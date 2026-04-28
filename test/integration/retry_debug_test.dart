import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  test('debug retry mechanism', () async {
    final runtime = McpFlowRuntime();
    
    final flow = {
      'version': '1.0.0',
      'state': {
        'attempt_count': {'type': 'number', 'initial': 0},
        'error_messages': {'type': 'array', 'initial': []},
      },
      'processes': [{
        'id': 'test_retry',
        'trigger': {'type': 'startup'},
        'steps': [{
          'action': 'try',
          'try': [{
            'action': 'stateSet',
            'params': {
              'key': 'attempt_count',
              'value': '=attempt_count + 1'
            }
          }, {
            // This should always fail - intentionally using unknown action
            'action': 'unknownAction',
            'params': {
              'test': 'value'
            },
            'retry': {
              'count': 2,
              'delayMs': 50
            }
          }],
          'catch': [{
            'action': 'stateSet',
            'params': {
              'key': 'error_messages',
              'value': '=append(error_messages, catchError.message)'
            }
          }]
        }]
      }]
    };

    await runtime.loadFlow(flow);
    await runtime.start();
    await Future.delayed(Duration(milliseconds: 500));
    
    print('Attempt count: ${runtime.getState('attempt_count')}');
    print('Error messages: ${runtime.getState('error_messages')}');
    
    // Should have tried once (setState executes, then unknownAction fails with retries)
    expect(runtime.getState('attempt_count'), equals(1));
    
    final errors = runtime.getState('error_messages') as List;
    expect(errors.length, equals(1));
    expect(errors[0], contains('Unknown action type: unknownAction'));
    
    await runtime.stop();
  });
}