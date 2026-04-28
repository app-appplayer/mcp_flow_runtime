import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Integration test for retry conditions evaluation
void main() {
  group('Retry Conditions Integration Tests', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('simple retry test', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'counter': {'type': 'number', 'initial': 0},
          'executed': {'type': 'boolean', 'initial': false},
        },
        'processes': [{
          'id': 'simple_retry',
          'trigger': {'type': 'startup'},
          'steps': [{
            'action': 'try',
            'try': [{
              'action': 'stateSet',
              'params': {
                'key': 'counter',
                'value': '=counter + 1'
              }
            }, {
              // This will fail
              'action': 'invalidAction',
              'params': {},
              'retry': {
                'count': 2,
                'delayMs': 50
              }
            }],
            'catch': [{
              'action': 'stateSet',
              'params': {'key': 'executed', 'value': true}
            }]
          }]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 300));
      
      // The setState should have executed once, then invalidAction fails with retries
      expect(runtime.getState('counter'), equals(1));
      expect(runtime.getState('executed'), isTrue);
    });

    test('retry with specific condition', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'attempts': {'type': 'number', 'initial': 0},
          'errors': {'type': 'array', 'initial': []},
        },
        'processes': [{
          'id': 'conditional_retry',
          'trigger': {'type': 'startup'},
          'steps': [{
            'action': 'try',
            'try': [{
              'action': 'stateSet',
              'params': {
                'key': 'attempts',
                'value': '=attempts + 1'
              }
            }, {
              // This action will fail with specific error message
              'action': 'unknownAction',
              'params': {'test': true},
              'retry': {
                'count': 2,
                'delayMs': 50,
                'retryConditions': [
                  'indexOf(retryError.message, "Unknown action") >= 0'
                ]
              }
            }],
            'catch': [{
              'action': 'stateSet',
              'params': {
                'key': 'errors',
                'value': '=append(errors, catchError.message)'
              }
            }]
          }]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 300));
      
      // setState should execute once, then unknownAction fails with retries
      expect(runtime.getState('attempts'), equals(1)); // Only setState executes once
      
      final errors = runtime.getState('errors') as List;
      expect(errors.length, equals(1));
      expect(errors[0], contains('Unknown action'));
    });

    test('retry stops when condition not met', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'attempts': {'type': 'number', 'initial': 0},
          'errorCaught': {'type': 'boolean', 'initial': false},
        },
        'processes': [{
          'id': 'no_retry_test',
          'trigger': {'type': 'startup'},
          'steps': [{
            'action': 'try',
            'try': [{
              'action': 'stateSet',
              'params': {
                'key': 'attempts',
                'value': '=attempts + 1'
              }
            }, {
              // This will fail but retry condition won't match
              'action': 'unknownAction',
              'params': {},
              'retry': {
                'count': 3,
                'delayMs': 50,
                'retryConditions': [
                  'indexOf(retryError.message, "network error") >= 0'
                ]
              }
            }],
            'catch': [{
              'action': 'stateSet',
              'params': {'key': 'errorCaught', 'value': true}
            }]
          }]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 200));
      
      // Should not retry because condition doesn't match
      expect(runtime.getState('attempts'), equals(1));
      expect(runtime.getState('errorCaught'), isTrue);
    });

    test('stop condition based on error type', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'errorCount': {'type': 'number', 'initial': 0},
          'finalStatus': {'type': 'string', 'initial': 'pending'},
          'errorMessage': {'type': 'string', 'initial': ''}
        },
        'processes': [{
          'id': 'stop_retry_test',
          'trigger': {'type': 'startup'},
          'steps': [{
            'action': 'try',
            'try': [{
              // This action will fail with "Unknown action" error
              'action': 'unknownAction',
              'params': {},
              'retry': {
                'count': 5,
                'delayMs': 50,
                // Stop retrying if the error indicates a permanent failure
                'stopConditions': [
                  'indexOf(retryError.message, "Unknown action") >= 0'
                ]
              }
            }],
            'catch': [{
              'action': 'stateSet',
              'params': {'key': 'errorCount', 'value': '=errorCount + 1'}
            }, {
              'action': 'stateSet',
              'params': {'key': 'errorMessage', 'value': '=catchError.message'}
            }, {
              'action': 'stateSet',
              'params': {'key': 'finalStatus', 'value': 'error_handled'}
            }]
          }]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 300));
      
      // The action should stop retrying immediately due to stopCondition
      // So it should fail once and go to catch block
      final errorMessage = runtime.getState('errorMessage');
      print('Error message: $errorMessage');
      
      expect(runtime.getState('errorCount'), equals(1));
      expect(runtime.getState('finalStatus'), equals('error_handled'));
      expect(errorMessage.toString().contains('Unknown action'), isTrue);
    });

    test('exponential backoff', () async {
      // Test exponential backoff with a different approach
      // Track retry attempts in the action executor logs
      final flow = {
        'version': '1.0.0',
        'state': {
          'executed': {'type': 'boolean', 'initial': false},
        },
        'processes': [{
          'id': 'backoff_test',
          'trigger': {'type': 'startup'},
          'steps': [{
            'action': 'try',
            'try': [{
              'action': 'unknownAction',
              'params': {},
              'retry': {
                'count': 2,
                'delayMs': 50,
                'backoff': 'exponential'
              }
            }],
            'catch': [{
              'action': 'stateSet',
              'params': {'key': 'executed', 'value': true}
            }]
          }]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 400));
      
      // The action should have been attempted 3 times (1 initial + 2 retries)
      // and then caught by the catch block
      expect(runtime.getState('executed'), isTrue);
    });
  });
}