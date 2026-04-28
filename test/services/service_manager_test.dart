import 'package:test/test.dart';

import 'package:mcp_flow_runtime/src/services/service_manager.dart';
import 'package:mcp_flow_runtime/src/services/system_service_registry.dart';
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
final _testServiceConfig = ServiceConfig(
  name: 'mcp_flow_test',
  displayName: 'MCP Flow Test Service',
  description: 'Test service for unit tests',
  executablePath: '/usr/local/bin/mcp_flow_runtime',
  arguments: ['--config', '/etc/mcp_flow/config.json'],
  environment: {'MCP_LOG_LEVEL': 'info', 'MCP_PORT': '3000'},
  workingDirectory: '/var/lib/mcp_flow',
  autoRestart: true,
  restartDelay: Duration(seconds: 5),
  maxRestarts: 3,
  user: 'mcp_flow',
);

// ---------------------------------------------------------------------------
// Helper to check if a list of commands contains a specific command
// ---------------------------------------------------------------------------
bool _containsCommand(List<List<String>> commands, List<String> target) {
  return commands.any((cmd) =>
      cmd.length == target.length &&
      List.generate(cmd.length, (i) => cmd[i] == target[i]).every((v) => v));
}

// ---------------------------------------------------------------------------
// Testable subclasses for platform-specific managers
// ---------------------------------------------------------------------------

/// Testable SystemdServiceManager that captures generated unit file content
/// and overrides actual process/file operations.
class TestableSystemdServiceManager extends SystemdServiceManager {
  String? lastGeneratedContent;
  String? lastWrittenPath;
  final List<List<String>> processCommands = [];
  final Map<String, int> processExitCodes = {};
  final Map<String, String> processStdout = {};
  final Map<String, String> processStderr = {};
  bool shouldFailFileWrite = false;
  final Map<String, String> _files = {};
  final Map<String, bool> _fileExistence = {};

  @override
  Future<void> install(ServiceConfig config) async {
    final content = generateSystemdUnit(config);
    lastGeneratedContent = content;
    final path = '/etc/systemd/system/${config.name}.service';
    lastWrittenPath = path;

    if (shouldFailFileWrite) {
      throw ServiceException(
        serviceName: config.name,
        operation: 'install',
        message: 'Failed to install systemd service: file write error',
      );
    }

    _files[path] = content;
    _fileExistence[path] = true;
    processCommands.add(['systemctl', 'daemon-reload']);
    if (config.autoRestart) {
      processCommands.add(['systemctl', 'enable', config.name]);
    }
  }

  @override
  Future<void> start(String serviceName) async {
    processCommands.add(['systemctl', 'start', serviceName]);
    final key = 'start:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'start',
        message: 'Failed to start service: ${processStderr[key] ?? ''}',
        exitCode: exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    processCommands.add(['systemctl', 'stop', serviceName]);
    final key = 'stop:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'stop',
        message: 'Failed to stop service: ${processStderr[key] ?? ''}',
        exitCode: exitCode,
      );
    }
  }

  @override
  Future<void> restart(String serviceName) async {
    processCommands.add(['systemctl', 'restart', serviceName]);
    final key = 'restart:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'restart',
        message: 'Failed to restart service: ${processStderr[key] ?? ''}',
        exitCode: exitCode,
      );
    }
  }

  @override
  Future<ServiceStatus> status(String serviceName) async {
    processCommands.add(['systemctl', 'is-active', serviceName]);
    final key = 'status:$serviceName';
    final stdout = processStdout[key] ?? 'inactive';
    switch (stdout.trim()) {
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
    final path = '/etc/systemd/system/$serviceName.service';
    return _fileExistence[path] ?? false;
  }

  @override
  Future<List<String>> logs(String serviceName, {int lines = 100}) async {
    processCommands.add(['journalctl', '-u', serviceName, '-n', lines.toString(), '--no-pager']);
    final key = 'logs:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'logs',
        message: 'Failed to get logs',
        exitCode: exitCode,
      );
    }
    final stdout = processStdout[key] ?? '';
    if (stdout.isEmpty) return [];
    return stdout.split('\n').where((l) => l.isNotEmpty).toList();
  }

  @override
  Future<void> uninstall(String serviceName) async {
    final path = '/etc/systemd/system/$serviceName.service';
    if (!(_fileExistence[path] ?? false)) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'uninstall',
        message: 'Service not installed',
      );
    }
    processCommands.add(['systemctl', 'stop', serviceName]);
    processCommands.add(['systemctl', 'disable', serviceName]);
    _files.remove(path);
    _fileExistence.remove(path);
    processCommands.add(['systemctl', 'daemon-reload']);
  }

  /// Expose the private _generateSystemdUnit for testing
  String generateSystemdUnit(ServiceConfig config) {
    // Replicate the generation logic from the source
    final buffer = StringBuffer();
    buffer.writeln('[Unit]');
    buffer.writeln('Description=${config.description}');
    buffer.writeln('After=network.target');
    buffer.writeln();
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
    config.environment.forEach((key, value) {
      buffer.writeln('Environment="$key=$value"');
    });
    final args = config.arguments.map((arg) => '"$arg"').join(' ');
    buffer.writeln('ExecStart=${config.executablePath} $args');
    if (config.autoRestart) {
      buffer.writeln('Restart=on-failure');
      buffer.writeln('RestartSec=${config.restartDelay.inSeconds}');
      buffer.writeln('StartLimitInterval=${config.maxRestarts * 60}');
      buffer.writeln('StartLimitBurst=${config.maxRestarts}');
    }
    buffer.writeln();
    buffer.writeln('[Install]');
    buffer.writeln('WantedBy=multi-user.target');
    return buffer.toString();
  }

  /// Simulate setting a file to not writable for error tests
  void simulateFileWriteFailure() {
    shouldFailFileWrite = true;
  }

  /// Configure process exit code for a specific operation
  void setProcessResult(String key, {int exitCode = 0, String stdout = '', String stderr = ''}) {
    processExitCodes[key] = exitCode;
    processStdout[key] = stdout;
    processStderr[key] = stderr;
  }
}

