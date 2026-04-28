import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Tests for MCP Flow DSL v1.0 Specification - Section 6.5.4: Shared Memory Actions
void main() {
  group('MCP Flow DSL Spec - Memory Actions', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('Basic Memory Operations', () {
      test('memoryWrite and memoryRead operations', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'read_value': {'type': 'any', 'initial': null},
            'write_complete': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'writer',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'shared_data',
                    'offset': 0,
                    'data': {'temperature': 25.5, 'humidity': 60}
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'write_complete', 'value': true}
                },
              ]
            },
            {
              'id': 'reader',
              'trigger': {'type': 'startup'},
              'steps': [
                // Wait for write to complete
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'shared_data',
                    'offset': 0,
                    'length': 100
                  },
                  'bindTo': 'data'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'read_value', 'value': '=data'}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('write_complete'), isTrue);
        final readValue = runtime.getState('read_value');
        expect(readValue, isNotNull);
        expect(readValue, isA<Map>());
        expect((readValue as Map)['temperature'], equals(25.5));
        expect(readValue['humidity'], equals(60));
      });

      test('memoryWrite with offset', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'buffer_content': {'type': 'array', 'initial': []},
          },
          'processes': [
            {
              'id': 'buffer_writer',
              'trigger': {'type': 'startup'},
              'steps': [
                // Write at different offsets
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'buffer',
                    'offset': 0,
                    'data': [1, 2, 3]
                  }
                },
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'buffer',
                    'offset': 3,
                    'data': [4, 5, 6]
                  }
                },
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'buffer',
                    'offset': 6,
                    'data': [7, 8, 9]
                  }
                },
                // Read entire buffer
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'buffer',
                    'offset': 0,
                    'length': 9
                  },
                  'bindTo': 'fullBuffer'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'buffer_content', 'value': '=fullBuffer'}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        final buffer = runtime.getState('buffer_content');
        expect(buffer, equals([1, 2, 3, 4, 5, 6, 7, 8, 9]));
      });
    });

    group('Atomic Memory Operations', () {
      test('memoryAtomic add operation', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'final_value': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'atomic_adder1',
              'trigger': {'type': 'startup'},
              'steps': [
                // Initialize memory
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'counter',
                    'offset': 0,
                    'data': 0
                  }
                },
                // Perform atomic additions
                {
                  'action': 'for',
                  'params': {
                    'variable': 'i',
                    'from': 0,
                    'to': 9,  // 0-9 = 10 iterations (inclusive)
                    'step': 1
                  },
                  'do': [
                    {
                      'action': 'memoryAtomic',
                      'params': {
                        'region': 'counter',
                        'offset': 0,
                        'operation': 'add',
                        'value': 1
                      }
                    }
                  ]
                },
              ]
            },
            {
              'id': 'atomic_adder2',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 10}},
                {
                  'action': 'for',
                  'params': {
                    'variable': 'j',
                    'from': 0,
                    'to': 9,  // 0-9 = 10 iterations (inclusive)
                    'step': 1
                  },
                  'do': [
                    {
                      'action': 'memoryAtomic',
                      'params': {
                        'region': 'counter',
                        'offset': 0,
                        'operation': 'add',
                        'value': 1
                      }
                    }
                  ]
                },
              ]
            },
            {
              'id': 'reader',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 200}},
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'counter',
                    'offset': 0,
                    'length': 1
                  },
                  'bindTo': 'counter'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'final_value', 'value': '=counter'}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 300));
        
        // Both processes add 10 each = 20 total
        expect(runtime.getState('final_value'), equals(20));
      });

      test('memoryAtomic compareExchange operation', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'exchange_success': {'type': 'boolean', 'initial': false},
            'exchange_failed': {'type': 'boolean', 'initial': false},
            'previous_value': {'type': 'number', 'initial': -1},
          },
          'processes': [
            {
              'id': 'initializer',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'atomic_var',
                    'offset': 0,
                    'data': 100
                  }
                },
              ]
            },
            {
              'id': 'exchanger1',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 50}},
                {
                  'action': 'memoryAtomic',
                  'params': {
                    'region': 'atomic_var',
                    'offset': 0,
                    'operation': 'compareExchange',
                    'expected': 100,
                    'value': 200
                  },
                  'bindTo': 'prevVal'
                },
                {
                  'action': 'if',
                  'condition': '=prevVal == 100',
                  'then': [
                    {
                      'action': 'stateSet',
                      'params': {'key': 'exchange_success', 'value': true}
                    }
                  ]
                },
              ]
            },
            {
              'id': 'exchanger2',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 100}},
                {
                  'action': 'memoryAtomic',
                  'params': {
                    'region': 'atomic_var',
                    'offset': 0,
                    'operation': 'compareExchange',
                    'expected': 100,
                    'value': 300
                  },
                  'bindTo': 'prevVal2'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'previous_value', 'value': '=prevVal2'}
                },
                {
                  'action': 'if',
                  'condition': '=prevVal2 != 100',
                  'then': [
                    {
                      'action': 'stateSet',
                      'params': {'key': 'exchange_failed', 'value': true}
                    }
                  ]
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // First exchange should succeed
        expect(runtime.getState('exchange_success'), isTrue);
        // Second exchange should fail (value is now 200, not 100)
        expect(runtime.getState('exchange_failed'), isTrue);
        expect(runtime.getState('previous_value'), equals(200));
      });

      test('memoryAtomic bitwise operations', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'and_result': {'type': 'number', 'initial': 0},
            'or_result': {'type': 'number', 'initial': 0},
            'xor_result': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'bitwise_ops',
              'trigger': {'type': 'startup'},
              'steps': [
                // Initialize with 0b11110000 (240)
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'flags',
                    'offset': 0,
                    'data': 240
                  }
                },
                // AND with 0b10101010 (170) = 0b10100000 (160)
                {
                  'action': 'memoryAtomic',
                  'params': {
                    'region': 'flags',
                    'offset': 0,
                    'operation': 'and',
                    'value': 170
                  }
                },
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'flags',
                    'offset': 0,
                    'length': 1
                  },
                  'bindTo': 'andResult'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'and_result', 'value': '=andResult'}
                },
                // OR with 0b00001111 (15) = 0b10101111 (175)
                {
                  'action': 'memoryAtomic',
                  'params': {
                    'region': 'flags',
                    'offset': 0,
                    'operation': 'or',
                    'value': 15
                  }
                },
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'flags',
                    'offset': 0,
                    'length': 1
                  },
                  'bindTo': 'orResult'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'or_result', 'value': '=orResult'}
                },
                // XOR with 0b11111111 (255) = 0b01010000 (80)
                {
                  'action': 'memoryAtomic',
                  'params': {
                    'region': 'flags',
                    'offset': 0,
                    'operation': 'xor',
                    'value': 255
                  }
                },
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'flags',
                    'offset': 0,
                    'length': 1
                  },
                  'bindTo': 'xorResult'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'xor_result', 'value': '=xorResult'}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('and_result'), equals(160));
        expect(runtime.getState('or_result'), equals(175));
        expect(runtime.getState('xor_result'), equals(80));
      });
    });

    group('Memory Regions', () {
      test('multiple memory regions isolation', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'region1_data': {'type': 'any', 'initial': null},
            'region2_data': {'type': 'any', 'initial': null},
          },
          'processes': [
            {
              'id': 'region_writer',
              'trigger': {'type': 'startup'},
              'steps': [
                // Write to different regions
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'sensors',
                    'offset': 0,
                    'data': {'type': 'temperature', 'value': 25}
                  }
                },
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'actuators',
                    'offset': 0,
                    'data': {'type': 'motor', 'speed': 1500}
                  }
                },
                // Read from each region
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'sensors',
                    'offset': 0,
                    'length': 100
                  },
                  'bindTo': 'sensorData'
                },
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'actuators',
                    'offset': 0,
                    'length': 100
                  },
                  'bindTo': 'actuatorData'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'region1_data', 'value': '=sensorData'}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'region2_data', 'value': '=actuatorData'}
                },
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        final region1 = runtime.getState('region1_data');
        final region2 = runtime.getState('region2_data');
        
        expect(region1, isA<Map>());
        expect((region1 as Map)['type'], equals('temperature'));
        expect(region1['value'], equals(25));
        
        expect(region2, isA<Map>());
        expect((region2 as Map)['type'], equals('motor'));
        expect(region2['speed'], equals(1500));
      });
    });
  });
}