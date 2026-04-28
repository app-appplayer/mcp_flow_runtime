import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  test('Debug channelPublish with proper sequencing', () async {
    final runtime = McpFlowRuntime();
    
    final flow = {
      'version': '1.0.0',
      'channels': {
        'events': {'type': 'pubsub', 'capacity': 10}  // Use pubsub for broadcast
      },
      'state': {
        'received1': {'type': 'any', 'initial': null},
        'received2': {'type': 'any', 'initial': null},
        'published': {'type': 'boolean', 'initial': false},
      },
      'processes': [
        {
          'id': 'publisher',
          'trigger': {'type': 'startup'},
          'steps': [
            // Add a small delay to ensure receivers are ready
            {
              'action': 'wait',
              'params': {'durationMs': 50}
            },
            {
              'action': 'channelPublish',
              'params': {
                'channel': 'events',
                'data': {'event': 'test', 'value': 123},
                'broadcast': true
              }
            },
            {
              'action': 'stateSet',
              'params': {'key': 'published', 'value': true}
            }
          ]
        },
        {
          'id': 'subscriber1',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'channelReceive',
              'params': {'channel': 'events', 'timeout': 200},  // Increase timeout
              'bindTo': 'msg1'
            },
            {
              'action': 'stateSet',
              'params': {'key': 'received1', 'value': '{{msg1}}'}
            }
          ]
        },
        {
          'id': 'subscriber2',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'channelReceive',
              'params': {'channel': 'events', 'timeout': 200},  // Increase timeout
              'bindTo': 'msg2'
            },
            {
              'action': 'stateSet',
              'params': {'key': 'received2', 'value': '{{msg2}}'}
            }
          ]
        }
      ]
    };
    
    await runtime.loadFlow(flow);
    await runtime.start();
    
    // Wait for processes to complete
    await Future.delayed(Duration(milliseconds: 300));
    
    // Check that publisher published
    expect(runtime.getState('published'), isTrue);
    
    // Check that both subscribers received the broadcast
    final received1 = runtime.getState('received1');
    final received2 = runtime.getState('received2');
    
    print('Published: ${runtime.getState("published")}');
    print('Received1: $received1');
    print('Received2: $received2');
    
    expect(received1, isNotNull, reason: 'Subscriber1 should have received the message');
    expect(received2, isNotNull, reason: 'Subscriber2 should have received the message');
    
    // Check the data structure
    if (received1 is Map) {
      expect(received1['data'], equals({'event': 'test', 'value': 123}));
      expect(received1['broadcast'], isTrue);
    }
    
    if (received2 is Map) {
      expect(received2['data'], equals({'event': 'test', 'value': 123}));
      expect(received2['broadcast'], isTrue);
    }
  });
}