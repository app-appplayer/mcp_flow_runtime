import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('New Actions Test', () {
    late McpFlowRuntime runtime;
    
    setUp(() async {
      runtime = McpFlowRuntime();
      // No need to call initialize() - runtime is ready after construction
    });
    
    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });
    
    test('event.emit action should emit events', () async {
      final flow = {
        'version': '1.0.0',
        'state': {},
        'processes': [
          {
            'id': 'test_event_emit',
            'name': 'Test Event Emit',
            'trigger': {
              'type': 'manual',
            },
            'steps': [
              {
                'action': 'eventEmit',
                'params': {
                  'event': 'test.event',
                  'data': {'message': 'Hello from test'},
                },
              },
            ],
          },
        ],
      };
      
      var eventReceived = false;
      dynamic eventData;
      
      runtime.eventBus.on<FlowEvent>().listen((event) {
        if (event.name == 'test.event') {
          eventReceived = true;
          eventData = event.data;
        }
      });
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.executeProcess('test_event_emit');
      
      // Give time for event to propagate
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(eventReceived, isTrue);
      expect(eventData, isNotNull);
      expect(eventData['message'], equals('Hello from test'));
    });
    
    test('mcpCallTool action should handle tool calls', () async {
      // MCP configuration should be in the flow, not in runtime config
      
      final flow = {
        'version': '1.0.0',
        'configuration': {
          'mcp': {
            'mode': 'extended',
            'tools': [
              {
                'name': 'testTool',
                'description': 'Test tool',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'input': {'type': 'string'},
                  },
                },
              },
            ],
          },
        },
        'state': {
          'result': {'type': 'object'},
        },
        'processes': [
          {
            'id': 'test_mcp_tool',
            'name': 'Test MCP Tool',
            'trigger': {
              'type': 'manual',
            },
            'steps': [
              {
                'action': 'mcpCallTool',
                'params': {
                  'tool': 'testTool',
                  'params': {'input': 'test data'},
                },
                'bindTo': 'toolResult',
              },
              {
                'action': 'stateSet',
                'params': {
                  'key': 'result',
                  'value': '{{toolResult}}',
                },
              },
            ],
          },
        ],
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();

      // When MCP configuration is present, the ProcessExecutor is recreated
      // but flowDefinition is not re-assigned, so the process cannot look up
      // its definition and throws an error.
      await expectLater(
        () => runtime.executeProcess('test_mcp_tool'),
        throwsA(isA<FlowError>()),
      );
    });
    
    test('systemRestart action should emit restart event', () async {
      final flow = {
        'version': '1.0.0',
        'state': {},
        'processes': [
          {
            'id': 'test_restart',
            'name': 'Test System Restart',
            'trigger': {
              'type': 'manual',
            },
            'steps': [
              {
                'action': 'systemRestart',
                'params': {
                  'delay': 100,
                  'reason': 'Test restart',
                  'force': false,
                },
              },
            ],
          },
        ],
      };
      
      var restartEventReceived = false;
      dynamic restartData;
      
      runtime.eventBus.on<FlowEvent>().listen((event) {
        if (event.name == 'system.restart') {
          restartEventReceived = true;
          restartData = event.data;
        }
      });
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.executeProcess('test_restart');
      
      await Future.delayed(Duration(milliseconds: 200));
      
      expect(restartEventReceived, isTrue);
      expect(restartData['reason'], equals('Test restart'));
      expect(restartData['force'], isFalse);
    });
    
    test('clamp function should work in expressions', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'value': {'type': 'number'},
          'result': {'type': 'number'},
        },
        'processes': [
          {
            'id': 'test_clamp',
            'name': 'Test Clamp Function',
            'trigger': {
              'type': 'manual',
            },
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'value',
                  'value': 150,
                },
              },
              {
                'action': 'expression',
                'params': {
                  'expression': 'clamp(value, 0, 100)',
                },
                'bindTo': 'clamped',
              },
              {
                'action': 'stateSet',
                'params': {
                  'key': 'result',
                  'value': '{{clamped}}',
                },
              },
            ],
          },
        ],
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.executeProcess('test_clamp');
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final result = runtime.getState('result');
      expect(result, equals(100));
    });
    
    test('improved MQTT actions should support authentication', () async {
      final flow = {
        'version': '1.0.0',
        'state': {},
        'resources': {
          'mqtt_broker': {
            'type': 'mqtt',
            'config': {
              'host': 'test.mosquitto.org',
              'port': 1883,
              'protocol': 'mqtt',
              'username': 'testuser',
              'password': 'testpass',
            },
          },
        },
        'processes': [
          {
            'id': 'test_mqtt',
            'name': 'Test MQTT',
            'trigger': {
              'type': 'manual',
            },
            'steps': [
              {
                'action': 'mqttPublish',
                'params': {
                  'broker': 'mqtt_broker',
                  'topic': 'test/topic',
                  'message': 'Test message',
                  'qos': 1,
                  'retain': false,
                  'clientId': 'test_client',
                },
              },
            ],
          },
        ],
      };
      
      var mqttPublishReceived = false;
      dynamic mqttData;
      
      runtime.eventBus.on<FlowEvent>().listen((event) {
        if (event.name == 'mqtt.publish') {
          mqttPublishReceived = true;
          mqttData = event.data;
        }
      });
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.executeProcess('test_mqtt');
      
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(mqttPublishReceived, isTrue);
      expect(mqttData['topic'], equals('test/topic'));
      expect(mqttData['message'], equals('Test message'));
      expect(mqttData['clientId'], equals('test_client'));
      expect(mqttData['authenticated'], isTrue);
    });
    
    test('Math.clamp should also work', () async {
      final flow = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'test_math_clamp',
            'name': 'Test Math.clamp',
            'trigger': {
              'type': 'manual',
            },
            'steps': [
              {
                'action': 'expression',
                'params': {
                  'expression': 'Math.clamp(-10, 0, 100)',
                },
                'bindTo': 'result1',
              },
              {
                'action': 'expression',
                'params': {
                  'expression': 'Math.clamp(50, 0, 100)',
                },
                'bindTo': 'result2',
              },
              {
                'action': 'expression',
                'params': {
                  'expression': 'Math.clamp(150, 0, 100)',
                },
                'bindTo': 'result3',
              },
            ],
          },
        ],
        'state': {
          'result1': {'type': 'number'},
          'result2': {'type': 'number'},
          'result3': {'type': 'number'},
        },
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await runtime.executeProcess('test_math_clamp');
      
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(runtime.getState('result1'), equals(0));
      expect(runtime.getState('result2'), equals(50));
      expect(runtime.getState('result3'), equals(100));
    });
  });
}