import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Channel minimal tests', () {
    test('empty flow with channels only', () async {
      final runtime = McpFlowRuntime();
      
      final flow = {
        'version': '1.0.0',
        'channels': {
          'test': {'type': 'queue'}
        },
        'processes': []
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 100));
      
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () => throw Exception('Timeout with just channels')
      );
      
      print('✓ Just channels: OK');
    });
    
    test('channels with manual process', () async {
      final runtime = McpFlowRuntime();
      
      final flow = {
        'version': '1.0.0',
        'channels': {
          'test': {'type': 'queue'}
        },
        'processes': [{
          'id': 'manual',
          'trigger': {'type': 'manual'},
          'steps': [{'action': 'log', 'params': {'message': 'test'}}]
        }]
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 100));
      
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () => throw Exception('Timeout with channels + manual')
      );
      
      print('✓ Channels + manual: OK');
    });
    
    test('scheduled process without channels', () async {
      final runtime = McpFlowRuntime();
      
      final flow = {
        'version': '1.0.0',
        'processes': [{
          'id': 'scheduled',
          'trigger': {'type': 'schedule', 'interval': 60000},
          'steps': [{'action': 'log', 'params': {'message': 'test'}}]
        }]
      };
      
      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 100));
      
      await runtime.stop().timeout(
        Duration(seconds: 2),
        onTimeout: () => throw Exception('Timeout with scheduled only')
      );
      
      print('✓ Scheduled only: OK');
    });
  });
}