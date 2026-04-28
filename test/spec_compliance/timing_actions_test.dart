import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Tests for MCP Flow DSL v1.0 Specification - Section 6.4: Timing Actions
void main() {
  group('MCP Flow DSL Spec - Timing Actions', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('wait Action', () {
      test('wait pauses execution for specified duration', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'wait_complete': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'timer',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'wait',
                  'params': {'durationMs': 100}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'wait_complete', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        final startTime = DateTime.now();
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('wait_complete'), isTrue);
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        expect(elapsed, greaterThanOrEqualTo(100));
      });

      // Test removed: 'wait with expression-based duration' is not in the spec
      // The spec defines durationMs as "number", not as an expression string
    });

    group('waitUntil Action', () {
      test('waitUntil blocks until condition is true', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 0},
            'wait_complete': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'incrementer',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'for',
                  'params': {
                    'variable': 'i',
                    'from': 0,
                    'to': 10,
                    'step': 1
                  },
                  'do': [
                    {'action': 'wait', 'params': {'durationMs': 20}},
                    {
                      'action': 'stateUpdate',
                      'params': {'key': 'counter', 'operation': 'increment'}
                    }
                  ]
                }
              ]
            },
            {
              'id': 'waiter',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'waitUntil',
                  'condition': '=state.counter >= 5',
                  'params': {
                    'pollIntervalMs': 10,
                    'timeoutMs': 500
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'wait_complete', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 300));
        
        expect(runtime.getState('wait_complete'), isTrue);
        expect(runtime.getState('counter'), greaterThanOrEqualTo(5));
      });

      test('waitUntil with timeout', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'condition_met': {'type': 'boolean', 'initial': false},
            'timeout_occurred': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'timeout_test',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'try',
                  'try': [
                    {
                      'action': 'waitUntil',
                      'condition': '=state.condition_met',
                      'params': {
                        'pollIntervalMs': 10,
                        'timeoutMs': 100
                      }
                    }
                  ],
                  'catch': [
                    {
                      'action': 'stateSet',
                      'params': {'key': 'timeout_occurred', 'value': true}
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('timeout_occurred'), isTrue);
        expect(runtime.getState('condition_met'), isFalse);
      });

      test('waitUntil with complex condition', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'temperature': {'type': 'number', 'initial': 20},
            'humidity': {'type': 'number', 'initial': 50},
            'conditions_met': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'sensor_simulator',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'temperature', 'value': 25}
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'humidity', 'value': 65}
                }
              ]
            },
            {
              'id': 'condition_waiter',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'waitUntil',
                  'condition': '=state.temperature > 24 && state.humidity > 60',
                  'params': {
                    'pollIntervalMs': 20,
                    'timeoutMs': 500
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'conditions_met', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        expect(runtime.getState('conditions_met'), isTrue);
        expect(runtime.getState('temperature'), equals(25));
        expect(runtime.getState('humidity'), equals(65));
      });
    });

    group('timeStart and timeElapsed Actions', () {
      test('timeStart and timeElapsed measure time duration', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'operation_time': {'type': 'number', 'initial': 0},
            'timing_complete': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'timed_operation',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'timeStart',
                  'params': {'timer': 'operation_timer'}
                },
                // Simulate some work
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'timeElapsed',
                  'params': {'timer': 'operation_timer'},
                  'bindTo': 'elapsed'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'operation_time', 'value': '=elapsed'}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'timing_complete', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('timing_complete'), isTrue);
        final elapsed = runtime.getState('operation_time');
        expect(elapsed, greaterThanOrEqualTo(100));
        expect(elapsed, lessThan(150));
      });

      test('multiple timers running concurrently', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'timer1_elapsed': {'type': 'number', 'initial': 0},
            'timer2_elapsed': {'type': 'number', 'initial': 0},
            'timer3_elapsed': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'multi_timer',
              'trigger': {'type': 'startup'},
              'steps': [
                // Start all timers
                {
                  'action': 'timeStart',
                  'params': {'timer': 'timer1'}
                },
                {
                  'action': 'timeStart',
                  'params': {'timer': 'timer2'}
                },
                {
                  'action': 'timeStart',
                  'params': {'timer': 'timer3'}
                },
                // Different wait times
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'timeElapsed',
                  'params': {'timer': 'timer1'},
                  'bindTo': 't1'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'timer1_elapsed', 'value': '=t1'}
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'timeElapsed',
                  'params': {'timer': 'timer2'},
                  'bindTo': 't2'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'timer2_elapsed', 'value': '=t2'}
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'timeElapsed',
                  'params': {'timer': 'timer3'},
                  'bindTo': 't3'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'timer3_elapsed', 'value': '=t3'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        final t1 = runtime.getState('timer1_elapsed');
        final t2 = runtime.getState('timer2_elapsed');
        final t3 = runtime.getState('timer3_elapsed');
        
        // Timer 1 should have ~50ms
        expect(t1, greaterThanOrEqualTo(50));
        expect(t1, lessThan(100));
        
        // Timer 2 should have ~100ms
        expect(t2, greaterThanOrEqualTo(100));
        expect(t2, lessThan(150));
        
        // Timer 3 should have ~150ms
        expect(t3, greaterThanOrEqualTo(150));
        expect(t3, lessThan(200));
      });

      test('timer restart resets elapsed time', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'first_elapsed': {'type': 'number', 'initial': 0},
            'second_elapsed': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'timer_restart',
              'trigger': {'type': 'startup'},
              'steps': [
                // First timing
                {
                  'action': 'timeStart',
                  'params': {'timer': 'restartable'}
                },
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'timeElapsed',
                  'params': {'timer': 'restartable'},
                  'bindTo': 'e1'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'first_elapsed', 'value': '=e1'}
                },
                // Restart timer
                {
                  'action': 'timeStart',
                  'params': {'timer': 'restartable'}
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'timeElapsed',
                  'params': {'timer': 'restartable'},
                  'bindTo': 'e2'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'second_elapsed', 'value': '=e2'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        final first = runtime.getState('first_elapsed');
        final second = runtime.getState('second_elapsed');
        
        expect(first, greaterThanOrEqualTo(100));
        expect(first, lessThan(150));
        
        expect(second, greaterThanOrEqualTo(50));
        expect(second, lessThan(100));
      });
    });

    group('Timing in Loops', () {
      test('wait in loop creates proper delays', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'iterations': {'type': 'array', 'initial': []},
            'total_time': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'loop_timer',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'timeStart',
                  'params': {'timer': 'loop_timer'}
                },
                {
                  'action': 'for',
                  'params': {
                    'variable': 'i',
                    'from': 0,
                    'to': 2,
                    'step': 1
                  },
                  'do': [
                    {'action': 'wait', 'params': {'durationMs': 30}},
                    {
                      'action': 'stateUpdate',
                      'params': {
                        'key': 'iterations',
                        'operation': 'append',
                        'value': '=i'
                      }
                    }
                  ]
                },
                {
                  'action': 'timeElapsed',
                  'params': {'timer': 'loop_timer'},
                  'bindTo': 'total'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'total_time', 'value': '=total'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        final iterations = runtime.getState('iterations') as List;
        expect(iterations.length, equals(3));
        
        final totalTime = runtime.getState('total_time');
        expect(totalTime, greaterThanOrEqualTo(90)); // 3 * 30ms
        expect(totalTime, lessThan(150));
      });
    });

    group('Timing in Parallel Processes', () {
      test('parallel processes with different timing', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'fast_done': {'type': 'boolean', 'initial': false},
            'medium_done': {'type': 'boolean', 'initial': false},
            'slow_done': {'type': 'boolean', 'initial': false},
            'completion_order': {'type': 'array', 'initial': []},
          },
          'processes': [
            {
              'id': 'fast_process',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'completion_order',
                    'operation': 'append',
                    'value': 'fast'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'fast_done', 'value': true}
                }
              ]
            },
            {
              'id': 'medium_process',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'completion_order',
                    'operation': 'append',
                    'value': 'medium'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'medium_done', 'value': true}
                }
              ]
            },
            {
              'id': 'slow_process',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 150}},
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'completion_order',
                    'operation': 'append',
                    'value': 'slow'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'slow_done', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        expect(runtime.getState('fast_done'), isTrue);
        expect(runtime.getState('medium_done'), isTrue);
        expect(runtime.getState('slow_done'), isTrue);
        
        final order = runtime.getState('completion_order') as List;
        expect(order, equals(['fast', 'medium', 'slow']));
      });
    });
  });
}
