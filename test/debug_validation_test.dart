import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';

void main() {
  test('Debug channelPublish validation - simple', () async {
    final runtime = McpFlowRuntime();
    
    // Simplest possible channelPublish test
    final flow = {
      'version': '1.0.0',
      'processes': [
        {
          'id': 'test',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'channelPublish',
              'params': {
                'channel': 'test',
                'data': 'hello'
              }
            }
          ]
        }
      ]
    };
    
    // This should work
    await runtime.loadFlow(flow);
    expect(runtime.status, RuntimeStatus.created);
  });
  
  test('Debug channelPublish validation - original', () async {
    final flow = {
      'version': '1.0.0',
      'state': {
        'received1': {'type': 'any', 'initial': null},
        'received2': {'type': 'any', 'initial': null},
      },
      'channels': {
        'events': {
          'type': 'pubsub',
          'capacity': 100
        }
      },
      'processes': [
        {
          'id': 'publisher',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'channelPublish',
              'params': {
                'channel': 'events',
                'data': {'event': 'test', 'value': 123},
                'broadcast': true
              }
            }
          ]
        },
        {
          'id': 'subscriber1',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'channelReceive',
              'params': {'channel': 'events', 'timeout': 100},
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
              'params': {'channel': 'events', 'timeout': 100},
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

    // Try to load and see what errors we get
    final runtime = McpFlowRuntime();
    try {
      await runtime.loadFlow(flow);
      expect(runtime.status, RuntimeStatus.created);
    } catch (e) {
      // Check the error details
      if (e is FlowValidationError) {
        for (final error in e.errors) {
          fail('Validation error detail: $error');
        }
      }
      fail('Flow validation failed: $e');
    }
  });
  
  test('Debug channelReceive with duplicate bindTo', () async {
    final runtime = McpFlowRuntime();
    
    // Test if duplicate bindTo in different processes causes issues
    final flow = {
      'version': '1.0.0',
      'processes': [
        {
          'id': 'proc1',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'channelReceive',
              'params': {'channel': 'test'},
              'bindTo': 'msg'  // Same variable name
            }
          ]
        },
        {
          'id': 'proc2',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'channelReceive',
              'params': {'channel': 'test'},
              'bindTo': 'msg'  // Same variable name - might be the issue
            }
          ]
        }
      ]
    };
    
    try {
      await runtime.loadFlow(flow);
      expect(runtime.status, RuntimeStatus.created);
    } catch (e) {
      // Check if this is the issue
      expect(e.toString(), contains('validation'), reason: 'Duplicate bindTo might be the issue');
    }
  });
}