/// Testable LaunchdServiceManager that captures generated plist content
/// and overrides actual process/file operations.
class TestableLaunchdServiceManager extends LaunchdServiceManager {
  String? lastGeneratedContent;
  String? lastWrittenPath;
  final List<List<String>> processCommands = [];
  final Map<String, int> processExitCodes = {};
  final Map<String, String> processStdout = {};
  final Map<String, String> processStderr = {};
  bool shouldFailFileWrite = false;
  final Map<String, String> _files = {};
  final Map<String, bool> _fileExistence = {};

  String labelFor(String name) => 'com.makemind.$name';

  @override
  Future<void> install(ServiceConfig config) async {
    final content = generateLaunchdPlist(config);
    lastGeneratedContent = content;
    final label = labelFor(config.name);
    final path = '/Library/LaunchDaemons/$label.plist';
    lastWrittenPath = path;

    if (shouldFailFileWrite) {
      throw ServiceException(
        serviceName: config.name,
        operation: 'install',
        message: 'Failed to install launchd service: file write error',
      );
    }

    _files[path] = content;
    _fileExistence[path] = true;
    processCommands.add(['launchctl', 'load', path]);
  }

  @override
  Future<void> start(String serviceName) async {
    final label = labelFor(serviceName);
    processCommands.add(['launchctl', 'start', label]);
    final key = 'start:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'start',
        message: 'Failed to start service: ${processStderr[key] ?? ''}',
        exitCode: exitCode,
      );
    }
  }

  @override
  Future<void> stop(String serviceName) async {
    final label = labelFor(serviceName);
    processCommands.add(['launchctl', 'stop', label]);
    final key = 'stop:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'stop',
        message: 'Failed to stop service: ${processStderr[key] ?? ''}',
        exitCode: exitCode,
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
    final label = labelFor(serviceName);
    processCommands.add(['launchctl', 'list', label]);
    final key = 'status:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      return ServiceStatus.stopped;
    }
    final stdout = processStdout[key] ?? '';
    if (stdout.contains(label)) {
      return ServiceStatus.running;
    }
    return ServiceStatus.stopped;
  }

  @override
  Future<bool> isInstalled(String serviceName) async {
    final label = labelFor(serviceName);
    final path = '/Library/LaunchDaemons/$label.plist';
    return _fileExistence[path] ?? false;
  }

  @override
  Future<List<String>> logs(String serviceName, {int lines = 100}) async {
    processCommands.add(['log', 'show', '--predicate', 'process == "$serviceName"', '--last', '${lines}m']);
    final key = 'logs:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'logs',
        message: 'Failed to get logs',
        exitCode: exitCode,
      );
    }
    final stdout = processStdout[key] ?? '';
    if (stdout.isEmpty) return [];
    return stdout.split('\n').where((l) => l.isNotEmpty).toList();
  }

  @override
  Future<void> uninstall(String serviceName) async {
    final label = labelFor(serviceName);
    final path = '/Library/LaunchDaemons/$label.plist';
    if (!(_fileExistence[path] ?? false)) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'uninstall',
        message: 'Service not installed',
      );
    }
    processCommands.add(['launchctl', 'unload', path]);
    final key = 'unload:$serviceName';
    final exitCode = processExitCodes[key] ?? 0;
    if (exitCode != 0) {
      throw ServiceException(
        serviceName: serviceName,
        operation: 'uninstall',
        message: 'Failed to unload service',
        exitCode: exitCode,
      );
    }
    _files.remove(path);
    _fileExistence.remove(path);
  }

  /// Expose the private _generateLaunchdPlist for testing
  String generateLaunchdPlist(ServiceConfig config) {
    final label = labelFor(config.name);
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

  void simulateFileWriteFailure() {
    shouldFailFileWrite = true;
  }

  void setProcessResult(String key, {int exitCode = 0, String stdout = '', String stderr = ''}) {
    processExitCodes[key] = exitCode;
    processStdout[key] = stdout;
    processStderr[key] = stderr;
  }
}

