/// System service integration for MCP Flow Runtime
import 'dart:io';
import 'package:logging/logging.dart';

/// Service configuration
class ServiceConfig {
  final String name;
  final String? displayName;
  final String description;
  final String executablePath;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final bool autoStart;
  final bool autoRestart;
  final Duration restartDelay;
  final int maxRestarts;

  ServiceConfig({
    required this.name,
    required this.description,
    required this.executablePath,
    this.displayName,
    this.arguments = const [],
    this.environment = const {},
    this.workingDirectory,
    this.autoStart = true,
    this.autoRestart = true,
    this.restartDelay = const Duration(seconds: 5),
    this.maxRestarts = 3,
  });
}

/// System service manager
abstract class SystemServiceManager {
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

  /// Retrieve service logs
  Future<String> logs(String serviceName, {int lines = 100});

  /// Factory method to create platform-specific manager
  static SystemServiceManager create() {
    if (Platform.isLinux) {
      return SystemdServiceManager();
    } else if (Platform.isMacOS) {
      return LaunchdServiceManager();
    } else if (Platform.isWindows) {
      return WindowsServiceManager();
    } else {
      throw UnsupportedError('Platform not supported for service integration');
    }
  }
}

/// Service status per DDD spec
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

  const ServiceException(
    this.message, {
    this.serviceName = '',
    this.operation = '',
    this.exitCode,
  });

  @override
  String toString() =>
      'ServiceException: [$operation] $serviceName - $message'
      '${exitCode != null ? ' (exitCode: $exitCode)' : ''}';
}

/// Systemd service manager for Linux
class SystemdServiceManager extends SystemServiceManager {
  final Logger _logger = Logger('SystemdServiceManager');

  @override
  Future<void> install(ServiceConfig config) async {
    final serviceName = '${config.name}.service';
    final serviceFile = File('/etc/systemd/system/$serviceName');

    // Generate systemd unit file with Restart=on-failure per DDD spec
    final unitContent = '''
[Unit]
Description=${config.description}
After=network.target

[Service]
Type=simple
ExecStart=${config.executablePath} ${config.arguments.join(' ')}
${config.workingDirectory != null ? 'WorkingDirectory=${config.workingDirectory}' : ''}
${config.environment.entries.map((e) => 'Environment="${e.key}=${e.value}"').join('\n')}
Restart=${config.autoRestart ? 'on-failure' : 'no'}
RestartSec=${config.restartDelay.inSeconds}
StartLimitBurst=${config.maxRestarts}

[Install]
WantedBy=multi-user.target
''';

    try {
      // Write service file (requires sudo)
      await serviceFile.writeAsString(unitContent);

      // Reload systemd
      await Process.run('systemctl', ['daemon-reload']);

      // Enable service if autoStart is true
      if (config.autoStart) {
        await Process.run('systemctl', ['enable', serviceName]);
      }

      _logger.info('Installed systemd service: $serviceName');
    } catch (e) {
      _logger.severe('Failed to install systemd service: $e');
      throw ServiceException(
        'Failed to install service: $e',
        serviceName: config.name,
        operation: 'install',
      );
    }
  }

  @override
  Future<void> uninstall(String serviceName) async {
    final serviceFile = File('/etc/systemd/system/$serviceName.service');

    try {
      // Stop and disable service
      await stop(serviceName);
      await Process.run('systemctl', ['disable', '$serviceName.service']);

      // Remove service file
      if (await serviceFile.exists()) {
        await serviceFile.delete();
      }

      // Reload systemd
      await Process.run('systemctl', ['daemon-reload']);

      _logger.info('Uninstalled systemd service: $serviceName');
    } catch (e) {
      _logger.severe('Failed to uninstall systemd service: $e');
      throw ServiceException(
        'Failed to uninstall service: $e',
        serviceName: serviceName,
        operation: 'uninstall',
      );
    }
  }

