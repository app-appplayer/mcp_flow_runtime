import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Channel stop specific combination tests', () {
    test('channels + scheduled process only', () async {
      final runtime = McpFlowRuntime();
      
      final flow = {
        'version': '1.0.0',
        'channels': {
          'commands': {'type': 'queue', 'capacity': 10},
        },
        'processes': [
          {
            'id': 'scheduled_process',
            'trigger': {'type': 'schedule', 'interval': 60000},
            'steps': [{'action': 'log', 'params': {'message': 'scheduled'}}]
          }
        ]
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 100));
      
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () => throw Exception('Timeout with channels + scheduled')
      );
      
      print('✓ channels + scheduled process: OK');
    });
    
    test('channels + conditional process only', () async {
      final runtime = McpFlowRuntime();
      
      final flow = {
        'version': '1.0.0',
        'state': {'x': {'type': 'number', 'initial': 0}},
        'channels': {
          'commands': {'type': 'queue', 'capacity': 10},
        },
        'processes': [
          {
            'id': 'conditional_process',
            'trigger': {'type': 'condition', 'condition': 'x > 5'},
            'steps': [{'action': 'log', 'params': {'message': 'condition'}}]
          }
        ]
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 100));
      
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () => throw Exception('Timeout with channels + conditional')
      );
      
      print('✓ channels + conditional process: OK');
    });
    
    test('channels + scheduled + conditional processes', () async {
      final runtime = McpFlowRuntime();
      
      final flow = {
        'version': '1.0.0',
        'state': {'x': {'type': 'number', 'initial': 0}},
        'channels': {
          'commands': {'type': 'queue', 'capacity': 10},
        },
        'processes': [
          {
            'id': 'scheduled_process',
            'trigger': {'type': 'schedule', 'interval': 60000},
            'steps': [{'action': 'log', 'params': {'message': 'scheduled'}}]
          },
          {
            'id': 'conditional_process',
            'trigger': {'type': 'condition', 'condition': 'x > 5'},
            'steps': [{'action': 'log', 'params': {'message': 'condition'}}]
          }
        ]
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 100));
      
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () => throw Exception('Timeout with channels + scheduled + conditional')
      );
      
      print('✓ channels + scheduled + conditional: OK');
    });
  });
}