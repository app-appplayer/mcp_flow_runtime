import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  test('Channel with listener (channelReceive trigger)', () async {
    final runtime = McpFlowRuntime();
    
    print('Creating flow with channelReceive trigger...');
    final flow = {
      'version': '1.0.0',
      'channels': {
        'test_channel': {'type': 'queue'}
      },
      'processes': [{
        'id': 'receiver',
        'trigger': {
          'type': 'channelReceive',
          'channel': 'test_channel'
        },
        'steps': [
          {'action': 'log', 'params': {'message': 'Received'}}
        ]
      }]
    };
    
    await runtime.loadFlow(flow);
    await runtime.start();
    await Future.delayed(Duration(milliseconds: 100));
    
    print('Attempting to stop runtime...');
    await runtime.stop().timeout(
      Duration(seconds: 2),
      onTimeout: () => throw Exception('Timeout with channelReceive trigger!')
    );
    
    print('✓ Runtime stopped successfully');
  });
  
  test('Channel without listener', () async {
    final runtime = McpFlowRuntime();
    
    print('Creating flow without channelReceive trigger...');
    final flow = {
      'version': '1.0.0',
      'channels': {
        'test_channel': {'type': 'queue'}
      },
      'processes': []
    };
    
    await runtime.loadFlow(flow);
    await runtime.start();
    await Future.delayed(Duration(milliseconds: 100));
    
    print('Attempting to stop runtime...');
    await runtime.stop().timeout(
      Duration(seconds: 2),
      onTimeout: () => throw Exception('Timeout without channelReceive trigger!')
    );
    
    print('✓ Runtime stopped successfully');
  });
}