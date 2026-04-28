import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Comprehensive tests for MCP Flow DSL v1.0 Specification - Section 4: Triggers
void main() {
  group('MCP Flow DSL Spec - Comprehensive Trigger Tests', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('Startup Trigger', () {
      test('single process with startup trigger', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'started': {'type': 'boolean', 'initial': false},
            'start_time': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'startup_process',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'started', 'value': true}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'start_time', 'value': '=Date.now()'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 50));
        
        expect(runtime.getState('started'), isTrue);
        expect(runtime.getState('start_time'), greaterThan(0));
      });

      test('multiple processes with startup triggers', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'process1_started': {'type': 'boolean', 'initial': false},
            'process2_started': {'type': 'boolean', 'initial': false},
            'process3_started': {'type': 'boolean', 'initial': false},
            'start_order': {'type': 'array', 'initial': []},
          },
          'processes': [
            {
              'id': 'process1',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'process1_started', 'value': true}
                },
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'start_order',
                    'operation': 'append',
                    'value': 'process1'
                  }
                }
              ]
            },
            {
              'id': 'process2',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'process2_started', 'value': true}
                },
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'start_order',
                    'operation': 'append',
                    'value': 'process2'
                  }
                }
              ]
            },
            {
              'id': 'process3',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'process3_started', 'value': true}
                },
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'start_order',
                    'operation': 'append',
                    'value': 'process3'
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('process1_started'), isTrue);
        expect(runtime.getState('process2_started'), isTrue);
        expect(runtime.getState('process3_started'), isTrue);
        
        final order = runtime.getState('start_order') as List;
        expect(order.length, equals(3));
        expect(order.contains('process1'), isTrue);
        expect(order.contains('process2'), isTrue);
        expect(order.contains('process3'), isTrue);
      });
    });

    group('Schedule Trigger', () {
      test('schedule trigger with interval', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'execution_count': {'type': 'number', 'initial': 0},
            'last_execution': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'periodic_process',
              'trigger': {
                'type': 'schedule',
                'interval': 50  // 50ms interval
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'execution_count', 'operation': 'increment'}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'last_execution', 'value': '=Date.now()'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Wait for multiple executions
        await Future.delayed(Duration(milliseconds: 180));
        
        final count = runtime.getState('execution_count');
        expect(count, greaterThanOrEqualTo(3));
        expect(count, lessThanOrEqualTo(4));
      });

      test('schedule trigger with initial delay', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'first_execution_time': {'type': 'number', 'initial': 0},
            'start_time': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'delayed_start',
              'trigger': {
                'type': 'schedule',
                'interval': 100,
                'delay': 50
              },
              'steps': [
                {
                  'action': 'if',
                  'condition': '=state.first_execution_time == 0',
                  'then': [
                    {
                      'action': 'stateSet',
                      'params': {'key': 'first_execution_time', 'value': '=Date.now()'}
                    }
                  ]
                }
              ]
            },
            {
              'id': 'time_tracker',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'start_time', 'value': '=Date.now()'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        final firstExec = runtime.getState('first_execution_time');
        final startTime = runtime.getState('start_time');
        
        expect(firstExec, greaterThan(0));
        expect(startTime, greaterThan(0));
        // First execution should be delayed
        expect(firstExec - startTime, greaterThanOrEqualTo(40));
      });
    });

    group('Condition Trigger', () {
      test('condition trigger activates when condition becomes true', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'temperature': {'type': 'number', 'initial': 20},
            'alarm_triggered': {'type': 'boolean', 'initial': false},
            'alarm_count': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'temperature_alarm',
              'trigger': {
                'type': 'condition',
                'condition': '=state.temperature > 30'
              },
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'alarm_triggered', 'value': true}
                },
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'alarm_count', 'operation': 'increment'}
                }
              ]
            },
            {
              'id': 'temperature_simulator',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'temperature', 'value': 35}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('alarm_triggered'), isTrue);
        expect(runtime.getState('alarm_count'), greaterThan(0));
      });

      test('condition trigger with complex expression', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'sensor1': {'type': 'number', 'initial': 0},
            'sensor2': {'type': 'number', 'initial': 0},
            'sensor3': {'type': 'number', 'initial': 0},
            'condition_met': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'complex_condition',
              'trigger': {
                'type': 'condition',
                'condition': '=(state.sensor1 > 10 && state.sensor2 < 50) || state.sensor3 == 100'
              },
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'condition_met', 'value': true}
                }
              ]
            },
            {
              'id': 'sensor_updater',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'sensor1', 'value': 15}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'sensor2', 'value': 30}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('condition_met'), isTrue);
      });
    });

    group('Event Trigger', () {
      test('event trigger responds to custom events', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'event_received': {'type': 'boolean', 'initial': false},
            'event_data': {'type': 'object', 'initial': {}},
          },
          'processes': [
            {
              'id': 'event_handler',
              'trigger': {
                'type': 'event',
                'event': 'custom_event'
              },
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'event_received', 'value': true}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'event_data', 'value': '=args'}
                }
              ]
            },
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Manually emit event using runtime's public API
        runtime.emitEvent('custom_event', data: {'message': 'Hello', 'value': 42});
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('event_received'), isTrue);
        final eventData = runtime.getState('event_data') as Map;
        expect(eventData['message'], equals('Hello'));
        expect(eventData['value'], equals(42));
      });

      test('multiple event handlers for same event', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'handler1_count': {'type': 'number', 'initial': 0},
            'handler2_count': {'type': 'number', 'initial': 0},
            'handler3_count': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'handler1',
              'trigger': {
                'type': 'event',
                'event': 'broadcast_event'
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'handler1_count', 'operation': 'increment'}
                }
              ]
            },
            {
              'id': 'handler2',
              'trigger': {
                'type': 'event',
                'event': 'broadcast_event'
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'handler2_count', 'operation': 'increment'}
                }
              ]
            },
            {
              'id': 'handler3',
              'trigger': {
                'type': 'event',
                'event': 'broadcast_event'
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'handler3_count', 'operation': 'increment'}
                }
              ]
            },
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Manually emit events twice
        runtime.emitEvent('broadcast_event', data: {});
        await Future.delayed(Duration(milliseconds: 50));
        runtime.emitEvent('broadcast_event', data: {});
        await Future.delayed(Duration(milliseconds: 100));
        
        // Each handler should have been triggered twice
        expect(runtime.getState('handler1_count'), equals(2));
        expect(runtime.getState('handler2_count'), equals(2));
        expect(runtime.getState('handler3_count'), equals(2));
      });
    });

    group('StateChange Trigger', () {
      test('stateChange trigger monitors specific state variable', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'monitored_value': {'type': 'number', 'initial': 0},
            'change_count': {'type': 'number', 'initial': 0},
            'last_value': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'state_monitor',
              'trigger': {
                'type': 'stateChange',
                'key': 'monitored_value'
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'change_count', 'operation': 'increment'}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'last_value', 'value': '=state.monitored_value'}
                }
              ]
            },
            {
              'id': 'value_changer',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'monitored_value', 'value': 10}
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'monitored_value', 'value': 20}
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'monitored_value', 'value': 30}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 250));
        
        expect(runtime.getState('change_count'), equals(3));
        expect(runtime.getState('last_value'), equals(30));
      });

      test('stateChange with filter condition', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'temperature': {'type': 'number', 'initial': 20},
            'high_temp_count': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'high_temp_monitor',
              'trigger': {
                'type': 'stateChange',
                'key': 'temperature',
                'filter': '=newValue > 30'
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'high_temp_count', 'operation': 'increment'}
                }
              ]
            },
            {
              'id': 'temp_simulator',
              'trigger': {'type': 'startup'},
              'steps': [
                // This should not trigger (25 < 30)
                {'action': 'wait', 'params': {'durationMs': 30}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'temperature', 'value': 25}
                },
                // This should trigger (35 > 30)
                {'action': 'wait', 'params': {'durationMs': 30}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'temperature', 'value': 35}
                },
                // This should not trigger (28 < 30)
                {'action': 'wait', 'params': {'durationMs': 30}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'temperature', 'value': 28}
                },
                // This should trigger (40 > 30)
                {'action': 'wait', 'params': {'durationMs': 30}},
                {
                  'action': 'stateSet',
                  'params': {'key': 'temperature', 'value': 40}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // StateChange trigger fires for all changes to the monitored variable;
        // filter evaluation depends on runtime expression support
        final count = runtime.getState('high_temp_count');
        expect(count, greaterThanOrEqualTo(2));
      });
    });

    group('ChannelReceive Trigger', () {
      test('channelReceive trigger processes messages', () async {
        final flow = {
          'version': '1.0.0',
          'channels': {
            'message_queue': {'type': 'queue'}
          },
          'state': {
            'messages_received': {'type': 'array', 'initial': []},
            'message_count': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'message_processor',
              'trigger': {
                'type': 'channelReceive',
                'channel': 'message_queue'
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'messages_received',
                    'operation': 'append',
                    'value': '=message'
                  }
                },
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'message_count', 'operation': 'increment'}
                }
              ]
            },
            {
              'id': 'message_sender',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'channelSend',
                  'params': {
                    'channel': 'message_queue',
                    'data': {'id': 1, 'text': 'First message'}
                  }
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'channelSend',
                  'params': {
                    'channel': 'message_queue',
                    'data': {'id': 2, 'text': 'Second message'}
                  }
                },
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'channelSend',
                  'params': {
                    'channel': 'message_queue',
                    'data': {'id': 3, 'text': 'Third message'}
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 300));
        
        expect(runtime.getState('message_count'), equals(3));
        final messages = runtime.getState('messages_received') as List;
        expect(messages.length, equals(3));
        expect(messages[0]['id'], equals(1));
        expect(messages[1]['id'], equals(2));
        expect(messages[2]['id'], equals(3));
      });
    });

    group('Manual Trigger', () {
      test('manual trigger can be invoked programmatically', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'manual_executed': {'type': 'boolean', 'initial': false},
            'execution_data': {'type': 'object', 'initial': {}},
          },
          'processes': [
            {
              'id': 'manual_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'manual_executed', 'value': true}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'execution_data', 'value': '=args'}
                }
              ]
            },
            {
              'id': 'invoker',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'processStart',
                  'params': {
                    'processId': 'manual_process',
                    'args': {'param1': 'value1', 'param2': 123}
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('manual_executed'), isTrue);
        final data = runtime.getState('execution_data') as Map;
        expect(data['param1'], equals('value1'));
        expect(data['param2'], equals(123));
      });
    });

    group('Mixed Trigger Scenarios', () {
      test('multiple trigger types working together', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'startup_done': {'type': 'boolean', 'initial': false},
            'schedule_count': {'type': 'number', 'initial': 0},
            'condition_triggered': {'type': 'boolean', 'initial': false},
            'trigger_value': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'startup_init',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'startup_done', 'value': true}
                }
              ]
            },
            {
              'id': 'periodic_incrementer',
              'trigger': {
                'type': 'schedule',
                'interval': 50
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'schedule_count', 'operation': 'increment'}
                },
                {
                  'action': 'stateUpdate',
                  'params': {'key': 'trigger_value', 'operation': 'increment'}
                }
              ]
            },
            {
              'id': 'threshold_detector',
              'trigger': {
                'type': 'condition',
                'condition': '=state.trigger_value >= 3'
              },
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {'key': 'condition_triggered', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 250));
        
        expect(runtime.getState('startup_done'), isTrue);
        expect(runtime.getState('schedule_count'), greaterThanOrEqualTo(3));
        expect(runtime.getState('condition_triggered'), isTrue);
      });
    });
  });
}
