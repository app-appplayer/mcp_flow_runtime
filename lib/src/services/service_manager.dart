/// System service integration for MCP Flow Runtime
import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

/// Service status enumeration per DDD spec
enum ServiceStatus {
  running,
  stopped,
  paused,
  failed,
  unknown,
}

/// Service exception with structured error information
class ServiceException implements Exception {
  final String serviceName;
  final String operation;
  final String message;
  final int? exitCode;

  const ServiceException({
    required this.serviceName,
    required this.operation,
    required this.message,
    this.exitCode,
  });

  @override
  String toString() =>
      'ServiceException: [$operation] $serviceName - $message'
      '${exitCode != null ? ' (exitCode: $exitCode)' : ''}';
}

/// Service configuration
class ServiceConfig {
  final String name;
  final String displayName;
  final String description;
  final String executablePath;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final String? user;
  final String? group;
  final bool autoRestart;
  final Duration restartDelay;
  final int maxRestarts;

  const ServiceConfig({
    required this.name,
    required this.displayName,
    required this.description,
    required this.executablePath,
    this.arguments = const [],
    this.environment = const {},
    this.workingDirectory,
    this.user,
    this.group,
    this.autoRestart = true,
    this.restartDelay = const Duration(seconds: 5),
    this.maxRestarts = 3,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'description': description,
    'executablePath': executablePath,
    'arguments': arguments,
    'environment': environment,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
    if (user != null) 'user': user,
    if (group != null) 'group': group,
    'autoRestart': autoRestart,
    'restartDelay': restartDelay.inSeconds,
    'maxRestarts': maxRestarts,
  };
}

/// Base service manager interface
abstract class ServiceManager {
  /// Install service
  Future<void> install(ServiceConfig config);

  /// Uninstall service
  Future<void> uninstall(String serviceName);

  /// Start service
  Future<void> start(String serviceName);

  /// Stop service
  Future<void> stop(String serviceName);

  /// Restart service
  Future<void> restart(String serviceName);

  /// Get service status
  Future<ServiceStatus> status(String serviceName);

  /// Check if service is installed
  Future<bool> isInstalled(String serviceName);

  /// Get service logs
  Future<List<String>> logs(String serviceName, {int lines = 100});
}

/// Factory for creating platform-specific service managers
class ServiceManagerFactory {
  /// Creates a platform-specific service manager.
  /// Pass [mock] = true to get a MockServiceManager for testing.
  static ServiceManager create({bool mock = false}) {
    if (mock) {
      return MockServiceManager();
    }
    if (Platform.isLinux) {
      return SystemdServiceManager();
    } else if (Platform.isWindows) {
      return WindowsServiceManager();
    } else if (Platform.isMacOS) {
      return LaunchdServiceManager();
    } else {
      return MockServiceManager();
    }
  }
}

/// Systemd service manager for Linux
class SystemdServiceManager implements ServiceManager {
  final Logger _logger = Logger('SystemdServiceManager');

  @override
  Future<void> install(ServiceConfig config) async {
    // Create systemd service file
    final serviceContent = _generateSystemdUnit(config);
    final servicePath = '/etc/systemd/system/${config.name}.service';

    try {
      // Write service file (requires sudo)
      final file = File(servicePath);
      await file.writeAsString(serviceContent);

      // Reload systemd
      await Process.run('systemctl', ['daemon-reload']);

      // Enable service for autostart
      if (config.autoRestart) {
        await Process.run('systemctl', ['enable', config.name]);
      }

      _logger.info('Installed systemd service: ${config.name}');
    } catch (e) {
      throw ServiceException(
        serviceName: config.name,
        operation: 'install',
        message: 'Failed to install systemd service: $e',
      );
    }
  }