  @override
  Future<void> start(String serviceName) async {
    final result = await Process.run('systemctl', ['start', '$serviceName.service']);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to start service: ${result.stderr}',
        serviceName: serviceName,
        operation: 'start',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    final result = await Process.run('systemctl', ['stop', '$serviceName.service']);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to stop service: ${result.stderr}',
        serviceName: serviceName,
        operation: 'stop',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> restart(String serviceName) async {
    final result = await Process.run('systemctl', ['restart', '$serviceName.service']);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to restart service: ${result.stderr}',
        serviceName: serviceName,
        operation: 'restart',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    final result = await Process.run('systemctl', ['is-active', '$serviceName.service']);

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
    final serviceFile = File('/etc/systemd/system/$serviceName.service');
    return serviceFile.exists();
  }

  @override
  Future<String> logs(String serviceName, {int lines = 100}) async {
    final result = await Process.run(
      'journalctl',
      ['-u', '$serviceName.service', '-n', '$lines', '--no-pager'],
    );
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to retrieve logs: ${result.stderr}',
        serviceName: serviceName,
        operation: 'logs',
        exitCode: result.exitCode,
      );
    }
    return result.stdout.toString();
  }
}

/// Launchd service manager for macOS
class LaunchdServiceManager extends SystemServiceManager {
  final Logger _logger = Logger('LaunchdServiceManager');

  /// Returns the launchd label using com.makemind.<name> convention
  String _label(String name) => 'com.makemind.$name';

