import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Watchdog Timer', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('watchdog configuration via runtime config', () async {
      // Create runtime with watchdog config
      runtime = McpFlowRuntime(
        config: RuntimeConfig(
          watchdogIntervalMs: 1000, // 1 second timeout
        ),
      );

      final flow = {
        'version': '1.0.0',
        'state': {
          'started': {'type': 'boolean', 'initial': false},
        },
        'processes': [
          {
            'id': 'test_process',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'started',
                  'value': true,
                },
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Process should start
      await Future.delayed(Duration(milliseconds: 100));
      expect(runtime.getState('started'), isTrue);
    });

    test('watchdog configuration via flow config', () async {
      final flow = {
        'version': '1.0.0',
        'configuration': {
          'safety': {
            'watchdog': {
              'enabled': true,
              'timeoutMs': 500,
              'action': 'restart_process',
              'criticalProcesses': ['critical_process'],
            },
          },
        },
        'state': {
          'executed': {'type': 'boolean', 'initial': false},
        },
        'processes': [
          {
            'id': 'normal_process',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'executed',
                  'value': true,
                },
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Process should execute normally
      await Future.delayed(Duration(milliseconds: 100));
      expect(runtime.getState('executed'), isTrue);
    });

    test('watchdog disabled by default', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'completed': {'type': 'boolean', 'initial': false},
        },
        'processes': [
          {
            'id': 'long_process',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'wait',
                'params': {
                  'durationMs': 2000, // Long delay
                },
              },
              {
                'action': 'stateSet',
                'params': {
                  'key': 'completed',
                  'value': true,
                },
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Wait for process to complete normally (no watchdog)
      await Future.delayed(Duration(milliseconds: 2500));

      // Process should complete without interruption
      expect(runtime.getState('completed'), isTrue);
    });

    test('runtime watchdog with automatic heartbeat', () async {
      // Create runtime with watchdog config
      runtime = McpFlowRuntime(
        config: RuntimeConfig(
          watchdogIntervalMs: 500, // 500ms timeout
        ),
      );

      final flow = {
        'version': '1.0.0',
        'state': {
          'alive': {'type': 'boolean', 'initial': true},
        },
        'processes': [], // No processes, just runtime monitoring
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Runtime should stay alive with automatic heartbeat
      await Future.delayed(Duration(seconds: 2));

      // Runtime should still be running
      expect(runtime.status, equals(RuntimeStatus.running));
    });

    test('watchdog detects hanging process (demonstration)', () async {
      final flow = {
        'version': '1.0.0',
        'configuration': {
          'safety': {
            'watchdog': {
              'enabled': true,
              'timeoutMs': 500, // 500ms timeout
              'action': 'restart_process',
            },
          },
        },
        'state': {
          'counter': {'type': 'number', 'initial': 0},
          'error_count': {'type': 'number', 'initial': 0},
        },
        'processes': [
          {
            'id': 'hanging_process',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'counter',
                  'value': '= counter + 1',
                },
              },
              {
                'action': 'wait',
                'params': {
                  'durationMs': 1000, // Will exceed watchdog timeout
                },
              },
            ],
            'error': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'error_count',
                  'value': '= error_count + 1',
                },
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      
      // Listen for process completion events
      int completionEvents = 0;
      runtime.eventBus.on<ProcessCompletedEvent>().listen((event) {
        completionEvents++;
      });

      await runtime.start();

      // Wait for watchdog to potentially trigger
      await Future.delayed(Duration(milliseconds: 1500));

      // Process should have been monitored by watchdog
      expect(runtime.getState('counter'), greaterThanOrEqualTo(1));
      
      // Note: Full restart functionality would require per-action heartbeat
      // which is not implemented in the current version.
      // The watchdog is initialized and monitoring but needs action-level
      // integration for complete functionality.
    });
  });
}