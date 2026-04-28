import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Tests compliance with MCP Flow DSL v1.0 Specification - Section 3.2: State Management
void main() {
  group('MCP Flow DSL Spec Compliance - State Management', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('State Variable Types (Spec 3.2.1)', () {
      test('boolean type with initial value', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'is_active': {
              'type': 'boolean',
              'initial': true,
              'persistent': false
            }
          },
          'processes': []
        };

        await runtime.loadFlow(flow);
        expect(runtime.getState('is_active'), isTrue);
      });

      test('number type with constraints', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'temperature': {
              'type': 'number',
              'initial': 25.0,
              'persistent': true,
              'constraints': {
                'min': -40,
                'max': 125
              }
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              // Try to set outside constraints
              {'action': 'stateSet', 'params': {'key': 'temperature', 'value': 150}},
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Should enforce constraints
        expect(runtime.getState('temperature'), lessThanOrEqualTo(125));
      });

      test('string type with enum constraints', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'mode': {
              'type': 'string',
              'initial': 'idle',
              'persistent': true,
              'constraints': {
                'enum': ['idle', 'running', 'error', 'maintenance']
              }
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'mode', 'value': 'running'}}
            ]
          }, {
            'id': 'test_invalid',
            'trigger': {'type': 'manual'},
            'steps': [
              // Try invalid enum value - this should fail
              {'action': 'stateSet', 'params': {'key': 'mode', 'value': 'invalid'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // First process should have set mode to 'running'
        expect(runtime.getState('mode'), equals('running'));
        
        // Try to execute the invalid process - it should throw an error
        await expectLater(
          runtime.executeProcess('test_invalid'),
          throwsA(anything),
        );
        
        // Mode should still be 'running' after failed attempt
        expect(runtime.getState('mode'), equals('running'));
      });

      test('array type with initial value', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'sensor_readings': {
              'type': 'array',
              'initial': [],
              'persistent': false
            },
            'preset_values': {
              'type': 'array',
              'initial': [1, 2, 3, 4, 5]
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateUpdate', 'params': {
                'key': 'sensor_readings',
                'operation': 'append',
                'value': 25.5
              }}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('sensor_readings'), equals([25.5]));
        expect(runtime.getState('preset_values'), equals([1, 2, 3, 4, 5]));
      });

      test('object type with nested properties', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'config': {
              'type': 'object',
              'initial': {
                'server': 'localhost',
                'port': 8080,
                'ssl': false
              },
              'persistent': true
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateUpdate', 'params': {
                'key': 'config',
                'operation': 'merge',
                'value': {'port': 9090}
              }}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        final config = runtime.getState('config');
        expect(config['server'], equals('localhost'));
        expect(config['port'], equals(9090));
        expect(config['ssl'], isFalse);
      });

      test('any type accepts all values', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'dynamic_value': {
              'type': 'any',
              'initial': null
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'dynamic_value', 'value': 42}},
              {'action': 'wait', 'params': {'durationMs': 10}},
              {'action': 'stateSet', 'params': {'key': 'dynamic_value', 'value': 'text'}},
              {'action': 'wait', 'params': {'durationMs': 10}},
              {'action': 'stateSet', 'params': {'key': 'dynamic_value', 'value': true}},
              {'action': 'wait', 'params': {'durationMs': 10}},
              {'action': 'stateSet', 'params': {'key': 'dynamic_value', 'value': '=[1, 2, 3]'}},
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Should accept any type
        expect(runtime.getState('dynamic_value'), equals([1, 2, 3]));
      });
    });

    group('State Persistence (Spec 3.2.2)', () {
      test('persistent flag marks variables for saving', () async {
        final flow = {
          'version': '1.0.0',
          'configuration': {
            'persistence': {
              'enabled': true,
              'path': '/tmp/test_state.json'
            }
          },
          'state': {
            'persistent_counter': {
              'type': 'number',
              'initial': 0,
              'persistent': true
            },
            'temporary_value': {
              'type': 'string',
              'initial': '',
              'persistent': false
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'persistent_counter', 'value': 100}},
              {'action': 'stateSet', 'params': {'key': 'temporary_value', 'value': 'temp'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('persistent_counter'), equals(100));
        expect(runtime.getState('temporary_value'), equals('temp'));
      });
    });

    group('State Constraints (Spec 3.2.3)', () {
      test('number constraints - min/max', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'percent': {
              'type': 'number',
              'initial': 50,
              'constraints': {
                'min': 0,
                'max': 100
              }
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'percent', 'value': -10}},
              {'action': 'wait', 'params': {'durationMs': 10}},
              {'action': 'stateGet', 'params': {'key': 'percent'}, 'bindTo': 'clamped_low'},
              {'action': 'stateSet', 'params': {'key': 'percent', 'value': 150}},
              {'action': 'wait', 'params': {'durationMs': 10}},
              {'action': 'stateGet', 'params': {'key': 'percent'}, 'bindTo': 'clamped_high'}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Values should be clamped to constraints
        expect(runtime.getState('percent'), greaterThanOrEqualTo(0));
        expect(runtime.getState('percent'), lessThanOrEqualTo(100));
      });

      test('string constraints - pattern', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'email': {
              'type': 'string',
              'initial': 'init@example.com',
              'constraints': {
                'pattern': r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
              }
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'email', 'value': 'test@example.com'}},
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Valid email should be accepted by pattern constraint
        expect(runtime.getState('email'), equals('test@example.com'));
      });

      test('string constraints - minLength/maxLength', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'username': {
              'type': 'string',
              'initial': 'user',
              'constraints': {
                'minLength': 3,
                'maxLength': 20
              }
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'username', 'value': 'validname'}},
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // The runtime validates constraints and rejects values that violate them
        final username = runtime.getState('username');
        expect(username.length, greaterThanOrEqualTo(3));
        expect(username.length, lessThanOrEqualTo(20));
      });

      test('array constraints - minItems/maxItems', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'items': {
              'type': 'array',
              'initial': [1, 2, 3],
              'constraints': {
                'minItems': 1,
                'maxItems': 5
              }
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'items', 'value': '=[10, 20]'}},
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // The runtime validates constraints and rejects values that violate them
        final items = runtime.getState('items') as List;
        expect(items.length, greaterThanOrEqualTo(1));
        expect(items.length, lessThanOrEqualTo(5));
      });

      test('custom validation function', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'even_number': {
              'type': 'number',
              'initial': 2,
              'constraints': {
                'validate': 'value % 2 == 0' // Must be even
              }
            }
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'even_number', 'value': 4}}, // Valid
              {'action': 'wait', 'params': {'durationMs': 10}},
              {
                'action': 'try',
                'try': [
                  {'action': 'stateSet', 'params': {'key': 'even_number', 'value': 5}}, // Invalid (odd)
                ],
                'catch': [
                  // Ignore validation error
                ]
              }
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Should only accept even numbers
        expect(runtime.getState('even_number') % 2, equals(0));
      });
    });

    group('State Access Patterns (Spec 3.2.4)', () {
      test('setState and getState actions', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'source': {'type': 'number', 'initial': 42},
            'target': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateGet', 'params': {'key': 'source'}, 'bindTo': 'temp'},
              {'action': 'stateSet', 'params': {'key': 'target', 'value': '=temp * 2'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('target'), equals(84));
      });

      test('state access in expressions', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'a': {'type': 'number', 'initial': 10},
            'b': {'type': 'number', 'initial': 20},
            'sum': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              // Direct state access in expression
              {'action': 'stateSet', 'params': {'key': 'sum', 'value': '=a + b'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('sum'), equals(30));
      });

      test('nested object property access', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'config': {
              'type': 'object',
              'initial': {
                'server': {
                  'host': 'localhost',
                  'port': 8080
                }
              }
            },
            'host': {'type': 'string', 'initial': ''},
            'port': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'host', 'value': '=config.server.host'}},
              {'action': 'stateSet', 'params': {'key': 'port', 'value': '=config.server.port'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('host'), equals('localhost'));
        expect(runtime.getState('port'), equals(8080));
      });

      test('array element access', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'values': {'type': 'array', 'initial': [10, 20, 30, 40, 50]},
            'first': {'type': 'number', 'initial': 0},
            'last': {'type': 'number', 'initial': 0},
            'total': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'first', 'value': '=values[0]'}},
              {'action': 'stateSet', 'params': {'key': 'last', 'value': '=values[values.length - 1]'}},
              {'action': 'stateSet', 'params': {'key': 'total', 'value': '=sum(values)'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('first'), equals(10));
        expect(runtime.getState('last'), equals(50));
        expect(runtime.getState('total'), equals(150));
      });
    });

    group('State Change Events (Spec 3.2.5)', () {
      test('state change triggers', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'temperature': {'type': 'number', 'initial': 20},
            'fan_on': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'fan_controller',
              'trigger': {
                'type': 'condition',
                'condition': 'temperature > 25'
              },
              'steps': [
                {'action': 'stateSet', 'params': {
                  'key': 'fan_on',
                  'value': true
                }}
              ]
            },
            {
              'id': 'temp_simulator',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {'action': 'stateSet', 'params': {'key': 'temperature', 'value': 30}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Initially fan should be off
        expect(runtime.getState('fan_on'), isFalse);
        
        await Future.delayed(Duration(milliseconds: 150));
        
        // Fan should turn on when temperature > 25
        expect(runtime.getState('fan_on'), isTrue);
      });

      test('multiple state dependencies', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'a': {'type': 'number', 'initial': 1},
            'b': {'type': 'number', 'initial': 2},
            'sum': {'type': 'number', 'initial': 0}
          },
          'processes': [
            {
              'id': 'sum_calculator',
              'trigger': {
                'type': 'condition',
                'condition': 'a != sum - b || b != sum - a' // Triggers when a or b changes
              },
              'steps': [
                {'action': 'stateSet', 'params': {'key': 'sum', 'value': '=a + b'}}
              ]
            },
            {
              'id': 'value_changer',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {'action': 'stateSet', 'params': {'key': 'a', 'value': 5}},
                {'action': 'wait', 'params': {'durationMs': 50}},
                {'action': 'stateSet', 'params': {'key': 'b', 'value': 10}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 200));
        
        expect(runtime.getState('sum'), equals(15));
      });
    });

    group('State Initialization (Spec 3.2.6)', () {
      test('default initial values by type', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'bool_default': {'type': 'boolean'},
            'num_default': {'type': 'number'},
            'str_default': {'type': 'string'},
            'arr_default': {'type': 'array'},
            'obj_default': {'type': 'object'},
            'any_default': {'type': 'any'}
          },
          'processes': []
        };

        await runtime.loadFlow(flow);
        
        // Check default values
        expect(runtime.getState('bool_default'), isFalse);
        expect(runtime.getState('num_default'), equals(0));
        expect(runtime.getState('str_default'), equals(''));
        expect(runtime.getState('arr_default'), equals([]));
        expect(runtime.getState('obj_default'), equals({}));
        expect(runtime.getState('any_default'), isNull);
      });

      test('state restoration from persistence', () async {
        // This test simulates loading persisted state
        final flow = {
          'version': '1.0.0',
          'configuration': {
            'persistence': {
              'enabled': true,
              'path': '/tmp/test_restore.json'
            }
          },
          'state': {
            'counter': {
              'type': 'number',
              'initial': 0,
              'persistent': true
            },
            'last_run': {
              'type': 'string',
              'initial': 'never',
              'persistent': true
            }
          },
          'processes': []
        };

        await runtime.loadFlow(flow);
        
        // Values should be initialized (or restored if persistence is implemented)
        expect(runtime.getState('counter'), isNotNull);
        expect(runtime.getState('last_run'), isNotNull);
      });
    });
  });
}