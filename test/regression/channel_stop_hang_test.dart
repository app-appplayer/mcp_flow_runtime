import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Channel stop hang regression test', () {
    test('runtime should stop cleanly with channels and multiple trigger types', () async {
      final runtime = McpFlowRuntime();
      
      // This is the exact flow that causes hanging in flowos_core
      final flow = {
        'version': '1.0.0',
        'state': {
          'counter': {'type': 'number', 'initial': 0},
          'flag': {'type': 'boolean', 'initial': false}
        },
        'channels': {
          'commands': {'type': 'queue', 'capacity': 10},
          'events': {'type': 'pubsub'}
        },
        'processes': [
          {
            'id': 'manual_process',
            'name': 'Manual Process',
            'trigger': {'type': 'manual'},
            'steps': [{'action': 'stateSet', 'params': {'key': 'flag', 'value': true}}]
          },
          {
            'id': 'scheduled_process', 
            'name': 'Scheduled Process',
            'trigger': {'type': 'schedule', 'interval': 60000, 'unit': 'milliseconds'},
            'steps': [{'action': 'stateSet', 'params': {'key': 'counter', 'value': 1}}]
          },
          {
            'id': 'conditional_process',
            'name': 'Conditional Process',
            'trigger': {'type': 'condition', 'condition': 'counter > 5'},
            'steps': [{'action': 'stateSet', 'params': {'key': 'flag', 'value': true}}]
          }
        ]
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait briefly
      await Future.delayed(Duration(milliseconds: 100));
      
      // This should complete without hanging
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () {
          throw Exception('Runtime stop timed out - this is the bug!');
        }
      );
    });
    
    test('runtime should stop cleanly even with channelReceive trigger', () async {
      final runtime = McpFlowRuntime();
      
      final flow = {
        'version': '1.0.0',
        'channels': {
          'test_channel': {'type': 'queue'}
        },
        'processes': [
          {
            'id': 'receiver',
            'trigger': {
              'type': 'channelReceive',
              'channel': 'test_channel'
            },
            'steps': [
              {'action': 'log', 'params': {'message': 'Received'}}
            ]
          }
        ]
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait briefly
      await Future.delayed(Duration(milliseconds: 100));
      
      // This should complete without hanging
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () {
          throw Exception('Runtime stop timed out with channelReceive trigger!');
        }
      );
    });
  });
}