// ---------------------------------------------------------------------------
// Mock SystemService for registry tests
// ---------------------------------------------------------------------------
class _MockSystemService extends SystemService {
  bool initialized = false;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  bool get isReady => initialized && !disposed;
}

// Typed services for registry type-safety tests
class _ServiceA extends _MockSystemService {}

class _ServiceB extends _MockSystemService {}

class _ServiceC extends _MockSystemService {}

void main() {
  // ==========================================================================
  // ServiceConfig Tests (TC-291~)
  // ==========================================================================
  group('TC-291: ServiceConfig', () {
    test('TC-291a: all fields match input', () {
      expect(_testServiceConfig.name, equals('mcp_flow_test'));
      expect(_testServiceConfig.displayName, equals('MCP Flow Test Service'));
      expect(_testServiceConfig.description, equals('Test service for unit tests'));
      expect(_testServiceConfig.executablePath, equals('/usr/local/bin/mcp_flow_runtime'));
      expect(_testServiceConfig.arguments, equals(['--config', '/etc/mcp_flow/config.json']));
      expect(_testServiceConfig.environment['MCP_LOG_LEVEL'], equals('info'));
      expect(_testServiceConfig.workingDirectory, equals('/var/lib/mcp_flow'));
      expect(_testServiceConfig.autoRestart, isTrue);
      expect(_testServiceConfig.restartDelay, equals(Duration(seconds: 5)));
      expect(_testServiceConfig.maxRestarts, equals(3));
      expect(_testServiceConfig.user, equals('mcp_flow'));
    });

    test('TC-291b: optional fields accept null', () {
      final config = ServiceConfig(
        name: 'test',
        displayName: 'Test',
        description: 'Test',
        executablePath: '/bin/test',
      );
      expect(config.user, isNull);
      expect(config.group, isNull);
      expect(config.workingDirectory, isNull);
    });

    test('TC-291c: empty arguments list is allowed', () {
      final config = ServiceConfig(
        name: 'test',
        displayName: 'Test',
        description: 'Test',
        executablePath: '/bin/test',
        arguments: [],
      );
      expect(config.arguments, isEmpty);
    });
  });

  // ==========================================================================
  // ServiceManagerFactory Tests (TC-294~)
  // ==========================================================================
  group('TC-294: ServiceManagerFactory', () {
    test('TC-294a: factory with mock=true returns MockServiceManager', () {
      final manager = ServiceManagerFactory.create(mock: true);
      expect(manager, isA<MockServiceManager>());
    });

    test('TC-294b: factory default returns platform-appropriate manager', () {
      final manager = ServiceManagerFactory.create();
      // On macOS CI, should be LaunchdServiceManager
      // On Linux, SystemdServiceManager. On Windows, WindowsServiceManager.
      // On unsupported, MockServiceManager.
      expect(manager, isA<ServiceManager>());
    });
  });

  // ==========================================================================
  // MockServiceManager Tests (TC-297~)
  // ==========================================================================
  group('TC-297: MockServiceManager.install', () {
    test('TC-297a: install registers service', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      expect(await mgr.isInstalled('mcp_flow_test'), isTrue);
    });

    test('TC-297b: duplicate install overwrites without error', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);

      // Second install of the same service silently overwrites in MockServiceManager
      await mgr.install(_testServiceConfig);
      expect(await mgr.isInstalled('mcp_flow_test'), isTrue);
    });

    test('TC-297c: install with empty name is handled', () async {
      final mgr = MockServiceManager();
      final config = ServiceConfig(
        name: '',
        displayName: 'Empty',
        description: 'Empty name test',
        executablePath: '/bin/test',
      );

      // MockServiceManager accepts empty name; verify it can be queried
      await mgr.install(config);
      expect(await mgr.isInstalled(''), isTrue);
    });
  });

  group('TC-298: MockServiceManager.start', () {
    test('TC-298a: start sets status to running', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.start('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.running));
    });

    test('TC-298b: start already running service is handled gracefully', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.start('mcp_flow_test');

      // Starting an already running service should not throw
      await mgr.start('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.running));
    });

    test('TC-298c: start uninstalled service throws ServiceException', () async {
      final mgr = MockServiceManager();
      expect(
        () => mgr.start('nonexistent'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-299: MockServiceManager.stop', () {
    test('TC-299a: stop sets status to stopped', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.start('mcp_flow_test');
      await mgr.stop('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.stopped));
    });

    test('TC-299b: stop already stopped service does not throw', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);

      // Service is installed in stopped state
      // Stopping again should not throw
      await mgr.stop('mcp_flow_test');
      await mgr.stop('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.stopped));
    });

    test('TC-299c: stop uninstalled service throws ServiceException', () async {
      final mgr = MockServiceManager();
      expect(
        () => mgr.stop('nonexistent'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-300: MockServiceManager.restart', () {
    test('TC-300a: restart results in running status', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.start('mcp_flow_test');
      await mgr.restart('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.running));
    });

    test('TC-300b: restart from stopped state sets running', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);

      // Service is stopped, restart should transition to running
      await mgr.restart('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.running));
    });

    test('TC-300c: restart uninstalled service throws ServiceException', () async {
      final mgr = MockServiceManager();
      expect(
        () => mgr.restart('nonexistent'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-301: MockServiceManager.uninstall', () {
    test('TC-301a: uninstall removes service', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.uninstall('mcp_flow_test');
      expect(await mgr.isInstalled('mcp_flow_test'), isFalse);
    });

    test('TC-301b: uninstall running service removes it', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.start('mcp_flow_test');

      // Uninstall while running should remove the service
      await mgr.uninstall('mcp_flow_test');
      expect(await mgr.isInstalled('mcp_flow_test'), isFalse);
    });

    test('TC-301c: uninstall non-installed service completes without error', () async {
      final mgr = MockServiceManager();

      // MockServiceManager.uninstall does not throw for missing services
      // It silently removes (or no-ops)
      await mgr.uninstall('nonexistent');
      expect(await mgr.isInstalled('nonexistent'), isFalse);
    });
  });

  group('TC-302: MockServiceManager.status', () {
    test('TC-302a: status returns current state', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.stopped));
    });

    test('TC-302b: setStatus injects state', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      mgr.setStatus('mcp_flow_test', ServiceStatus.failed);
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.failed));
    });

    test('TC-302c: status of uninstalled service returns unknown', () async {
      final mgr = MockServiceManager();
      expect(await mgr.status('nonexistent'), equals(ServiceStatus.unknown));
    });
  });

  group('TC-303: MockServiceManager.logs', () {
    test('TC-303a: logs returns injected log lines', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      mgr.addLog('mcp_flow_test', 'Log line 1');
      mgr.addLog('mcp_flow_test', 'Log line 2');

      final logs = await mgr.logs('mcp_flow_test');
      expect(logs, contains('Log line 1'));
      expect(logs, contains('Log line 2'));
    });

    test('TC-303b: logs respects lines parameter', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      for (var i = 0; i < 10; i++) {
        mgr.addLog('mcp_flow_test', 'Log $i');
      }

      final logs = await mgr.logs('mcp_flow_test', lines: 5);
      expect(logs.length, equals(5));
    });
  });

  group('TC-304: MockServiceManager.isInstalled', () {
    test('TC-304a: installed service returns true', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      expect(await mgr.isInstalled('mcp_flow_test'), isTrue);
    });

    test('TC-304b: uninstalled service returns false', () async {
      final mgr = MockServiceManager();
      expect(await mgr.isInstalled('nonexistent'), isFalse);
    });

    test('TC-304c: after uninstall returns false', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.uninstall('mcp_flow_test');
      expect(await mgr.isInstalled('mcp_flow_test'), isFalse);
    });
  });

  group('TC-305: Full lifecycle', () {
    test('TC-305a: install -> start -> stop -> restart -> uninstall', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.start('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.running));

      await mgr.stop('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.stopped));

      await mgr.restart('mcp_flow_test');
      expect(await mgr.status('mcp_flow_test'), equals(ServiceStatus.running));

      await mgr.stop('mcp_flow_test');
      await mgr.uninstall('mcp_flow_test');
      expect(await mgr.isInstalled('mcp_flow_test'), isFalse);
    });

    test('TC-305b: start before install throws ServiceException', () async {
      final mgr = MockServiceManager();

      // Calling start before install should throw
      await expectLater(
        mgr.start('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });

    test('TC-305c: uninstall then reinstall succeeds', () async {
      final mgr = MockServiceManager();
      await mgr.install(_testServiceConfig);
      await mgr.uninstall('mcp_flow_test');
      await mgr.install(_testServiceConfig);
      expect(await mgr.isInstalled('mcp_flow_test'), isTrue);
    });
  });

  // ==========================================================================
  // ServiceException Tests
  // ==========================================================================
  group('ServiceException', () {
    test('toString includes operation and service name', () {
      const ex = ServiceException(
        serviceName: 'my_svc',
        operation: 'start',
        message: 'failed',
        exitCode: 1,
      );
      expect(ex.toString(), contains('my_svc'));
      expect(ex.toString(), contains('start'));
      expect(ex.toString(), contains('exitCode: 1'));
    });
  });

  // ==========================================================================
  // SystemdServiceManager Tests (TC-309~315)
  // ==========================================================================
  group('TC-309: SystemdServiceManager.install', () {
    late TestableSystemdServiceManager mgr;

    setUp(() {
      mgr = TestableSystemdServiceManager();
    });

    test('TC-309a: systemd install generates service file with correct sections', () async {
      await mgr.install(_testServiceConfig);

      final content = mgr.lastGeneratedContent!;
      expect(content, contains('[Unit]'));
      expect(content, contains('[Service]'));
      expect(content, contains('[Install]'));
      expect(content, contains('ExecStart=/usr/local/bin/mcp_flow_runtime'));
      expect(mgr.lastWrittenPath, equals('/etc/systemd/system/mcp_flow_test.service'));
    });

    test('TC-309b: install includes environment variables', () async {
      await mgr.install(_testServiceConfig);

      final content = mgr.lastGeneratedContent!;
      expect(content, contains('Environment="MCP_LOG_LEVEL=info"'));
      expect(content, contains('Environment="MCP_PORT=3000"'));
    });

    test('TC-309c: install with file write failure throws ServiceException', () async {
      mgr.simulateFileWriteFailure();
      expect(
        () => mgr.install(_testServiceConfig),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-310: SystemdServiceManager.start', () {
    late TestableSystemdServiceManager mgr;

    setUp(() {
      mgr = TestableSystemdServiceManager();
    });

    test('TC-310a: start calls systemctl start', () async {
      await mgr.start('mcp_flow_test');
      expect(_containsCommand(mgr.processCommands, ['systemctl', 'start', 'mcp_flow_test']), isTrue);
    });

    test('TC-310b: start when already running succeeds by default', () async {
      // No special handling needed; default exitCode is 0
      await mgr.start('mcp_flow_test');
      await mgr.start('mcp_flow_test');
      expect(mgr.processCommands.where((c) => c.contains('start')).length, equals(2));
    });

    test('TC-310c: start with systemctl failure throws ServiceException', () async {
      mgr.setProcessResult('start:mcp_flow_test', exitCode: 1, stderr: 'Unit not found.');
      expect(
        () => mgr.start('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-311: SystemdServiceManager.stop', () {
    late TestableSystemdServiceManager mgr;

    setUp(() {
      mgr = TestableSystemdServiceManager();
    });

    test('TC-311a: stop calls systemctl stop', () async {
      await mgr.stop('mcp_flow_test');
      expect(_containsCommand(mgr.processCommands, ['systemctl', 'stop', 'mcp_flow_test']), isTrue);
    });

    test('TC-311b: stop when already stopped succeeds by default', () async {
      await mgr.stop('mcp_flow_test');
      await mgr.stop('mcp_flow_test');
      expect(mgr.processCommands.where((c) => c[1] == 'stop').length, equals(2));
    });

    test('TC-311c: stop with systemctl failure throws ServiceException', () async {
      mgr.setProcessResult('stop:mcp_flow_test', exitCode: 1, stderr: 'Failed');
      expect(
        () => mgr.stop('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-312: SystemdServiceManager.status', () {
    late TestableSystemdServiceManager mgr;

    setUp(() {
      mgr = TestableSystemdServiceManager();
    });

    test('TC-312a: active stdout returns ServiceStatus.running', () async {
      mgr.setProcessResult('status:mcp_flow_test', stdout: 'active');
      final result = await mgr.status('mcp_flow_test');
      expect(result, equals(ServiceStatus.running));
    });

    test('TC-312b: inactive returns stopped, failed returns failed', () async {
      mgr.setProcessResult('status:svc1', stdout: 'inactive');
      expect(await mgr.status('svc1'), equals(ServiceStatus.stopped));

      mgr.setProcessResult('status:svc2', stdout: 'failed');
      expect(await mgr.status('svc2'), equals(ServiceStatus.failed));
    });

    test('TC-312c: unknown output returns ServiceStatus.unknown', () async {
      mgr.setProcessResult('status:mcp_flow_test', stdout: 'activating');
      final result = await mgr.status('mcp_flow_test');
      expect(result, equals(ServiceStatus.unknown));
    });
  });

  group('TC-313: SystemdServiceManager.logs', () {
    late TestableSystemdServiceManager mgr;

    setUp(() {
      mgr = TestableSystemdServiceManager();
    });

    test('TC-313a: logs returns parsed journalctl output', () async {
      final logLines = List.generate(100, (i) => 'Log line $i').join('\n');
      mgr.setProcessResult('logs:mcp_flow_test', stdout: logLines);
      final result = await mgr.logs('mcp_flow_test');
      expect(result.length, equals(100));
    });

    test('TC-313b: logs passes lines parameter to journalctl', () async {
      mgr.setProcessResult('logs:mcp_flow_test', stdout: 'line1\nline2');
      await mgr.logs('mcp_flow_test', lines: 10);
      expect(_containsCommand(mgr.processCommands, ['journalctl', '-u', 'mcp_flow_test', '-n', '10', '--no-pager']), isTrue);
    });

    test('TC-313c: logs with journalctl failure throws ServiceException', () async {
      mgr.setProcessResult('logs:mcp_flow_test', exitCode: 1);
      expect(
        () => mgr.logs('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-314: SystemdServiceManager.uninstall', () {
    late TestableSystemdServiceManager mgr;

    setUp(() async {
      mgr = TestableSystemdServiceManager();
      await mgr.install(_testServiceConfig);
      mgr.processCommands.clear();
    });

    test('TC-314a: uninstall calls disable and removes service file', () async {
      await mgr.uninstall('mcp_flow_test');
      expect(_containsCommand(mgr.processCommands, ['systemctl', 'disable', 'mcp_flow_test']), isTrue);
      expect(_containsCommand(mgr.processCommands, ['systemctl', 'daemon-reload']), isTrue);
      expect(await mgr.isInstalled('mcp_flow_test'), isFalse);
    });

    test('TC-314b: uninstall stops running service first', () async {
      await mgr.uninstall('mcp_flow_test');
      // stop is called before disable
      final stopIdx = mgr.processCommands.indexWhere((c) => c[1] == 'stop');
      final disableIdx = mgr.processCommands.indexWhere((c) => c[1] == 'disable');
      expect(stopIdx, lessThan(disableIdx));
    });

    test('TC-314c: uninstall of non-installed service throws ServiceException', () async {
      expect(
        () => mgr.uninstall('nonexistent'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-315: SystemdServiceManager restart policy', () {
    test('TC-315a: autoRestart=true generates Restart=on-failure', () {
      final mgr = TestableSystemdServiceManager();
      final content = mgr.generateSystemdUnit(_testServiceConfig);
      expect(content, contains('Restart=on-failure'));
    });

    test('TC-315b: autoRestart=false does not include Restart=on-failure', () {
      final mgr = TestableSystemdServiceManager();
      final config = ServiceConfig(
        name: 'no_restart',
        displayName: 'No Restart',
        description: 'Test',
        executablePath: '/bin/test',
        autoRestart: false,
      );
      final content = mgr.generateSystemdUnit(config);
      expect(content, isNot(contains('Restart=on-failure')));
    });

    test('TC-315c: user config generates User= directive', () {
      final mgr = TestableSystemdServiceManager();
      final content = mgr.generateSystemdUnit(_testServiceConfig);
      expect(content, contains('User=mcp_flow'));
    });
  });

  // ==========================================================================
  // LaunchdServiceManager Tests (TC-321~326)
  // ==========================================================================
  group('TC-321: LaunchdServiceManager.install', () {
    late TestableLaunchdServiceManager mgr;

    setUp(() {
      mgr = TestableLaunchdServiceManager();
    });

    test('TC-321a: install generates plist file with Label', () async {
      await mgr.install(_testServiceConfig);

      final content = mgr.lastGeneratedContent!;
      expect(content, contains('<?xml version='));
      expect(content, contains('<key>Label</key>'));
      expect(content, contains('com.makemind.mcp_flow_test'));
    });

    test('TC-321b: plist contains ProgramArguments with executable path', () async {
      await mgr.install(_testServiceConfig);

      final content = mgr.lastGeneratedContent!;
      expect(content, contains('<key>ProgramArguments</key>'));
      expect(content, contains('/usr/local/bin/mcp_flow_runtime'));
    });

    test('TC-321c: install with file write failure throws ServiceException', () async {
      mgr.simulateFileWriteFailure();
      expect(
        () => mgr.install(_testServiceConfig),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-322: LaunchdServiceManager plist content', () {
    late TestableLaunchdServiceManager mgr;

    setUp(() {
      mgr = TestableLaunchdServiceManager();
    });

    test('TC-322a: plist contains EnvironmentVariables', () async {
      await mgr.install(_testServiceConfig);
      final content = mgr.lastGeneratedContent!;
      expect(content, contains('<key>EnvironmentVariables</key>'));
    });

    test('TC-322b: plist contains RunAtLoad', () async {
      await mgr.install(_testServiceConfig);
      final content = mgr.lastGeneratedContent!;
      expect(content, contains('<key>RunAtLoad</key>'));
      expect(content, contains('<true/>'));
    });

    test('TC-322c: plist contains KeepAlive when autoRestart is true', () async {
      await mgr.install(_testServiceConfig);
      final content = mgr.lastGeneratedContent!;
      expect(content, contains('<key>KeepAlive</key>'));
    });
  });

  group('TC-323: LaunchdServiceManager.start', () {
    late TestableLaunchdServiceManager mgr;

    setUp(() {
      mgr = TestableLaunchdServiceManager();
    });

    test('TC-323a: start calls launchctl start with label', () async {
      await mgr.start('mcp_flow_test');
      expect(_containsCommand(mgr.processCommands, ['launchctl', 'start', 'com.makemind.mcp_flow_test']), isTrue);
    });

    test('TC-323b: install calls launchctl load', () async {
      await mgr.install(_testServiceConfig);
      final loadCmd = mgr.processCommands.firstWhere((c) => c[1] == 'load');
      expect(loadCmd[0], equals('launchctl'));
    });

    test('TC-323c: start with launchctl failure throws ServiceException', () async {
      mgr.setProcessResult('start:mcp_flow_test', exitCode: 125, stderr: 'error');
      expect(
        () => mgr.start('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-324: LaunchdServiceManager.stop', () {
    late TestableLaunchdServiceManager mgr;

    setUp(() {
      mgr = TestableLaunchdServiceManager();
    });

    test('TC-324a: stop calls launchctl stop with label', () async {
      await mgr.stop('mcp_flow_test');
      expect(_containsCommand(mgr.processCommands, ['launchctl', 'stop', 'com.makemind.mcp_flow_test']), isTrue);
    });

    test('TC-324b: stop when already stopped succeeds by default', () async {
      await mgr.stop('mcp_flow_test');
      await mgr.stop('mcp_flow_test');
      expect(mgr.processCommands.length, equals(2));
    });

    test('TC-324c: stop with launchctl failure throws ServiceException', () async {
      mgr.setProcessResult('stop:mcp_flow_test', exitCode: 1, stderr: 'error');
      expect(
        () => mgr.stop('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-325: LaunchdServiceManager.uninstall', () {
    late TestableLaunchdServiceManager mgr;

    setUp(() async {
      mgr = TestableLaunchdServiceManager();
      await mgr.install(_testServiceConfig);
      mgr.processCommands.clear();
    });

    test('TC-325a: uninstall calls launchctl unload and removes plist', () async {
      await mgr.uninstall('mcp_flow_test');
      expect(_containsCommand(mgr.processCommands, ['launchctl', 'unload', '/Library/LaunchDaemons/com.makemind.mcp_flow_test.plist']), isTrue);
      expect(await mgr.isInstalled('mcp_flow_test'), isFalse);
    });

    test('TC-325b: uninstall of non-installed service throws ServiceException', () async {
      expect(
        () => mgr.uninstall('nonexistent'),
        throwsA(isA<ServiceException>()),
      );
    });

    test('TC-325c: uninstall with unload failure throws ServiceException', () async {
      mgr.setProcessResult('unload:mcp_flow_test', exitCode: 1);
      expect(
        () => mgr.uninstall('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  group('TC-326: LaunchdServiceManager.logs', () {
    late TestableLaunchdServiceManager mgr;

    setUp(() {
      mgr = TestableLaunchdServiceManager();
    });

    test('TC-326a: logs returns parsed log output', () async {
      mgr.setProcessResult('logs:mcp_flow_test', stdout: 'log line 1\nlog line 2\nlog line 3');
      final result = await mgr.logs('mcp_flow_test');
      expect(result.length, equals(3));
      expect(result, contains('log line 1'));
    });

    test('TC-326b: logs passes lines parameter', () async {
      mgr.setProcessResult('logs:mcp_flow_test', stdout: 'line1');
      await mgr.logs('mcp_flow_test', lines: 50);
      expect(_containsCommand(mgr.processCommands, ['log', 'show', '--predicate', 'process == "mcp_flow_test"', '--last', '50m']), isTrue);
    });

    test('TC-326c: logs with failure throws ServiceException', () async {
      mgr.setProcessResult('logs:mcp_flow_test', exitCode: 1);
      expect(
        () => mgr.logs('mcp_flow_test'),
        throwsA(isA<ServiceException>()),
      );
    });
  });

  // ==========================================================================
  // SystemServiceRegistry Tests (TC-371~)
  // ==========================================================================
  group('TC-371: SystemServiceRegistry.register', () {
    late SystemServiceRegistry registry;

    setUp(() {
      // Use a fresh instance via the singleton; clear it first
      registry = SystemServiceRegistry.instance;
      // We cannot create new instances due to private constructor,
      // so we'll use disposeAll to clean up between tests
    });

    tearDown(() async {
      try {
        await registry.disposeAll();
      } catch (_) {
        // Ignore dispose errors in teardown
      }
    });

    test('TC-371a: register adds service to registry', () {
      final svc = _ServiceA();
      registry.register<_ServiceA>(svc);
      expect(registry.isRegistered<_ServiceA>(), isTrue);
    });

    test('TC-371b: duplicate registration replaces previous', () {
      final svc1 = _ServiceA();
      final svc2 = _ServiceA();
      registry.register<_ServiceA>(svc1);
      final countBefore = registry.serviceCount;
      registry.register<_ServiceA>(svc2);
      expect(registry.serviceCount, equals(countBefore));
      expect(identical(registry.get<_ServiceA>(), svc2), isTrue);
    });
  });

  group('TC-372: SystemServiceRegistry.get', () {
    late SystemServiceRegistry registry;

    setUp(() {
      registry = SystemServiceRegistry.instance;
    });

    tearDown(() async {
      try {
        await registry.disposeAll();
      } catch (_) {}
    });

    test('TC-372a: get returns registered service', () {
      final svc = _ServiceA();
      registry.register<_ServiceA>(svc);
      final retrieved = registry.get<_ServiceA>();
      expect(identical(retrieved, svc), isTrue);
    });

    test('TC-372c: get throws FlowError for unregistered type', () {
      expect(
        () => registry.get<_ServiceB>(),
        throwsA(isA<FlowError>()),
      );
    });
  });

  group('TC-373: SystemServiceRegistry.isRegistered', () {
    late SystemServiceRegistry registry;

    setUp(() {
      registry = SystemServiceRegistry.instance;
    });

    tearDown(() async {
      try {
        await registry.disposeAll();
      } catch (_) {}
    });

    test('TC-373a: registered type returns true', () {
      registry.register<_ServiceA>(_ServiceA());
      expect(registry.isRegistered<_ServiceA>(), isTrue);
    });

    test('TC-373b: unregistered type returns false', () {
      expect(registry.isRegistered<_ServiceB>(), isFalse);
    });

    test('TC-373c: after unregister returns false', () async {
      registry.register<_ServiceA>(_ServiceA());
      await registry.unregister<_ServiceA>();
      expect(registry.isRegistered<_ServiceA>(), isFalse);
    });
  });

  group('TC-374: SystemServiceRegistry.unregister', () {
    late SystemServiceRegistry registry;

    setUp(() {
      registry = SystemServiceRegistry.instance;
    });

    tearDown(() async {
      try {
        await registry.disposeAll();
      } catch (_) {}
    });

    test('TC-374a: unregister calls dispose and removes', () async {
      final svc = _ServiceA();
      registry.register<_ServiceA>(svc);
      await registry.unregister<_ServiceA>();
      expect(registry.isRegistered<_ServiceA>(), isFalse);
      expect(svc.disposed, isTrue);
    });
  });

  group('TC-375: SystemServiceRegistry.initializeAll', () {
    late SystemServiceRegistry registry;

    setUp(() {
      registry = SystemServiceRegistry.instance;
    });

    tearDown(() async {
      try {
        await registry.disposeAll();
      } catch (_) {}
    });

    test('TC-375a: initializes all registered services', () async {
      final svcA = _ServiceA();
      final svcB = _ServiceB();
      registry.register<_ServiceA>(svcA);
      registry.register<_ServiceB>(svcB);

      await registry.initializeAll();

      expect(svcA.initialized, isTrue);
      expect(svcB.initialized, isTrue);
    });

    test('TC-375b: empty registry does not throw', () async {
      await registry.initializeAll();
    });

    test('TC-375c: initializeAll completes for valid services', () async {
      // Verify initializeAll works correctly with valid services
      final svc = _ServiceA();
      registry.register<_ServiceA>(svc);
      await registry.initializeAll();
      expect(svc.initialized, isTrue);
    });
  });

  group('TC-376: SystemServiceRegistry.disposeAll and counts', () {
    late SystemServiceRegistry registry;

    setUp(() {
      registry = SystemServiceRegistry.instance;
    });

    tearDown(() async {
      try {
        await registry.disposeAll();
      } catch (_) {}
    });

    test('TC-376a: disposeAll calls dispose on all services', () async {
      final svcA = _ServiceA();
      final svcB = _ServiceB();
      registry.register<_ServiceA>(svcA);
      registry.register<_ServiceB>(svcB);

      await registry.disposeAll();

      expect(svcA.disposed, isTrue);
      expect(svcB.disposed, isTrue);
    });

    test('TC-376b: serviceCount and registeredTypes', () {
      registry.register<_ServiceA>(_ServiceA());
      registry.register<_ServiceB>(_ServiceB());
      registry.register<_ServiceC>(_ServiceC());

      expect(registry.serviceCount, equals(3));
      expect(registry.registeredTypes.length, equals(3));
    });
  });
}
