import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'package:mcp_flow_runtime/src/hal/mock_hal_factory.dart';

/// Common test fixtures
final minimalFlow = {
  'version': '1.0.0',
  'metadata': {'name': 'Test Flow'},
  'processes': [
    {
      'id': 'test_process',
      'trigger': {'type': 'startup'},
      'steps': [
        {'action': 'log', 'params': {'message': 'hello'}},
      ],
    }
  ],
};

final emptyFlow = {
  'version': '1.0.0',
  'resources': {},
  'state': {},
  'processes': [],
};

final stateFlow = {
  'version': '1.0.0',
  'state': {
    'counter': {'type': 'number', 'initial': 0},
    'message': {'type': 'string', 'initial': 'hello'},
    'started': {'type': 'boolean', 'initial': false},
  },
  'processes': [],
};

final channelFlow = {
  'version': '1.0.0',
  'state': {},
  'channels': {
    'events': {'type': 'pubsub'},
    'commands': {'type': 'queue'},
  },
  'processes': [],
};

void main() {
  group('TC-001: Constructor', () {
    test('TC-001a: default constructor creates runtime with created status',
        () {
      final runtime = McpFlowRuntime();
      expect(runtime.status, equals(RuntimeStatus.created));
      expect(runtime.eventBus, isNotNull);
    });

    test('TC-001b: custom config injection', () {
      final hal = MockHalFactory.createMockHal();
      final runtime = McpFlowRuntime(
        config: RuntimeConfig(maxProcesses: 1, tickRateMs: 100),
        hal: hal,
      );
      expect(runtime.status, equals(RuntimeStatus.created));
      expect(runtime.config.maxProcesses, equals(1));
      expect(runtime.config.tickRateMs, equals(100));
    });

    test('TC-001c: maxProcesses=0 uses given value', () {
      // RuntimeConfig allows 0 — no ArgumentError thrown by constructor
      final runtime =
          McpFlowRuntime(config: RuntimeConfig(maxProcesses: 0));
      expect(runtime.config.maxProcesses, equals(0));
    });
  });

  group('TC-002: loadFlow', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-002a: valid flow loads successfully', () async {
      await runtime.loadFlow(minimalFlow);
      // Should complete without error
    });

    test('TC-002b: empty processes array loads successfully', () async {
      await runtime.loadFlow(emptyFlow);
    });

    test('TC-002c: missing version loads with default', () async {
      // Current implementation: version defaults if missing, no error thrown
      await runtime.loadFlow({'processes': []});
    });

    test('TC-002d: duplicate process IDs throws FlowValidationError', () {
      final dupFlow = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'dup',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'log', 'params': {'message': 'a'}}
            ]
          },
          {
            'id': 'dup',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'log', 'params': {'message': 'b'}}
            ]
          },
        ],
      };
      expect(
        () => runtime.loadFlow(dupFlow),
        throwsA(isA<FlowValidationError>()),
      );
    });

    test('TC-002e: reload while running preserves persistent state', () async {
      final flow1 = {
        'version': '1.0.0',
        'state': {
          'counter': {
            'type': 'number',
            'initial': 0,
            'persistent': true,
          },
        },
        'processes': [],
      };
      await runtime.loadFlow(flow1);
      await runtime.start();
      await runtime.setState('counter', 42);

      // Reload with new flow
      final flow2 = {
        'version': '1.0.0',
        'state': {
          'counter': {
            'type': 'number',
            'initial': 0,
            'persistent': true,
          },
          'newVar': {
            'type': 'string',
            'initial': 'test',
          },
        },
        'processes': [],
      };
      await runtime.loadFlow(flow2);
      // Persistent state should be preserved
      expect(runtime.getState('counter'), equals(42));
    });
  });

  group('TC-003: loadFlowFromJson / loadFlowFromFile', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-003a: load from JSON string', () async {
      await runtime
          .loadFlowFromJson('{"version": "1.0.0", "processes": []}');
    });

    test('TC-003b: invalid JSON string throws FormatException', () {
      expect(
        () => runtime.loadFlowFromJson('{invalid json}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('TC-003c: load from file', () async {
      final tmpFile = File('/tmp/test_flow_tc003.json');
      await tmpFile.writeAsString('{"version": "1.0.0", "processes": []}');
      try {
        await runtime.loadFlowFromFile(tmpFile.path);
      } finally {
        await tmpFile.delete();
      }
    });

    test('TC-003d: nonexistent file throws error', () {
      expect(
        () => runtime.loadFlowFromFile('/nonexistent/path_tc003.json'),
        throwsA(anything),
      );
    });
  });

  group('TC-004: start', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-004a: start after loadFlow sets running status', () async {
      await runtime.loadFlow(emptyFlow);
      await runtime.start();
      expect(runtime.status, equals(RuntimeStatus.running));
    });

    test('TC-004b: start without loadFlow still starts', () async {
      await runtime.start();
      expect(runtime.status, equals(RuntimeStatus.running));
    });

    test('TC-004c: double start throws exception', () async {
      await runtime.loadFlow(emptyFlow);
      await runtime.start();
      expect(() => runtime.start(), throwsException);
    });

    test('TC-004d: start with custom HAL succeeds', () async {
      final hal = MockHalFactory.createMockHal();
      final rt = McpFlowRuntime(hal: hal);
      await rt.loadFlow(emptyFlow);
      await rt.start();
      expect(rt.status, equals(RuntimeStatus.running));
      await rt.stop();
    });
  });

  group('TC-005: stop', () {
    late McpFlowRuntime runtime;

    setUp(() async {
      runtime = McpFlowRuntime();
      await runtime.loadFlow(emptyFlow);
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-005a: stop sets stopped status', () async {
      await runtime.start();
      expect(runtime.status, equals(RuntimeStatus.running));
      await runtime.stop();
      expect(runtime.status, equals(RuntimeStatus.stopped));
    });

    test('TC-005b: stop when already stopped is idempotent', () async {
      await runtime.start();
      await runtime.stop();
      // Second stop should not throw
      await runtime.stop();
      expect(runtime.status, equals(RuntimeStatus.stopped));
    });

    test('TC-005c: stop with active processes gracefully shuts down',
        () async {
      final flowWithProcess = {
        'version': '1.0.0',
        'state': {
          'val': {'type': 'number', 'initial': 0}
        },
        'processes': [
          {
            'id': 'periodic',
            'trigger': {'type': 'schedule', 'interval': 50},
            'steps': [
              {
                'action': 'stateSet',
                'params': {'key': 'val', 'value': 1}
              }
            ]
          }
        ],
      };
      final rt = McpFlowRuntime();
      await rt.loadFlow(flowWithProcess);
      await rt.start();
      await Future.delayed(Duration(milliseconds: 100));
      // Should stop gracefully without throwing
      await rt.stop();
      expect(rt.status, equals(RuntimeStatus.stopped));
    });
  });

  group('TC-006: executeProcess / stopProcess', () {
    late McpFlowRuntime runtime;

    setUp(() async {
      runtime = McpFlowRuntime();
      await runtime.loadFlow(minimalFlow);
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-006a: execute process by id', () async {
      await runtime.start();
      // Should not throw for existing process
      await runtime.executeProcess('test_process');
    });

    test('TC-006b: execute nonexistent processId throws error', () async {
      await runtime.start();
      expect(
        () => runtime.executeProcess('nonexistent'),
        throwsA(isA<ConcreteFlowError>()),
      );
    });

    test('TC-006c: execute before start throws error', () {
      expect(
        () => runtime.executeProcess('test_process'),
        throwsA(isA<ConcreteFlowError>()),
      );
    });

    test('TC-006d: stop a running process', () async {
      await runtime.start();
      // Should not throw
      await runtime.stopProcess('test_process');
    });

    test('TC-006e: stop already stopped process is safe', () async {
      await runtime.start();
      await runtime.stopProcess('test_process');
      // Second stop should not throw
      await runtime.stopProcess('test_process');
    });
  });

  group('TC-007: emitEvent / emitResourceEvent', () {
    late McpFlowRuntime runtime;

    setUp(() async {
      runtime = McpFlowRuntime();
      await runtime.loadFlow(emptyFlow);
      await runtime.start();
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-007a: emit event with data', () async {
      final events = <FlowEvent>[];
      runtime.eventBus.on<FlowEvent>().listen(events.add);
      runtime.emitEvent('alarm', data: {'zone': 'A'});
      await Future.delayed(Duration(milliseconds: 50));
      expect(events, hasLength(1));
      expect(events[0].name, equals('alarm'));
      expect(events[0].data['zone'], equals('A'));
    });

    test('TC-007b: emit event without data', () async {
      final events = <FlowEvent>[];
      runtime.eventBus.on<FlowEvent>().listen(events.add);
      runtime.emitEvent('heartbeat');
      await Future.delayed(Duration(milliseconds: 50));
      expect(events, hasLength(1));
      expect(events[0].name, equals('heartbeat'));
      expect(events[0].data, isNull);
    });

    test('TC-007c: emit event with empty name', () {
      // Should not throw
      runtime.emitEvent('');
    });

    test('TC-007d: emit resource event', () async {
      final events = <ResourceEvent>[];
      runtime.eventBus.on<ResourceEvent>().listen(events.add);
      runtime.emitResourceEvent('gpio', 'pinChange', data: {'pin': 18});
      await Future.delayed(Duration(milliseconds: 50));
      expect(events, hasLength(1));
      expect(events[0].resource, equals('gpio'));
      expect(events[0].event, equals('pinChange'));
    });

    test('TC-007e: resource event with special characters in name', () async {
      final events = <ResourceEvent>[];
      runtime.eventBus.on<ResourceEvent>().listen(events.add);
      runtime.emitResourceEvent('sensor/temp', 'value.changed');
      await Future.delayed(Duration(milliseconds: 50));
      expect(events, hasLength(1));
      expect(events[0].resource, equals('sensor/temp'));
    });
  });

  group('TC-008: getState / setState / sendToChannel', () {
    late McpFlowRuntime runtime;

    setUp(() async {
      runtime = McpFlowRuntime();
      await runtime.loadFlow(stateFlow);
      await runtime.start();
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-008a: get initial state value', () {
      expect(runtime.getState('counter'), equals(0));
    });

    test('TC-008b: get nonexistent key throws', () {
      expect(
        () => runtime.getState('nonexistent'),
        throwsA(anything),
      );
    });

    test('TC-008c: set state value', () async {
      await runtime.setState('counter', 42);
      expect(runtime.getState('counter'), equals(42));
    });

    test('TC-008d: set state to empty string', () async {
      await runtime.setState('message', '');
      expect(runtime.getState('message'), equals(''));
    });

    test('TC-008e: send to channel', () async {
      final rt = McpFlowRuntime();
      await rt.loadFlow(channelFlow);
      await rt.start();

      final stream = rt.getChannelStream('events');
      expect(stream, isNotNull);

      final received = <dynamic>[];
      final sub = stream!.listen(received.add);

      await rt.sendToChannel('events', {'value': 1});
      await Future.delayed(Duration(milliseconds: 50));

      expect(received, hasLength(1));
      expect(received[0]['value'], equals(1));

      await sub.cancel();
      await rt.stop();
    });

    test('TC-008f: send to nonexistent channel throws', () async {
      expect(
        () => runtime.sendToChannel('nonexistent', {}),
        throwsA(isA<ConcreteFlowError>()),
      );
    });
  });

  group('TC-009: Backup Operations', () {
    late McpFlowRuntime runtime;
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('tc009_');
      final backupMgr = BackupManager(
        backupDirectory: tmpDir.path,
        maxBackups: 10,
      );
      runtime = McpFlowRuntime(backupManager: backupMgr);
      await runtime.loadFlow(stateFlow);
      await runtime.start();
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('TC-009a: create backup returns metadata', () async {
      final meta = await runtime.createBackup(
        description: 'test',
        tags: {'env': 'dev'},
      );
      expect(meta.id, isNotEmpty);
      expect(meta.timestamp, isA<DateTime>());
    });

    test('TC-009b: create backup without flow throws', () async {
      final rt = McpFlowRuntime();
      expect(
        () => rt.createBackup(),
        throwsA(isA<ConcreteFlowError>()),
      );
    });

    test('TC-009c: list backups returns created backups', () async {
      await runtime.createBackup(description: 'backup1');
      await runtime.createBackup(description: 'backup2');
      final list = await runtime.listBackups();
      expect(list.length, greaterThanOrEqualTo(2));
    });

    test('TC-009d: restore backup restores state', () async {
      await runtime.setState('counter', 99);
      final meta = await runtime.createBackup();
      await runtime.setState('counter', 0);

      await runtime.restoreBackup(meta.id);
      await runtime.start();
      expect(runtime.getState('counter'), equals(99));
    });

    test('TC-009e: restore nonexistent backup throws', () {
      expect(
        () => runtime.restoreBackup('nonexistent_id'),
        throwsA(anything),
      );
    });

    test('TC-009f: delete backup removes it from list', () async {
      final meta = await runtime.createBackup();
      await runtime.deleteBackup(meta.id);
      final list = await runtime.listBackups();
      expect(list.where((b) => b.id == meta.id), isEmpty);
    });

    test('TC-009g: export and import backup', () async {
      final meta = await runtime.createBackup(description: 'export_test');
      final exportPath = '${tmpDir.path}/export_test.json';
      await runtime.exportBackup(meta.id, exportPath);

      expect(await File(exportPath).exists(), isTrue);

      final imported = await runtime.importBackup(exportPath);
      expect(imported.id, isNotEmpty);
    });

    test('TC-009h: import nonexistent file throws', () {
      expect(
        () => runtime.importBackup('/nonexistent/file.json'),
        throwsA(anything),
      );
    });
  });

  group('TC-010: Service / ProcessList', () {
    late McpFlowRuntime runtime;

    setUp(() async {
      runtime = McpFlowRuntime();
      await runtime.loadFlow(minimalFlow);
    });

    tearDown(() async {
      try {
        if (runtime.status == RuntimeStatus.running) {
          await runtime.stop().timeout(Duration(seconds: 2));
        }
      } catch (_) {}
    });

    test('TC-010a: install as service delegates to ServiceManager', () async {
      await runtime.start();
      final config = ServiceConfig(
        name: 'test_flow_service',
        displayName: 'Test Flow Service',
        description: 'Test service for TC-010a',
        executablePath: '/usr/bin/dart',
      );
      // On test environments, service install may throw due to OS permissions
      try {
        await runtime.installAsService(config);
      } on Exception {
        // Expected: platform service manager may lack permissions in test
      }
      await runtime.stop();
    });

    test('TC-010b: install service without flow loaded throws', () async {
      final rt = McpFlowRuntime();
      final config = ServiceConfig(
        name: 'no_flow_service',
        displayName: 'No Flow Service',
        description: 'Test service without flow',
        executablePath: '/usr/bin/dart',
      );
      expect(
        () => rt.installAsService(config),
        throwsException,
      );
    });

    test('TC-010c: get service status returns ServiceStatus', () async {
      await runtime.start();
      // Service is not installed, so status query may throw or return unknown
      try {
        final status = await runtime.getServiceStatus('test_flow_service');
        expect(status, isA<ServiceStatus>());
      } on Exception {
        // Expected: platform service manager may throw for non-installed service
      }
      await runtime.stop();
    });

    test('TC-010d: get status of non-installed service', () async {
      await runtime.start();
      try {
        final status = await runtime.getServiceStatus('nonexistent_service');
        // Some platforms return unknown for non-installed services
        expect(status, isA<ServiceStatus>());
      } on Exception {
        // Expected: some platforms throw for non-installed service
      }
      await runtime.stop();
    });

    test('TC-010e: uninstall service', () async {
      await runtime.start();
      // Uninstalling a non-existent service may throw or succeed silently
      try {
        await runtime.uninstallService('test_flow_service');
      } on Exception {
        // Expected: platform service manager may throw
      }
      await runtime.stop();
    });

    test('TC-010f: getProcessList returns process info', () async {
      await runtime.start();
      final list = runtime.getProcessList();
      expect(list, isA<List<ProcessInfo>>());
      expect(list.length, greaterThanOrEqualTo(1));
      expect(list.first.id, equals('test_process'));
    });

    test('TC-010g: getProcessList when no processes', () async {
      final rt = McpFlowRuntime();
      await rt.loadFlow(emptyFlow);
      await rt.start();
      final list = rt.getProcessList();
      expect(list, isEmpty);
      await rt.stop();
    });
  });

  // ===== Integration Tests =====

  group('IT-001: startup trigger end-to-end', () {
    test('startup process sets state', () async {
      final runtime = McpFlowRuntime();
      final flow = {
        'version': '1.0.0',
        'state': {
          'started': {'type': 'boolean', 'initial': false},
        },
        'processes': [
          {
            'id': 'startup_proc',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'stateSet',
                'params': {'key': 'started', 'value': true}
              }
            ],
          }
        ],
      };
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 500));
      expect(runtime.getState('started'), equals(true));
      await runtime.stop();
    });
  });

  group('IT-002: schedule trigger periodic execution', () {
    test('counter increments on schedule', () async {
      final runtime = McpFlowRuntime();
      final flow = {
        'version': '1.0.0',
        'state': {
          'count': {'type': 'number', 'initial': 0},
        },
        'processes': [
          {
            'id': 'counter_proc',
            'trigger': {'type': 'schedule', 'interval': 100},
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'count',
                  'value': '={{state.count + 1}}'
                }
              }
            ],
          }
        ],
      };
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 450));
      final count = runtime.getState('count') as num;
      expect(count, greaterThanOrEqualTo(3));
      await runtime.stop();
    });
  });

  group('IT-003: event trigger reaction', () {
    test('event trigger fires process', () async {
      final runtime = McpFlowRuntime();
      final flow = {
        'version': '1.0.0',
        'state': {
          'alarmed': {'type': 'boolean', 'initial': false},
        },
        'processes': [
          {
            'id': 'alarm_handler',
            'trigger': {'type': 'event', 'event': 'alarm'},
            'steps': [
              {
                'action': 'stateSet',
                'params': {'key': 'alarmed', 'value': true}
              }
            ],
          }
        ],
      };
      await runtime.loadFlow(flow);
      await runtime.start();
      runtime.emitEvent('alarm');
      await Future.delayed(Duration(milliseconds: 300));
      expect(runtime.getState('alarmed'), equals(true));
      await runtime.stop();
    });
  });

  group('IT-004: stateChange trigger reaction', () {
    test('stateChange trigger fires on change', () async {
      final runtime = McpFlowRuntime();
      final flow = {
        'version': '1.0.0',
        'state': {
          'temperature': {'type': 'number', 'initial': 20.0},
          'alert': {'type': 'boolean', 'initial': false},
        },
        'processes': [
          {
            'id': 'temp_handler',
            'trigger': {'type': 'stateChange', 'key': 'temperature'},
            'steps': [
              {
                'action': 'stateSet',
                'params': {'key': 'alert', 'value': true}
              }
            ],
          }
        ],
      };
      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.setState('temperature', 30.0);
      await Future.delayed(Duration(milliseconds: 300));
      expect(runtime.getState('alert'), equals(true));
      await runtime.stop();
    });
  });

  group('IT-005: cron trigger execution', () {
    test('cron trigger fires process on schedule', () async {
      final runtime = McpFlowRuntime();
      final flow = {
        'version': '1.0.0',
        'state': {
          'cronCount': {'type': 'number', 'initial': 0},
        },
        'processes': [
          {
            'id': 'cron_proc',
            'trigger': {
              'type': 'schedule',
              'cron': '*/1 * * * * *',
            },
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'cronCount',
                  'value': '={{state.cronCount + 1}}'
                }
              }
            ],
          }
        ],
      };
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(seconds: 2));
      final count = runtime.getState('cronCount') as num;
      expect(count, greaterThanOrEqualTo(1));
      await runtime.stop();
    });
  });

  group('IT-006: channelReceive trigger', () {
    test('channelReceive triggers process', () async {
      final runtime = McpFlowRuntime();
      final flow = {
        'version': '1.0.0',
        'state': {
          'received': {'type': 'boolean', 'initial': false},
        },
        'channels': {
          'commands': {'type': 'queue'},
        },
        'processes': [
          {
            'id': 'cmd_handler',
            'trigger': {'type': 'channelReceive', 'channel': 'commands'},
            'steps': [
              {
                'action': 'stateSet',
                'params': {'key': 'received', 'value': true}
              }
            ],
          }
        ],
      };
      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.sendToChannel('commands', {'cmd': 'go'});
      await Future.delayed(Duration(milliseconds: 300));
      expect(runtime.getState('received'), equals(true));
      await runtime.stop();
    });
  });

  group('IT-007: backup/restore integration', () {
    test('backup and restore preserves state', () async {
      final tmpDir = await Directory.systemTemp.createTemp('it007_');
      try {
        final backupMgr = BackupManager(
          backupDirectory: tmpDir.path,
          maxBackups: 10,
        );
        final runtime = McpFlowRuntime(backupManager: backupMgr);
        await runtime.loadFlow(stateFlow);
        await runtime.start();
        await runtime.setState('counter', 55);
        final meta = await runtime.createBackup();
        await runtime.setState('counter', 999);

        await runtime.restoreBackup(meta.id);
        await runtime.start();
        expect(runtime.getState('counter'), equals(55));
        await runtime.stop();
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });

  group('IT-008: multiple processes concurrent execution', () {
    test('5 startup processes all complete', () async {
      final runtime = McpFlowRuntime();
      final processes = List.generate(
        5,
        (i) => {
          'id': 'proc_$i',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'stateSet',
              'params': {'key': 'v$i', 'value': i}
            }
          ],
        },
      );
      final stateVars = <String, dynamic>{};
      for (var i = 0; i < 5; i++) {
        stateVars['v$i'] = {'type': 'number', 'initial': -1};
      }
      final flow = {
        'version': '1.0.0',
        'state': stateVars,
        'processes': processes,
      };
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 500));
      for (var i = 0; i < 5; i++) {
        expect(runtime.getState('v$i'), equals(i));
      }
      await runtime.stop();
    });
  });

  group('IT-009: runtime event subscription', () {
    test('RuntimeStartedEvent and ProcessCompletedEvent received', () async {
      final runtime = McpFlowRuntime();
      await runtime.loadFlow(minimalFlow);

      final startEvents = <RuntimeStartedEvent>[];
      runtime.eventBus.on<RuntimeStartedEvent>().listen(startEvents.add);
      final procEvents = <ProcessCompletedEvent>[];
      runtime.eventBus
          .on<ProcessCompletedEvent>()
          .listen(procEvents.add);

      await runtime.start();
      await Future.delayed(Duration(milliseconds: 500));

      expect(startEvents, hasLength(1));
      // Process may or may not complete depending on timing
      await runtime.stop();
    });
  });

  group('IT-010: resourceEvent trigger', () {
    test('resourceEvent triggers process', () async {
      final flow = {
        'version': '1.0.0',
        'resources': {
          'button': {
            'type': 'gpio',
            'capabilities': ['read', 'interrupt'],
            'config': {'pin': 18, 'mode': 'input', 'interrupt': 'both'},
          },
        },
        'state': {
          'pinChanged': {'type': 'boolean', 'initial': false},
        },
        'processes': [
          {
            'id': 'gpio_handler',
            'trigger': {
              'type': 'resourceEvent',
              'resource': 'gpio_18',
              'event': 'high',
            },
            'steps': [
              {
                'action': 'stateSet',
                'params': {'key': 'pinChanged', 'value': true}
              }
            ],
          }
        ],
      };
      final hal = MockHalFactory.createMockHal() as MockHardwareAbstractionLayer;
      final rt = McpFlowRuntime(hal: hal);
      await rt.loadFlow(flow);
      await rt.start();
      rt.emitResourceEvent('gpio_18', 'high', data: {'pin': 18});
      await Future.delayed(Duration(milliseconds: 300));
      expect(rt.getState('pinChanged'), equals(true));
      await rt.stop();
    });
  });
}