  @override
  Future<void> install(ServiceConfig config) async {
    final plistName = _label(config.name);
    final plistFile = File('/Library/LaunchDaemons/$plistName.plist');

    // Generate launchd plist
    final plistContent = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$plistName</string>
    <key>ProgramArguments</key>
    <array>
        <string>${config.executablePath}</string>
        ${config.arguments.map((arg) => '        <string>$arg</string>').join('\n')}
    </array>
    ${config.workingDirectory != null ? '''
    <key>WorkingDirectory</key>
    <string>${config.workingDirectory}</string>''' : ''}
    ${config.environment.isNotEmpty ? '''
    <key>EnvironmentVariables</key>
    <dict>
        ${config.environment.entries.map((e) => '''
        <key>${e.key}</key>
        <string>${e.value}</string>''').join('\n')}
    </dict>''' : ''}
    <key>RunAtLoad</key>
    <${config.autoStart}/>
    <key>KeepAlive</key>
    <${config.autoRestart}/>
</dict>
</plist>
''';

    try {
      // Write plist file (requires sudo)
      await plistFile.writeAsString(plistContent);

      // Load the service
      await Process.run('launchctl', ['load', plistFile.path]);

      _logger.info('Installed launchd service: $plistName');
    } catch (e) {
      _logger.severe('Failed to install launchd service: $e');
      throw ServiceException(
        'Failed to install service: $e',
        serviceName: config.name,
        operation: 'install',
      );
    }
  }

  @override
  Future<void> uninstall(String serviceName) async {
    final plistName = _label(serviceName);
    final plistFile = File('/Library/LaunchDaemons/$plistName.plist');

    try {
      // Unload the service
      if (await plistFile.exists()) {
        await Process.run('launchctl', ['unload', plistFile.path]);
        await plistFile.delete();
      }

      _logger.info('Uninstalled launchd service: $plistName');
    } catch (e) {
      _logger.severe('Failed to uninstall launchd service: $e');
      throw ServiceException(
        'Failed to uninstall service: $e',
        serviceName: serviceName,
        operation: 'uninstall',
      );
    }
  }

  @override
  Future<void> start(String serviceName) async {
    final plistName = _label(serviceName);
    final result = await Process.run('launchctl', ['start', plistName]);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to start service: ${result.stderr}',
        serviceName: serviceName,
        operation: 'start',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    final plistName = _label(serviceName);
    final result = await Process.run('launchctl', ['stop', plistName]);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to stop service: ${result.stderr}',
        serviceName: serviceName,
        operation: 'stop',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> restart(String serviceName) async {
    await stop(serviceName);
    await start(serviceName);
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    final plistName = _label(serviceName);
    final result = await Process.run('launchctl', ['list', plistName]);

    if (result.exitCode == 0) {
      // Parse output to determine status
      final output = result.stdout.toString();
      if (output.contains('PID')) {
        return ServiceStatus.running;
      }
    }

    return ServiceStatus.stopped;
  }

  @override
  Future<bool> isInstalled(String serviceName) async {
    final plistName = _label(serviceName);
    final plistFile = File('/Library/LaunchDaemons/$plistName.plist');
    return plistFile.exists();
  }

  @override
  Future<String> logs(String serviceName, {int lines = 100}) async {
    final plistName = _label(serviceName);
    final result = await Process.run(
      'log',
      ['show', '--predicate', 'eventMessage contains "$plistName"', '--last', '1h'],
    );
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to retrieve logs: ${result.stderr}',
        serviceName: serviceName,
        operation: 'logs',
        exitCode: result.exitCode,
      );
    }
    return result.stdout.toString();
  }
}

/// Windows service manager
class WindowsServiceManager extends SystemServiceManager {
  final Logger _logger = Logger('WindowsServiceManager');

  @override
  Future<void> install(ServiceConfig config) async {
    try {
      // Create service using sc.exe
      final args = [
        'create',
        config.name,
        'binPath=', config.executablePath,
        'DisplayName=', config.displayName ?? config.description,
        'start=', config.autoStart ? 'auto' : 'demand',
      ];

      final result = await Process.run('sc.exe', args);
      if (result.exitCode != 0) {
        throw ServiceException(
          'Failed to create service: ${result.stderr}',
          serviceName: config.name,
          operation: 'install',
          exitCode: result.exitCode,
        );
      }

      // Set recovery options if autoRestart is enabled
      if (config.autoRestart) {
        await Process.run('sc.exe', [
          'failure', config.name,
          'reset=', '86400',
          'actions=', 'restart/${config.restartDelay.inMilliseconds}',
        ]);
      }

      _logger.info('Installed Windows service: ${config.name}');
    } catch (e) {
      if (e is ServiceException) rethrow;
      _logger.severe('Failed to install Windows service: $e');
      throw ServiceException(
        'Failed to install service: $e',
        serviceName: config.name,
        operation: 'install',
      );
    }
  }

  @override
  Future<void> uninstall(String serviceName) async {
    try {
      // Stop service first
      await stop(serviceName);

      // Delete service
      final result = await Process.run('sc.exe', ['delete', serviceName]);
      if (result.exitCode != 0) {
        throw ServiceException(
          'Failed to delete service: ${result.stderr}',
          serviceName: serviceName,
          operation: 'uninstall',
          exitCode: result.exitCode,
        );
      }

      _logger.info('Uninstalled Windows service: $serviceName');
    } catch (e) {
      if (e is ServiceException) rethrow;
      _logger.severe('Failed to uninstall Windows service: $e');
      throw ServiceException(
        'Failed to uninstall service: $e',
        serviceName: serviceName,
        operation: 'uninstall',
      );
    }
  }

  @override
  Future<void> start(String serviceName) async {
    final result = await Process.run('net', ['start', serviceName]);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to start service: ${result.stderr}',
        serviceName: serviceName,
        operation: 'start',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    final result = await Process.run('net', ['stop', serviceName]);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to stop service: ${result.stderr}',
        serviceName: serviceName,
        operation: 'stop',
        exitCode: result.exitCode,
      );
    }
  }

  @override
  Future<void> restart(String serviceName) async {
    await stop(serviceName);
    await start(serviceName);
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    final result = await Process.run('sc.exe', ['query', serviceName]);

    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      if (output.contains('RUNNING')) {
        return ServiceStatus.running;
      } else if (output.contains('STOPPED')) {
        return ServiceStatus.stopped;
      } else if (output.contains('PAUSED')) {
        return ServiceStatus.paused;
      }
    }

    return ServiceStatus.unknown;
  }

  @override
  Future<bool> isInstalled(String serviceName) async {
    final result = await Process.run('sc.exe', ['query', serviceName]);
    return result.exitCode == 0;
  }

  @override
  Future<String> logs(String serviceName, {int lines = 100}) async {
    // Windows event log query for the service
    final result = await Process.run('wevtutil', [
      'qe', 'System',
      '/q:*[System[Provider[@Name="$serviceName"]]]',
      '/c:$lines',
      '/f:text',
    ]);
    if (result.exitCode != 0) {
      throw ServiceException(
        'Failed to retrieve logs: ${result.stderr}',
        serviceName: serviceName,
        operation: 'logs',
        exitCode: result.exitCode,
      );
    }
    return result.stdout.toString();
  }
}