  @override
  Future<void> uninstall(String serviceName) async {
    try {
      // Stop service if running
      await stop(serviceName);

      // Disable service
      await Process.run('systemctl', ['disable', serviceName]);

      // Remove service file
      final servicePath = '/etc/systemd/system/$serviceName.service';
      final file = File(servicePath);
      if (await file.exists()) {
        await file.delete();
      }

      // Reload systemd
      await Process.run('systemctl', ['daemon-reload']);

      _logger.info('Uninstalled systemd service: $serviceName');
    } catch (e) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'uninstall',
        message: 'Failed to uninstall systemd service: $e',
      );
    }
  }

  @override
  Future<void> start(String serviceName) async {
    final result = await Process.run('systemctl', ['start', serviceName]);
    if (result.exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'start',
        message: 'Failed to start service: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    final result = await Process.run('systemctl', ['stop', serviceName]);
    if (result.exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'stop',
        message: 'Failed to stop service: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> restart(String serviceName) async {
    final result = await Process.run('systemctl', ['restart', serviceName]);
    if (result.exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'restart',
        message: 'Failed to restart service: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    final result = await Process.run(
      'systemctl',
      ['is-active', serviceName],
    );

    switch (result.stdout.toString().trim()) {
      case 'active':
        return ServiceStatus.running;
      case 'inactive':
        return ServiceStatus.stopped;
      case 'failed':
        return ServiceStatus.failed;
      default:
        return ServiceStatus.unknown;
    }
  }

  @override
  Future<bool> isInstalled(String serviceName) async {
    final servicePath = '/etc/systemd/system/$serviceName.service';
    return File(servicePath).exists();
  }

  @override
  Future<List<String>> logs(String serviceName, {int lines = 100}) async {
    final result = await Process.run(
      'journalctl',
      ['-u', serviceName, '-n', lines.toString(), '--no-pager'],
    );

    if (result.exitCode != 0) {
      return [];
    }

    return result.stdout
        .toString()
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
  }

  String _generateSystemdUnit(ServiceConfig config) {
    final buffer = StringBuffer();

    // Unit section
    buffer.writeln('[Unit]');
    buffer.writeln('Description=${config.description}');
    buffer.writeln('After=network.target');
    buffer.writeln();

    // Service section
    buffer.writeln('[Service]');
    buffer.writeln('Type=simple');

    if (config.user != null) {
      buffer.writeln('User=${config.user}');
    }
    if (config.group != null) {
      buffer.writeln('Group=${config.group}');
    }
    if (config.workingDirectory != null) {
      buffer.writeln('WorkingDirectory=${config.workingDirectory}');
    }

    // Environment variables
    config.environment.forEach((key, value) {
      buffer.writeln('Environment="$key=$value"');
    });

    // Exec command
    final args = config.arguments.map((arg) => '"$arg"').join(' ');
    buffer.writeln('ExecStart=${config.executablePath} $args');

    // Restart policy: use on-failure per DDD spec
    if (config.autoRestart) {
      buffer.writeln('Restart=on-failure');
      buffer.writeln('RestartSec=${config.restartDelay.inSeconds}');
      buffer.writeln('StartLimitInterval=${config.maxRestarts * 60}');
      buffer.writeln('StartLimitBurst=${config.maxRestarts}');
    }

    buffer.writeln();

    // Install section
    buffer.writeln('[Install]');
    buffer.writeln('WantedBy=multi-user.target');

    return buffer.toString();
  }
}

/// Windows Service Manager
class WindowsServiceManager implements ServiceManager {
  final Logger _logger = Logger('WindowsServiceManager');

  @override
  Future<void> install(ServiceConfig config) async {
    try {
      // Create service using sc.exe
      final args = [
        'create',
        config.name,
        'binPath=', '"${config.executablePath} ${config.arguments.join(' ')}"',
        'DisplayName=', config.displayName,
        'start=', config.autoRestart ? 'auto' : 'demand',
      ];

      final result = await Process.run('sc.exe', args);
      if (result.exitCode != 0) {
        throw ServiceException(
          serviceName: config.name,
          operation: 'install',
          message: 'Failed to create service: ${result.stderr}',
          exitCode: result.exitCode,
        );
      }

      // Set description
      await Process.run('sc.exe', [
        'description',
        config.name,
        config.description,
      ]);

      _logger.info('Installed Windows service: ${config.name}');
    } catch (e) {
      if (e is ServiceException) rethrow;
      throw ServiceException(
        serviceName: config.name,
        operation: 'install',
        message: 'Failed to install Windows service: $e',
      );
    }
  }

  @override
  Future<void> uninstall(String serviceName) async {
    try {
      await stop(serviceName);

      final result = await Process.run('sc.exe', ['delete', serviceName]);
      if (result.exitCode != 0) {
        throw ServiceException(
          serviceName: serviceName,
          operation: 'uninstall',
          message: 'Failed to delete service: ${result.stderr}',
          exitCode: result.exitCode,
        );
      }

      _logger.info('Uninstalled Windows service: $serviceName');
    } catch (e) {
      if (e is ServiceException) rethrow;
      throw ServiceException(
        serviceName: serviceName,
        operation: 'uninstall',
        message: 'Failed to uninstall Windows service: $e',
      );
    }
  }

  @override
  Future<void> start(String serviceName) async {
    final result = await Process.run('net', ['start', serviceName]);
    if (result.exitCode != 0 && !result.stderr.toString().contains('already started')) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'start',
        message: 'Failed to start service: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    final result = await Process.run('net', ['stop', serviceName]);
    if (result.exitCode != 0 && !result.stderr.toString().contains('not started')) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'stop',
        message: 'Failed to stop service: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> restart(String serviceName) async {
    await stop(serviceName);
    await Future.delayed(Duration(seconds: 2));
    await start(serviceName);
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    final result = await Process.run('sc.exe', ['query', serviceName]);

    if (result.exitCode != 0) {
      return ServiceStatus.unknown;
    }

    final output = result.stdout.toString();
    if (output.contains('RUNNING')) {
      return ServiceStatus.running;
    } else if (output.contains('PAUSED')) {
      return ServiceStatus.paused;
    } else if (output.contains('STOPPED')) {
      return ServiceStatus.stopped;
    }

    return ServiceStatus.unknown;
  }

  @override
  Future<bool> isInstalled(String serviceName) async {
    final result = await Process.run('sc.exe', ['query', serviceName]);
    return result.exitCode == 0;
  }

  @override
  Future<List<String>> logs(String serviceName, {int lines = 100}) async {
    // Windows services typically log to Event Log
    _logger.warning('Windows service logs not fully implemented');
    return [];
  }
}

/// Launchd service manager for macOS
class LaunchdServiceManager implements ServiceManager {
  final Logger _logger = Logger('LaunchdServiceManager');

  /// Returns the launchd label using com.makemind.<name> convention
  String _label(String name) => 'com.makemind.$name';

  @override
  Future<void> install(ServiceConfig config) async {
    // Create launchd plist with com.makemind.* naming convention
    final label = _label(config.name);
    final plistContent = _generateLaunchdPlist(config);
    final plistPath = '/Library/LaunchDaemons/$label.plist';

    try {
      // Write plist file (requires sudo)
      final file = File(plistPath);
      await file.writeAsString(plistContent);

      // Load service
      await Process.run('launchctl', ['load', plistPath]);

      _logger.info('Installed launchd service: $label');
    } catch (e) {
      throw ServiceException(
        serviceName: config.name,
        operation: 'install',
        message: 'Failed to install launchd service: $e',
      );
    }
  }

  @override
  Future<void> uninstall(String serviceName) async {
    try {
      final label = _label(serviceName);
      final plistPath = '/Library/LaunchDaemons/$label.plist';

      // Unload service
      await Process.run('launchctl', ['unload', plistPath]);

      // Remove plist file
      final file = File(plistPath);
      if (await file.exists()) {
        await file.delete();
      }

      _logger.info('Uninstalled launchd service: $label');
    } catch (e) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'uninstall',
        message: 'Failed to uninstall launchd service: $e',
      );
    }
  }

  @override
  Future<void> start(String serviceName) async {
    final label = _label(serviceName);
    final result = await Process.run('launchctl', ['start', label]);
    if (result.exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'start',
        message: 'Failed to start service: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    final label = _label(serviceName);
    final result = await Process.run('launchctl', ['stop', label]);
    if (result.exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'stop',
        message: 'Failed to stop service: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> restart(String serviceName) async {
    await stop(serviceName);
    await Future.delayed(Duration(seconds: 2));
    await start(serviceName);
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    final label = _label(serviceName);
    final result = await Process.run('launchctl', ['list', label]);

    if (result.exitCode != 0) {
      return ServiceStatus.stopped;
    }

    // Parse output to determine status
    final output = result.stdout.toString();
    if (output.contains(label)) {
      return ServiceStatus.running;
    }

    return ServiceStatus.stopped;
  }

  @override
  Future<bool> isInstalled(String serviceName) async {
    final label = _label(serviceName);
    final plistPath = '/Library/LaunchDaemons/$label.plist';
    return File(plistPath).exists();
  }

  @override
  Future<List<String>> logs(String serviceName, {int lines = 100}) async {
    // macOS services typically log to system log
    final result = await Process.run(
      'log',
      ['show', '--predicate', 'process == "$serviceName"', '--last', '${lines}m'],
    );

    if (result.exitCode != 0) {
      return [];
    }

    return result.stdout
        .toString()
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();
  }

  String _generateLaunchdPlist(ServiceConfig config) {
    final label = _label(config.name);
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"');
    buffer.writeln('  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">');
    buffer.writeln('<plist version="1.0">');
    buffer.writeln('<dict>');

    buffer.writeln('  <key>Label</key>');
    buffer.writeln('  <string>$label</string>');

    buffer.writeln('  <key>ProgramArguments</key>');
    buffer.writeln('  <array>');
    buffer.writeln('    <string>${config.executablePath}</string>');
    for (final arg in config.arguments) {
      buffer.writeln('    <string>$arg</string>');
    }
    buffer.writeln('  </array>');

    if (config.workingDirectory != null) {
      buffer.writeln('  <key>WorkingDirectory</key>');
      buffer.writeln('  <string>${config.workingDirectory}</string>');
    }

    if (config.environment.isNotEmpty) {
      buffer.writeln('  <key>EnvironmentVariables</key>');
      buffer.writeln('  <dict>');
      config.environment.forEach((key, value) {
        buffer.writeln('    <key>$key</key>');
        buffer.writeln('    <string>$value</string>');
      });
      buffer.writeln('  </dict>');
    }

    if (config.autoRestart) {
      buffer.writeln('  <key>KeepAlive</key>');
      buffer.writeln('  <true/>');
      buffer.writeln('  <key>ThrottleInterval</key>');
      buffer.writeln('  <integer>${config.restartDelay.inSeconds}</integer>');
    }

    buffer.writeln('  <key>RunAtLoad</key>');
    buffer.writeln('  <true/>');

    buffer.writeln('</dict>');
    buffer.writeln('</plist>');

    return buffer.toString();
  }
}

/// Mock service manager for testing
class MockServiceManager implements ServiceManager {
  final Map<String, ServiceConfig> _services = {};
  final Map<String, ServiceStatus> _states = {};
  final Map<String, List<String>> _logs = {};

  @override
  Future<void> install(ServiceConfig config) async {
    _services[config.name] = config;
    _states[config.name] = ServiceStatus.stopped;
    _logs[config.name] = ['Service ${config.name} installed'];
  }

  @override
  Future<void> uninstall(String serviceName) async {
    _services.remove(serviceName);
    _states.remove(serviceName);
    _logs.remove(serviceName);
  }

  @override
  Future<void> start(String serviceName) async {
    if (!_services.containsKey(serviceName)) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'start',
        message: 'Service not found: $serviceName',
      );
    }
    _states[serviceName] = ServiceStatus.running;
    _logs[serviceName]?.add('Service $serviceName started');
  }

  @override
  Future<void> stop(String serviceName) async {
    if (!_services.containsKey(serviceName)) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'stop',
        message: 'Service not found: $serviceName',
      );
    }
    _states[serviceName] = ServiceStatus.stopped;
    _logs[serviceName]?.add('Service $serviceName stopped');
  }

  @override
  Future<void> restart(String serviceName) async {
    await stop(serviceName);
    await start(serviceName);
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    return _states[serviceName] ?? ServiceStatus.unknown;
  }

  @override
  Future<bool> isInstalled(String serviceName) async {
    return _services.containsKey(serviceName);
  }

  @override
  Future<List<String>> logs(String serviceName, {int lines = 100}) async {
    final logs = _logs[serviceName] ?? [];
    return logs.take(lines).toList();
  }

  /// Allows tests to inject specific status responses
  void setStatus(String serviceName, ServiceStatus status) {
    _states[serviceName] = status;
  }

  /// Allows tests to inject log lines
  void addLog(String serviceName, String message) {
    _logs.putIfAbsent(serviceName, () => []);
    _logs[serviceName]!.add(message);
  }
}
