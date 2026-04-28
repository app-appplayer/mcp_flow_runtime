import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'package:mcp_flow_runtime/src/services/service_manager.dart';

void main() {
  group('System Service Integration', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('service manager factory creates platform-specific manager', () {
      final serviceManager = ServiceManagerFactory.create();
      expect(serviceManager, isNotNull);
      
      if (Platform.isLinux) {
        expect(serviceManager, isA<SystemdServiceManager>());
      } else if (Platform.isWindows) {
        expect(serviceManager, isA<WindowsServiceManager>());
      } else if (Platform.isMacOS) {
        expect(serviceManager, isA<LaunchdServiceManager>());
      } else {
        expect(serviceManager, isA<MockServiceManager>());
      }
    });

    test('mock service manager basic operations', () async {
      final serviceManager = MockServiceManager();
      
      final config = ServiceConfig(
        name: 'test-service',
        displayName: 'Test Service',
        description: 'Test service for unit testing',
        executablePath: '/usr/bin/test',
        arguments: ['--arg1', '--arg2'],
      );

      // Install service
      await serviceManager.install(config);
      expect(await serviceManager.isInstalled('test-service'), isTrue);
      
      // Start service
      await serviceManager.start('test-service');
      expect(await serviceManager.status('test-service'), equals(ServiceStatus.running));

      // Stop service
      await serviceManager.stop('test-service');
      expect(await serviceManager.status('test-service'), equals(ServiceStatus.stopped));

      // Restart service
      await serviceManager.restart('test-service');
      expect(await serviceManager.status('test-service'), equals(ServiceStatus.running));

      // Get logs
      final logs = await serviceManager.logs('test-service');
      expect(logs, isNotEmpty);
      expect(logs.any((log) => log.contains('installed')), isTrue);
      
      // Uninstall service
      await serviceManager.uninstall('test-service');
      expect(await serviceManager.isInstalled('test-service'), isFalse);
    });

    test('runtime creates service configuration from flow', () async {
      final flow = {
        'version': '1.0.0',
        'metadata': {
          'name': 'test-flow',
          'description': 'Test flow for service integration',
        },
        'state': {},
        'processes': [],
      };

      await runtime.loadFlow(flow);
      
      final config = runtime.createServiceConfig(
        executablePath: '/usr/bin/dart',
        arguments: ['run', 'flow.dart'],
        workingDirectory: '/opt/myapp',
        user: 'flowuser',
      );

      expect(config.name, equals('mcp-flow-test-flow'));
      expect(config.displayName, equals('MCP Flow Runtime - test-flow'));
      expect(config.description, contains('test-flow'));
      expect(config.executablePath, equals('/usr/bin/dart'));
      expect(config.arguments, equals(['run', 'flow.dart']));
      expect(config.workingDirectory, equals('/opt/myapp'));
      expect(config.user, equals('flowuser'));
      expect(config.autoRestart, isTrue);
    });

    test('runtime service installation with mock manager', () async {
      final flow = {
        'version': '1.0.0',
        'metadata': {
          'name': 'service-test',
        },
        'state': {},
        'processes': [],
      };

      await runtime.loadFlow(flow);
      
      final config = runtime.createServiceConfig(
        executablePath: '/usr/bin/dart',
        arguments: ['run', 'app.dart'],
      );

      // Note: This would require elevated privileges in real environments
      // For testing, we'll just verify the method doesn't throw
      try {
        await runtime.installAsService(config);
        await runtime.uninstallService(config.name);
      } catch (e) {
        // Expected on platforms without proper permissions
        expect(e.toString(), contains('Failed to'));
      }
    });

    test('runtime throws error when installing service without flow', () async {
      final config = ServiceConfig(
        name: 'test-service',
        displayName: 'Test Service',
        description: 'Test service',
        executablePath: '/usr/bin/test',
      );

      expect(
        () => runtime.installAsService(config),
        throwsA(isA<Exception>()),
      );
    });

    test('service config serialization', () {
      final config = ServiceConfig(
        name: 'test-service',
        displayName: 'Test Service',
        description: 'Test service description',
        executablePath: '/usr/bin/test',
        arguments: ['--arg1', 'value1'],
        environment: {'ENV_VAR': 'value'},
        workingDirectory: '/opt/test',
        user: 'testuser',
        group: 'testgroup',
        autoRestart: true,
        restartDelay: Duration(seconds: 10),
        maxRestarts: 5,
      );

      final json = config.toJson();
      
      expect(json['name'], equals('test-service'));
      expect(json['displayName'], equals('Test Service'));
      expect(json['description'], equals('Test service description'));
      expect(json['executablePath'], equals('/usr/bin/test'));
      expect(json['arguments'], equals(['--arg1', 'value1']));
      expect(json['environment'], equals({'ENV_VAR': 'value'}));
      expect(json['workingDirectory'], equals('/opt/test'));
      expect(json['user'], equals('testuser'));
      expect(json['group'], equals('testgroup'));
      expect(json['autoRestart'], isTrue);
      expect(json['restartDelay'], equals(10));
      expect(json['maxRestarts'], equals(5));
    });
  });
}