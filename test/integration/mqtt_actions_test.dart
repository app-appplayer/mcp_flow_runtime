import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'package:logging/logging.dart';

/// Integration test for MQTT actions
void main() {
  group('MQTT Actions Integration Tests', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('basic MQTT publish and subscribe', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'publish_executed': {'type': 'boolean', 'initial': false},
          'subscribe_executed': {'type': 'boolean', 'initial': false}
        },
        'processes': [{
          'id': 'mqtt_test',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'mqttPublish',
              'params': {
                'broker': 'mqtt://test.mosquitto.org:1883',
                'topic': 'mcp/test/topic',
                'message': 'Hello from MCP Flow'
              }
            },
            {'action': 'stateSet', 'params': {'key': 'publish_executed', 'value': true}},
            {
              'action': 'mqttSubscribe',
              'params': {
                'broker': 'mqtt://test.mosquitto.org:1883',
                'topic': 'mcp/test/response'
              }
            },
            {'action': 'stateSet', 'params': {'key': 'subscribe_executed', 'value': true}}
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 500));
      
      expect(runtime.getState('publish_executed'), isTrue);
      expect(runtime.getState('subscribe_executed'), isTrue);
    });

    test('MQTT publish with expression evaluation', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'temperature': {'type': 'number', 'initial': 25.5},
          'humidity': {'type': 'number', 'initial': 60},
          'message_sent': {'type': 'boolean', 'initial': false}
        },
        'processes': [{
          'id': 'sensor_publisher',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'mqttPublish',
              'params': {
                'broker': 'mqtt://localhost:1883',
                'topic': 'sensors/room1/data',
                'message': '=JSON.stringify({temperature: temperature, humidity: humidity})',
                'qos': 1,
                'retain': true
              }
            },
            {'action': 'stateSet', 'params': {'key': 'message_sent', 'value': true}}
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 200));
      
      expect(runtime.getState('message_sent'), isTrue);
    });

    test('MQTT error handling - missing broker', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'error_caught': {'type': 'boolean', 'initial': false},
          'error_message': {'type': 'string', 'initial': ''}
        },
        'processes': [{
          'id': 'mqtt_error_test',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'try',
              'try': [
                {
                  'action': 'mqttPublish',
                  'params': {
                    'broker': 'non_existent_broker',
                    'topic': 'test/topic',
                    'message': 'test'
                  }
                }
              ],
              'catch': [
                {'action': 'stateSet', 'params': {'key': 'error_caught', 'value': true}},
                {'action': 'stateSet', 'params': {'key': 'error_message', 'value': '=catchError.message'}}
              ]
            }
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 200));
      
      expect(runtime.getState('error_caught'), isTrue);
      expect(runtime.getState('error_message'), contains('not found'));
    });
  });
}