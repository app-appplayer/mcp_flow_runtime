import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Tests for MCP Flow DSL v1.0 Specification - Section 6.5.3: Synchronization Actions
void main() {
  group('MCP Flow DSL Spec - Synchronization Actions', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('Mutex Operations', () {
      test('syncLock acquires mutex lock', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 0},
            'process1_done': {'type': 'boolean', 'initial': false},
            'process2_done': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'process1',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'syncLock',
                  'params': {'mutex': 'counter_mutex', 'timeout': 1000}
                },
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'counter', 'value': '=counter + 1'}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'process1_done', 'value': true}
                },
                {
                  'action': 'syncUnlock',
                  'params': {'mutex': 'counter_mutex'}
                },
              ]
            },
            {
              'id': 'process2',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'syncLock',
                  'params': {'mutex': 'counter_mutex', 'timeout': 1000}
                },
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'counter', 'value': '=counter + 1'}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'process2_done', 'value': true}
                },
                {
                  'action': 'syncUnlock',
                  'params': {'mutex': 'counter_mutex'}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Wait for both processes to complete
        await Future.delayed(Duration(milliseconds: 300));
        
        // Both processes should have completed
        expect(runtime.getState('process1_done'), isTrue);
        expect(runtime.getState('process2_done'), isTrue);
        
        // Counter should be exactly 2 (no race condition)
        expect(runtime.getState('counter'), equals(2));
      });

      test('syncLock with timeout', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'lock_acquired': {'type': 'boolean', 'initial': false},
            'timeout_occurred': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'holder',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'syncLock',
                  'params': {'mutex': 'test_mutex'}
                },
                // Hold lock for 500ms
                {'action': 'wait', 'params': {'durationMs': 500}},
                {
                  'action': 'syncUnlock',
                  'params': {'mutex': 'test_mutex'}
                },
              ]
            },
            {
              'id': 'waiter',
              'trigger': {'type': 'startup'},
              'steps': [
                // Wait a bit to ensure holder gets lock first
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'try',
                  'try': [
                    {
                      'action': 'syncLock',
                      'params': {'mutex': 'test_mutex', 'timeout': 100}
                    },
                    {
                      'action': 'stateSet',
                      'params': {'key': 'lock_acquired', 'value': true}
                    },
                  ],
                  'catch': [
                    {
                      'action': 'stateSet',
                      'params': {'key': 'timeout_occurred', 'value': true}
                    },
                  ]
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Lock should timeout
        expect(runtime.getState('lock_acquired'), isFalse);
        expect(runtime.getState('timeout_occurred'), isTrue);
      });
    });

    group('Event Signaling', () {
      test('syncWait and syncSignal coordination', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'data_ready': {'type': 'boolean', 'initial': false},
            'data_processed': {'type': 'boolean', 'initial': false},
            'result': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'producer',
              'trigger': {'type': 'startup'},
              'steps': [
                // Simulate data preparation
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'result', 'value': 42}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'data_ready', 'value': true}
                },
                // Signal that data is ready
                {
                  'action': 'syncSignal',
                  'params': {'event': 'data_available', 'broadcast': false}
                },
              ]
            },
            {
              'id': 'consumer',
              'trigger': {'type': 'startup'},
              'steps': [
                // Wait for data to be available
                {
                  'action': 'syncWait',
                  'params': {'event': 'data_available', 'timeout': 500}
                },
                // Process the data
                {
                  'action': 'stateSet',
                  'params': {'key': 'data_processed', 'value': true}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        expect(runtime.getState('data_ready'), isTrue);
        expect(runtime.getState('data_processed'), isTrue);
        expect(runtime.getState('result'), equals(42));
      });

      test('syncSignal with broadcast', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'worker1_started': {'type': 'boolean', 'initial': false},
            'worker2_started': {'type': 'boolean', 'initial': false},
            'worker3_started': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'coordinator',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 100}},
                // Broadcast start signal to all workers
                {
                  'action': 'syncSignal',
                  'params': {'event': 'start_work', 'broadcast': true}
                },
              ]
            },
            {
              'id': 'worker1',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'syncWait',
                  'params': {'event': 'start_work', 'timeout': 500}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'worker1_started', 'value': true}
                },
              ]
            },
            {
              'id': 'worker2',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'syncWait',
                  'params': {'event': 'start_work', 'timeout': 500}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'worker2_started', 'value': true}
                },
              ]
            },
            {
              'id': 'worker3',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'syncWait',
                  'params': {'event': 'start_work', 'timeout': 500}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'worker3_started', 'value': true}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // All workers should have started
        expect(runtime.getState('worker1_started'), isTrue);
        expect(runtime.getState('worker2_started'), isTrue);
        expect(runtime.getState('worker3_started'), isTrue);
      });
    });

    group('Barrier Synchronization', () {
      test('syncBarrier waits for all processes', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'process1_at_barrier': {'type': 'boolean', 'initial': false},
            'process2_at_barrier': {'type': 'boolean', 'initial': false},
            'process3_at_barrier': {'type': 'boolean', 'initial': false},
            'all_continued': {'type': 'number', 'initial': 0},
          },
          'synchronization': {
            'barriers': {
              'sync_point': {'type': 'barrier', 'count': 3}
            }
          },
          'processes': [
            {
              'id': 'process1',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'process1_at_barrier', 'value': true}
                },
                {
                  'action': 'syncBarrier',
                  'params': {'barrier': 'sync_point'}
                },
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'all_continued', 'operation': 'increment'}
                },
              ]
            },
            {
              'id': 'process2',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'process2_at_barrier', 'value': true}
                },
                {
                  'action': 'syncBarrier',
                  'params': {'barrier': 'sync_point'}
                },
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'all_continued', 'operation': 'increment'}
                },
              ]
            },
            {
              'id': 'process3',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 150}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'process3_at_barrier', 'value': true}
                },
                {
                  'action': 'syncBarrier',
                  'params': {'barrier': 'sync_point'}
                },
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'all_continued', 'operation': 'increment'}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Wait for all to reach barrier
        await Future.delayed(Duration(milliseconds: 200));
        
        // All should have reached barrier
        expect(runtime.getState('process1_at_barrier'), isTrue);
        expect(runtime.getState('process2_at_barrier'), isTrue);
        expect(runtime.getState('process3_at_barrier'), isTrue);
        
        // Wait a bit more for barrier release
        await Future.delayed(Duration(milliseconds: 100));
        
        // All should have continued past barrier
        expect(runtime.getState('all_continued'), equals(3));
      });
    });
  });
}