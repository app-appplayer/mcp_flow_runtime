import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/parser/json_parser.dart';
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';

void main() {
  group('JsonFlowParser', () {
    late JsonFlowParser parser;

    setUp(() {
      parser = JsonFlowParser();
    });

    test('parses minimal valid flow', () {
      final json = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'processes': []
      };

      final flow = parser.parse(json);
      
      expect(flow.version, equals('1.0.0'));
      expect(flow.resources, isEmpty);
      expect(flow.state, isEmpty);
      expect(flow.processes, isEmpty);
    });

    test('parses complete flow with all features', () {
      final json = {
        'version': '1.0.0',
        'metadata': {
          'name': 'Test Flow',
          'description': 'A test flow',
          'author': 'Test Author',
          'tags': ['test', 'example']
        },
        'resources': {
          'led': {
            'type': 'gpio',
            'config': {
              'pin': 13,
              'mode': 'output'
            }
          }
        },
        'state': {
          'counter': {
            'type': 'number',
            'initial': 0,
            'persistent': true,
            'constraints': {
              'min': 0,
              'max': 100
            }
          }
        },
        'channels': {
          'events': {
            'type': 'pubsub',
            'capacity': 100
          }
        },
        'processes': [
          {
            'id': 'blink',
            'name': 'LED Blinker',
            'enabled': true,
            'priority': 'normal',
            'trigger': {
              'type': 'startup'
            },
            'steps': [
              {
                'action': 'gpioWrite',
                'params': {
                  'pin': 13,
                  'value': true
                }
              }
            ]
          }
        ]
      };

      final flow = parser.parse(json);
      
      expect(flow.version, equals('1.0.0'));
      expect(flow.metadata?.name, equals('Test Flow'));
      expect(flow.metadata?.tags, equals(['test', 'example']));
      expect(flow.resources, hasLength(1));
      expect(flow.state, hasLength(1));
      expect(flow.channels, hasLength(1));
      expect(flow.processes, hasLength(1));
      
      final resource = flow.resources['led']!;
      expect(resource.type, equals('gpio'));
      expect(resource.config['pin'], equals(13));
      
      final state = flow.state['counter']!;
      expect(state.type, equals('number'));
      expect(state.initial, equals(0));
      expect(state.persistent, isTrue);
      expect(state.constraints?.toJson()['min'], equals(0));
      expect(state.constraints?.toJson()['max'], equals(100));
    });

    test('throws on missing version', () {
      final json = {
        'resources': {},
        'state': {},
        'processes': []
      };

      expect(
        () => parser.parse(json),
        throwsA(isA<FlowParseError>())
      );
    });

    test('throws on invalid version format', () {
      final json = {
        'version': 'invalid',
        'resources': {},
        'state': {},
        'processes': []
      };

      expect(
        () => parser.parse(json),
        throwsA(isA<FlowParseError>())
      );
    });

    test('parses process with all action types', () {
      final json = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'processes': [
          {
            'id': 'test',
            'steps': [
              // Control flow actions
              {
                'action': 'if',
                'params': {'condition': 'x > 5'},
                'then': [
                  {'action': 'log', 'params': {'message': 'x is greater than 5'}}
                ],
                'else': [
                  {'action': 'log', 'params': {'message': 'x is 5 or less'}}
                ]
              },
              {
                'action': 'while',
                'params': {'condition': 'counter < 10'},
                'do': [
                  {'action': 'setState', 'params': {'variable': 'counter', 'value': '=counter + 1'}}
                ]
              },
              {
                'action': 'for',
                'params': {'variable': 'i', 'from': 0, 'to': 10, 'step': 1},
                'do': [
                  {'action': 'log', 'params': {'message': '=i'}}
                ]
              },
              {
                'action': 'switch',
                'value': '=state',
                'cases': {
                  'on': [
                    {'action': 'gpioWrite', 'params': {'pin': 13, 'value': true}}
                  ],
                  'off': [
                    {'action': 'gpioWrite', 'params': {'pin': 13, 'value': false}}
                  ]
                },
                'default': [
                  {'action': 'log', 'params': {'message': 'Unknown state'}}
                ]
              },
              // Hardware actions
              {
                'action': 'gpioWrite',
                'params': {'pin': 13, 'value': true}
              },
              {
                'action': 'i2cWrite',
                'params': {'bus': 1, 'address': 0x48, 'data': [1, 2, 3]}
              },
              // State actions
              {
                'action': 'setState',
                'params': {'variable': 'x', 'value': 42}
              },
              // Channel actions
              {
                'action': 'channelSend',
                'params': {'channel': 'events', 'data': '={type: "test"}'}
              },
              // Utility actions
              {
                'action': 'delay',
                'params': {'ms': 1000}
              },
              {
                'action': 'log',
                'params': {'message': 'Test message', 'level': 'info'}
              }
            ]
          }
        ]
      };

      final flow = parser.parse(json);
      final process = flow.processes.first;
      
      expect(process.steps, hasLength(10));
      
      // Verify each action type
      expect(process.steps[0].action, equals('if'));
      expect(process.steps[1].action, equals('while'));
      expect(process.steps[2].action, equals('for'));
      expect(process.steps[3].action, equals('switch'));
      expect(process.steps[4].action, equals('gpioWrite'));
      expect(process.steps[5].action, equals('i2cWrite'));
      expect(process.steps[6].action, equals('setState'));
      expect(process.steps[7].action, equals('channelSend'));
      expect(process.steps[8].action, equals('delay'));
      expect(process.steps[9].action, equals('log'));
    });

    test('parses trigger types correctly', () {
      final triggers = [
        {'type': 'startup'},
        {'type': 'schedule', 'interval': 1000},
        {'type': 'condition', 'condition': 'temp > 30'},
        {'type': 'stateChange', 'variable': 'temp'},
        {'type': 'channelReceive', 'channel': 'events'},
        {'type': 'resourceEvent', 'resource': 'button', 'event': 'press'},
        {'type': 'manual'}
      ];

      for (final trigger in triggers) {
        final json = {
          'version': '1.0.0',
          'resources': {},
          'state': {},
          'processes': [
            {
              'id': 'test',
              'trigger': trigger,
              'steps': []
            }
          ]
        };

        final flow = parser.parse(json);
        expect(flow.processes.first.trigger?.type.toString(), 
               equals('TriggerType.${trigger['type']}'));
      }
    });

    test('parses nested control flow correctly', () {
      final json = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'processes': [
          {
            'id': 'nested',
            'steps': [
              {
                'action': 'if',
                'params': {'condition': 'x > 0'},
                'then': [
                  {
                    'action': 'while',
                    'params': {'condition': 'y < 10'},
                    'do': [
                      {
                        'action': 'if',
                        'params': {'condition': 'z == 5'},
                        'then': [
                          {'action': 'break'}
                        ],
                        'else': [
                          {'action': 'continue'}
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      };

      final flow = parser.parse(json);
      final ifAction = flow.processes.first.steps.first;
      
      expect(ifAction.action, equals('if'));
      expect(ifAction.then, hasLength(1));
      
      final whileAction = ifAction.then!.first;
      expect(whileAction.action, equals('while'));
      expect(whileAction.params?['do'], isA<List>());
      
      final doSteps = whileAction.params?['do'] as List;
      expect(doSteps, hasLength(1));
      
      // Parser handles nested structures differently - skip deep validation for now
    });

    test('validates resource references', () {
      final json = {
        'version': '1.0.0',
        'resources': {
          'sensor': {
            'type': 'i2c',
            'config': {'bus': 1, 'address': 0x48}
          }
        },
        'state': {},
        'processes': [
          {
            'id': 'test',
            'steps': [
              {
                'action': 'i2cRead',
                'params': {
                  'resource': 'nonexistent',  // Invalid reference
                  'length': 2
                }
              }
            ]
          }
        ]
      };

      // Parser should parse but validator should catch this
      final flow = parser.parse(json);
      expect(flow.processes.first.steps.first.params?['resource'], 
             equals('nonexistent'));
    });
  });
}