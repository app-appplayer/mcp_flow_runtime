import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Convenience State Actions (Spec 6.3.2)', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      await runtime.stop();
    });

    group('increment action', () {
      test('increments numeric value by default amount (1)', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 10}
          },
          'processes': [
            {
              'id': 'increment_test',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'increment',
                  'params': {'key': 'counter'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('counter'), equals(11));
      });

      test('increments numeric value by custom amount', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 10}
          },
          'processes': [
            {
              'id': 'increment_custom',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'increment',
                  'params': {'key': 'counter', 'value': 5}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('counter'), equals(15));
      });

      test('throws error for non-numeric value', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'text': {'type': 'string', 'initial': 'hello'},
            'error_caught': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'increment_string',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'increment',
                  'params': {'key': 'text'}
                }
              ],
              // Add error handler to capture the error
              'error': [
                {'action': 'stateSet', 'params': {'key': 'error_caught', 'value': true}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));
        
        // The process should have failed and error handler should have run
        expect(runtime.getState('error_caught'), equals(true));
      });
    });

    group('decrement action', () {
      test('decrements numeric value by default amount (1)', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 10}
          },
          'processes': [
            {
              'id': 'decrement_test',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'decrement',
                  'params': {'key': 'counter'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('counter'), equals(9));
      });

      test('decrements numeric value by custom amount', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 10}
          },
          'processes': [
            {
              'id': 'decrement_custom',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'decrement',
                  'params': {'key': 'counter', 'value': 3}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('counter'), equals(7));
      });
    });

    group('append action', () {
      test('appends value to list', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'items': {
              'type': 'array',
              'initial': [1, 2, 3]
            }
          },
          'processes': [
            {
              'id': 'append_test',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'append',
                  'params': {'key': 'items', 'value': 4}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('items'), equals([1, 2, 3, 4]));
      });

      test('appends object to list', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'users': {
              'type': 'array',
              'initial': [
                {'id': 1, 'name': 'Alice'},
                {'id': 2, 'name': 'Bob'}
              ]
            }
          },
          'processes': [
            {
              'id': 'append_object',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'append',
                  'params': {
                    'key': 'users',
                    'value': {'id': 3, 'name': 'Charlie'}
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        final users = runtime.getState('users') as List;
        expect(users.length, equals(3));
        expect(users[2], equals({'id': 3, 'name': 'Charlie'}));
      });

      test('throws error for non-list value', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'number': {'type': 'number', 'initial': 42},
            'error_caught': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'append_to_number',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'append',
                  'params': {'key': 'number', 'value': 5}
                }
              ],
              'error': [
                {'action': 'stateSet', 'params': {'key': 'error_caught', 'value': true}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));
        
        // The process should have failed and error handler should have run
        expect(runtime.getState('error_caught'), equals(true));
      });
    });

    group('merge action', () {
      test('merges objects', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'config': {
              'type': 'object',
              'initial': {
                'host': 'localhost',
                'port': 8080
              }
            }
          },
          'processes': [
            {
              'id': 'merge_test',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'merge',
                  'params': {
                    'key': 'config',
                    'value': {
                      'port': 3000,
                      'ssl': true
                    }
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('config'), equals({
          'host': 'localhost',
          'port': 3000,
          'ssl': true
        }));
      });

      test('throws error for non-map values', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'list': {'type': 'array', 'initial': [1, 2, 3]},
            'error_caught': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'merge_to_list',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'merge',
                  'params': {
                    'key': 'list',
                    'value': {'new': 'value'}
                  }
                }
              ],
              'error': [
                {'action': 'stateSet', 'params': {'key': 'error_caught', 'value': true}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));
        
        // The process should have failed and error handler should have run
        expect(runtime.getState('error_caught'), equals(true));
      });
    });

    group('toggle action', () {
      test('toggles boolean from true to false', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'enabled': {'type': 'boolean', 'initial': true}
          },
          'processes': [
            {
              'id': 'toggle_test',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'toggle',
                  'params': {'key': 'enabled'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('enabled'), equals(false));
      });

      test('toggles boolean from false to true', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'enabled': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'toggle_test',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'toggle',
                  'params': {'key': 'enabled'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('enabled'), equals(true));
      });

      test('toggles multiple times', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'flag': {'type': 'boolean', 'initial': true}
          },
          'processes': [
            {
              'id': 'multi_toggle',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'toggle',
                  'params': {'key': 'flag'}
                },
                {
                  'action': 'toggle',
                  'params': {'key': 'flag'}
                },
                {
                  'action': 'toggle',
                  'params': {'key': 'flag'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Toggled 3 times: true -> false -> true -> false
        expect(runtime.getState('flag'), equals(false));
      });

      test('throws error for non-boolean value', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'text': {'type': 'string', 'initial': 'hello'},
            'error_caught': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'toggle_string',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'toggle',
                  'params': {'key': 'text'}
                }
              ],
              'error': [
                {'action': 'stateSet', 'params': {'key': 'error_caught', 'value': true}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));
        
        // The process should have failed and error handler should have run
        expect(runtime.getState('error_caught'), equals(true));
      });
    });

    group('Integration tests', () {
      test('combines multiple convenience actions', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 0},
            'history': {'type': 'array', 'initial': []},
            'settings': {
              'type': 'object',
              'initial': {'mode': 'basic'}
            },
            'active': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'combined_test',
              'trigger': {'type': 'startup'},
              'steps': [
                // Increment counter
                {'action': 'increment', 'params': {'key': 'counter', 'value': 5}},
                // Append to history
                {'action': 'append', 'params': {'key': 'history', 'value': 'started'}},
                // Toggle active
                {'action': 'toggle', 'params': {'key': 'active'}},
                // Merge settings
                {
                  'action': 'merge',
                  'params': {
                    'key': 'settings',
                    'value': {'advanced': true, 'level': 2}
                  }
                },
                // Decrement counter
                {'action': 'decrement', 'params': {'key': 'counter', 'value': 2}},
                // Append again
                {'action': 'append', 'params': {'key': 'history', 'value': 'completed'}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 200));

        expect(runtime.getState('counter'), equals(3)); // 0 + 5 - 2
        expect(runtime.getState('history'), equals(['started', 'completed']));
        expect(runtime.getState('settings'), equals({
          'mode': 'basic',
          'advanced': true,
          'level': 2
        }));
        expect(runtime.getState('active'), equals(true));
      });

      test('convenience actions work with expressions', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'base': {'type': 'number', 'initial': 10},
            'multiplier': {'type': 'number', 'initial': 2},
            'result': {'type': 'number', 'initial': 0}
          },
          'processes': [
            {
              'id': 'expression_test',
              'trigger': {'type': 'startup'},
              'steps': [
                // Set result to base * multiplier
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'result',
                    'value': '=state.base * state.multiplier'
                  }
                },
                // Increment result by 5
                {'action': 'increment', 'params': {'key': 'result', 'value': 5}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('result'), equals(25)); // (10 * 2) + 5
      });
    });
  });
}