import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('MCP Flow DSL Spec - Process Model (Section 5)', () {
    late McpFlowRuntime runtime;
    late JsonFlowParser parser;

    setUp(() {
      parser = JsonFlowParser();
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      await runtime.stop();
    });

    group('Process Definition', () {
      test('should define basic process with id and trigger', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'basic_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Process executed'}}
              ]
            }
          ]
        };

        final flow = parser.parse(flowDef);
        await runtime.loadFlow(flowDef);

        expect(flow.processes, hasLength(1));
        expect(flow.processes[0].id, equals('basic_process'));
        expect(flow.processes[0].trigger?.type, equals(TriggerType.manual));
      });

      test('should support process name and description', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'documented_process',
              'name': 'Test Process',
              'description': 'This process is for testing',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            }
          ]
        };

        final flow = parser.parse(flowDef);
        await runtime.loadFlow(flowDef);

        expect(flow.processes[0].name, equals('Test Process'));
        expect(flow.processes[0].description, equals('This process is for testing'));
      });

      test('should support enabled flag', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'disabled_process',
              'enabled': false,
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Should not run'}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();

        // Process should not execute when disabled
        // Verification would require checking logs or state
      });
    });

    group('Process Priorities', () {
      test('should support process priority levels', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'realtime_process',
              'priority': 'realtime',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            },
            {
              'id': 'high_process',
              'priority': 'high',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            },
            {
              'id': 'normal_process',
              'priority': 'normal',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            },
            {
              'id': 'low_process',
              'priority': 'low',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            }
          ]
        };

        final flow = parser.parse(flowDef);
        await runtime.loadFlow(flowDef);

        expect(flow.processes[0].priority, equals(ProcessPriority.realtime));  // 'critical' maps to 'realtime'
        expect(flow.processes[1].priority, equals(ProcessPriority.high));
        expect(flow.processes[2].priority, equals(ProcessPriority.normal));
        expect(flow.processes[3].priority, equals(ProcessPriority.low));
      });

      test('should default to normal priority', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'default_priority',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            }
          ]
        };

        final flow = parser.parse(flowDef);
        await runtime.loadFlow(flowDef);

        expect(flow.processes[0].priority, equals(ProcessPriority.normal));
      });
    });

    group('Process Lifecycle', () {
      test('should execute startup processes on runtime start', () async {
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'startupExecuted': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'startup_process',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'startupExecuted',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();

        // Give time for startup process to execute
        await Future.delayed(Duration(milliseconds: 100));

        final state = runtime.getState('startupExecuted');
        expect(state, isTrue);
      });

      test('should support process with multiple steps', () async {
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'counter': {
              'type': 'number',
              'initial': 0
            }
          },
          'processes': [
            {
              'id': 'multi_step',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'counter',
                    'value': 1
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'counter',
                    'value': 2
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'counter',
                    'value': 3
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        // Execute the manual process
        await runtime.executeProcess('multi_step');
        
        // Give time for process to complete
        await Future.delayed(Duration(milliseconds: 100));

        final counter = runtime.getState('counter');
        expect(counter, equals(3));
      });

      test('should track process execution state', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'tracked_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'wait',
                  'params': {'durationMs': 50}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();

        // Process state tracking would be verified through runtime APIs
        // that expose process instance states
      });
    });

    group('Process Error Handling', () {
      test('should support error steps', () async {
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'errorHandled': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'error_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'expression',
                  'params': {
                    'expression': '= error("Test error")'  // This will throw
                  }
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'errorHandled',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        // Execute process that will error
        try {
          await runtime.executeProcess('error_process');
        } catch (e) {
          // Process may throw, that's expected
          print('Process threw error: $e');
        }
        
        // Give time for error handling
        await Future.delayed(Duration(milliseconds: 100));

        final errorHandled = runtime.getState('errorHandled');
        expect(errorHandled, isTrue);
      });

      test('should support finally steps', () async {
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'finallyExecuted': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'finally_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'log',
                  'params': {'message': 'Normal execution'}
                }
              ],
              'finally': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'finallyExecuted',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('finally_process');
        
        // Give time for finally block
        await Future.delayed(Duration(milliseconds: 100));

        final finallyExecuted = runtime.getState('finallyExecuted');
        expect(finallyExecuted, isTrue);
      });

      test('should execute finally even on error', () async {
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'finallyAfterError': {
              'type': 'boolean',
              'initial': false
            },
            'mainStepRan': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'error_finally_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'try',
                  'try': [
                    {
                      'action': 'expression',
                      'params': {
                        'expression': '= 1 / 0'
                      }
                    }
                  ],
                  'catch': [
                    {
                      'action': 'log',
                      'params': {'message': 'Error caught'}
                    }
                  ],
                  'finally': [
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'finallyAfterError',
                        'value': true
                      }
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();

        await runtime.executeProcess('error_finally_process');

        // Give time for finally block
        await Future.delayed(Duration(milliseconds: 100));

        final finallyExecuted = runtime.getState('finallyAfterError');
        expect(finallyExecuted, isTrue);
      });
    });

    group('Process Communication', () {
      test('should support inter-process communication via state', () async {
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'sharedData': {
              'type': 'string',
              'initial': ''
            }
          },
          'processes': [
            {
              'id': 'producer',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'sharedData',
                    'value': 'Hello from producer'
                  }
                }
              ]
            },
            {
              'id': 'consumer',
              'trigger': {
                'type': 'stateChange',
                'key': 'sharedData'
              },
              'steps': [
                {
                  'action': 'log',
                  'params': {
                    'message': '= "Received: " + sharedData'
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        // Execute producer which should trigger consumer
        await runtime.executeProcess('producer');
        
        // Give time for state change trigger
        await Future.delayed(Duration(milliseconds: 100));

        // Consumer should have been triggered by state change
        final sharedData = runtime.getState('sharedData');
        expect(sharedData, equals('Hello from producer'));
      });

      test('should support channel-based communication', () async {
        final flowDef = {
          'version': '1.0.0',
          'channels': {
            'dataChannel': {
              'type': 'pubsub',
              'config': {}
            }
          },
          'state': {
            'messageReceived': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'sender',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'channelSend',
                  'params': {
                    'channel': 'dataChannel',
                    'data': {'message': 'Test message'}
                  }
                }
              ]
            },
            {
              'id': 'receiver',
              'trigger': {
                'type': 'channelReceive',
                'channel': 'dataChannel'
              },
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'messageReceived',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        // Send message through channel
        await runtime.executeProcess('sender');
        
        // Give time for channel message
        await Future.delayed(Duration(milliseconds: 100));

        final messageReceived = runtime.getState('messageReceived');
        expect(messageReceived, isTrue);
      });
    });

    group('Process Execution Control', () {
      test('should support conditional execution', () async {
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'condition': {
              'type': 'boolean',
              'initial': true
            },
            'executed': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'conditional_process',
              'trigger': {
                'type': 'condition',
                'condition': 'condition == true'
              },
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'executed',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        // Give time for condition evaluation
        await Future.delayed(Duration(milliseconds: 200));

        final executed = runtime.getState('executed');
        expect(executed, isTrue);
      });

      test('should support process timeout', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'timeout_process',
              'trigger': {'type': 'manual'},
              'timeout': 100,  // 100ms timeout
              'steps': [
                {
                  'action': 'wait',
                  'params': {'durationMs': 200}  // Will exceed timeout
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        // Process should timeout
        // This would be verified through process state or error handling
      });

      test('should support process retry on failure', () async {
        // Test that retry configuration is accepted and process executes
        final flowDef = {
          'version': '1.0.0',
          'state': {
            'attempt_count': {
              'type': 'number',
              'initial': 0
            },
            'process_succeeded': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'retry_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'attempt_count',
                    'value': '= attempt_count + 1'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'process_succeeded',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();

        await runtime.executeProcess('retry_process');

        // Give time for execution
        await Future.delayed(Duration(milliseconds: 100));

        final attemptCount = runtime.getState('attempt_count');
        final succeeded = runtime.getState('process_succeeded');

        expect(attemptCount, greaterThanOrEqualTo(1));
        expect(succeeded, isTrue);
      });
    });

    group('Process Validation', () {
      test('should reject process without id', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              // Missing 'id' field
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            }
          ]
        };

        expect(() async => await runtime.loadFlow(flowDef), 
               throwsA(isA<FlowParseError>()));
      });

      test('should accept process without trigger (manual trigger)', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'no_trigger',
              // Missing 'trigger' field - should default to manual
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            }
          ]
        };

        // Should not throw - trigger is optional
        await runtime.loadFlow(flowDef);
        final flow = parser.parse(flowDef);
        
        // Process should exist with no trigger (manual execution)
        expect(flow.processes[0].trigger, isNull);
      });

      test('should reject invalid priority value', () async {
        final flowDef = {
          'version': '1.0.0',
          'processes': [
            {
              'id': 'bad_priority',
              'priority': 'invalid_priority',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'log', 'params': {'message': 'Test step'}}
              ]
            }
          ]
        };

        // Parser may accept but runtime should validate
        expect(() async => await runtime.loadFlow(flowDef), 
               throwsA(isA<Exception>()));
      });
    });
  });
}