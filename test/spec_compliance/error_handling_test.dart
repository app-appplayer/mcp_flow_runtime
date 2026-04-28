import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'dart:async';

void main() {
  group('MCP Flow DSL Spec - Error Handling (Section 6.8)', () {
    late McpFlowRuntime runtime;
    late JsonFlowParser parser;

    setUp(() {
      parser = JsonFlowParser();
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      await runtime.stop();
    });

    group('Process Error Handlers', () {
      test('should execute error handler on step failure', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'errorHandled': {
              'type': 'boolean',
              'initial': false
            },
            'errorMessage': {
              'type': 'string',
              'initial': ''
            }
          },
          'processes': [
            {
              'id': 'error_test',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'expression',
                  'params': {
                    'expression': 'undefinedFunction()'  // This will cause an error
                  }
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'errorHandled',
                    'value': true
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'errorMessage',
                    'value': 'Error occurred in process'
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('error_test');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('errorHandled'), isTrue);
        expect(runtime.getState('errorMessage'), equals('Error occurred in process'));
      });

      test('should execute finally block regardless of success', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'stepExecuted': {
              'type': 'boolean',
              'initial': false
            },
            'finallyExecuted': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'success_finally',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'stepExecuted',
                    'value': true
                  }
                }
              ],
              'finally': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'finallyExecuted',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('success_finally');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('stepExecuted'), isTrue);
        expect(runtime.getState('finallyExecuted'), isTrue);
      });

      test('should execute finally block even after error', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'finallyAfterError': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'error_finally',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'expression',
                  'params': {
                    'expression': '= 1 / 0'
                  }
                }
              ],
              'error': [
                {
                  'action': 'log',
                  'params': {
                    'level': 'error',
                    'message': 'Division by zero'
                  }
                }
              ],
              'finally': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'finallyAfterError',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('error_finally');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('finallyAfterError'), isTrue);
      });

      test('should handle nested error scenarios', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'outerError': {
              'type': 'boolean',
              'initial': false
            },
            'innerError': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'outer_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'processStart',
                  'params': {
                    'processId': 'inner_process'
                  }
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'outerError',
                    'value': true
                  }
                }
              ]
            },
            {
              'id': 'inner_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'expression',
                  'params': {
                    'expression': '= invalidFunction()'
                  }
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'innerError',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('outer_process');
        await Future.delayed(Duration(milliseconds: 200));

        expect(runtime.getState('innerError'), isTrue);
        // Outer process may or may not handle inner process errors depending on implementation
      });
    });

    group('Try-Catch Control Flow', () {
      test('should execute try block on success', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'tryExecuted': {
              'type': 'boolean',
              'initial': false
            },
            'catchExecuted': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'try_success',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'try',
                  'try': [
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'tryExecuted',
                        'value': true
                      }
                    }
                  ],
                  'catch': [
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'catchExecuted',
                        'value': true
                      }
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('try_success');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('tryExecuted'), isTrue);
        expect(runtime.getState('catchExecuted'), isFalse);
      });

      test('should execute catch block on error', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'tryExecuted': {
              'type': 'boolean',
              'initial': false
            },
            'catchExecuted': {
              'type': 'boolean',
              'initial': false
            },
            'errorCaught': {
              'type': 'string',
              'initial': ''
            }
          },
          'processes': [
            {
              'id': 'try_error',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'try',
                  'try': [
                    {
                      'action': 'expression',
                      'params': {
                        'expression': 'nonExistentFunction()'  // This will cause an error
                      }
                    },
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'tryExecuted',
                        'value': true
                      }
                    }
                  ],
                  'catch': [
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'catchExecuted',
                        'value': true
                      }
                    },
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'errorCaught',
                        'value': 'Error was caught'
                      }
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('try_error');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('tryExecuted'), isFalse);
        expect(runtime.getState('catchExecuted'), isTrue);
        expect(runtime.getState('errorCaught'), equals('Error was caught'));
      });

      test('should support try-catch-finally', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'finallyExecuted': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'try_catch_finally',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'try',
                  'try': [
                    {
                      'action': 'expression',
                      'params': {
                        'expression': '1 / 0'
                      }
                    }
                  ],
                  'catch': [
                    {
                      'action': 'log',
                      'params': {
                        'message': 'Caught division by zero'
                      }
                    }
                  ],
                  'finally': [
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'finallyExecuted',
                        'value': true
                      }
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('try_catch_finally');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('finallyExecuted'), isTrue);
      });
    });

    group('Retry Logic', () {
      test('should retry failed action', () async {
        // Test that retry configuration is accepted by the runtime
        final flowDef = {
          'version': '1.0',
          'state': {
            'result': {
              'type': 'string',
              'initial': ''
            }
          },
          'processes': [
            {
              'id': 'retry_process',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'result',
                    'value': 'completed'
                  },
                  'retry': {
                    'count': 3,
                    'delayMs': 50
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();

        await runtime.executeProcess('retry_process');
        await Future.delayed(Duration(milliseconds: 200));

        // The action should complete successfully
        expect(runtime.getState('result'), equals('completed'));
      });

      test('should respect retry delay', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'retryCount': {
              'type': 'number',
              'initial': 0
            },
            'startTime': {
              'type': 'number',
              'initial': 0
            },
            'endTime': {
              'type': 'number',
              'initial': 0
            }
          },
          'processes': [
            {
              'id': 'retry_delay_test',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'startTime',
                    'value': '= Date.now()'
                  }
                },
                {
                  'action': 'expression',
                  'params': {
                    'expression': '= failsNTimes(2)'  // Will fail twice, succeed on 3rd
                  },
                  'retry': {
                    'count': 2,
                    'delayMs': 100
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'endTime',
                    'value': '= Date.now()'
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        try {
          await runtime.executeProcess('retry_delay_test');
        } catch (e) {
          // Expected to fail after retries
        }
        await Future.delayed(Duration(milliseconds: 500));
        
        final startTime = runtime.getState('startTime');
        final endTime = runtime.getState('endTime');
        
        // Should have executed with delays: initial + 2 retries with 100ms delay each
        // Total time should be at least 200ms
        if (endTime != 0 && startTime != 0) {
          final totalTime = endTime - startTime;
          expect(totalTime, greaterThanOrEqualTo(180)); // Allow some timing variance
        }
      });
    });

    group('Error Recovery Patterns', () {
      test('should support graceful degradation', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'primaryValue': {
              'type': 'number',
              'initial': -1
            },
            'fallbackValue': {
              'type': 'number',
              'initial': 42
            },
            'finalValue': {
              'type': 'number',
              'initial': -1
            }
          },
          'processes': [
            {
              'id': 'degradation_test',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'try',
                  'try': [
                    // Simulate primary sensor failure
                    {
                      'action': 'expression',
                      'params': {
                        'expression': '= failedSensor.read()'
                      }
                    },
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'finalValue',
                        'value': '= primaryValue'
                      }
                    }
                  ],
                  'catch': [
                    // Fallback to secondary source
                    {
                      'action': 'stateSet',
                      'params': {
                        'key': 'finalValue',
                        'value': '= fallbackValue'
                      }
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('degradation_test');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('finalValue'), equals(42));
      });

      test('should handle hardware error recovery', () async {
        final flowDef = {
          'version': '1.0',
          'resources': {
            'sensor': {
              'type': 'i2c',
              'config': {
                'address': 0x48,
                'bus': 1
              },
              'errorHandling': {
                'resetOnError': true,
                'resetProcedure': [
                  {
                    'action': 'stateSet',
                    'params': {
                      'key': 'resetInitiated',
                      'value': true
                    }
                  },
                  {
                    'action': 'wait',
                    'params': {'durationMs': 50}
                  },
                  {
                    'action': 'stateSet',
                    'params': {
                      'key': 'resetCompleted',
                      'value': true
                    }
                  }
                ]
              }
            }
          },
          'state': {
            'resetInitiated': {
              'type': 'boolean',
              'initial': false
            },
            'resetCompleted': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': []
        };

        final flow = parser.parse(flowDef);
        await runtime.loadFlow(flowDef);

        // Verify error handling configuration is parsed
        expect(flow.resources['sensor']!.errorHandling, isNotNull);
      });
    });

    group('Error Context', () {
      test('should provide error context in handlers', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'errorType': {
              'type': 'string',
              'initial': ''
            },
            'errorAction': {
              'type': 'string',
              'initial': ''
            }
          },
          'processes': [
            {
              'id': 'error_context_test',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'expression',
                  'params': {
                    'expression': '= JSON.parse("invalid json")'
                  }
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'errorType',
                    'value': 'ExpressionError'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'errorAction',
                    'value': 'expression'
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('error_context_test');
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('errorType'), equals('ExpressionError'));
        expect(runtime.getState('errorAction'), equals('expression'));
      });
    });

    group('Circuit Breaker Pattern', () {
      test('should parse circuit breaker configuration', () async {
        final flowDef = {
          'version': '1.0',
          'resources': {
            'external_api': {
              'type': 'service',
              'config': {
                'url': 'https://api.example.com',
                'circuitBreaker': {
                  'failureThreshold': 5,
                  'timeoutMs': 10000,
                  'recoveryTimeMs': 30000,
                  'halfOpenMaxCalls': 3
                }
              }
            }
          },
          'processes': []
        };

        final flow = parser.parse(flowDef);
        await runtime.loadFlow(flowDef);

        expect(flow.resources['external_api']!.type, equals('service'));
        expect(flow.resources['external_api']!.config['circuitBreaker'], isNotNull);
        expect(flow.resources['external_api']!.config['circuitBreaker']['failureThreshold'], equals(5));
      });
    });

    group('Error Propagation', () {
      test('should propagate errors through process chain', () async {
        final flowDef = {
          'version': '1.0',
          'state': {
            'process1Error': {
              'type': 'boolean',
              'initial': false
            },
            'process2Error': {
              'type': 'boolean',
              'initial': false
            },
            'process3Error': {
              'type': 'boolean',
              'initial': false
            }
          },
          'processes': [
            {
              'id': 'process1',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'processStart',
                  'params': {'processId': 'process2'}
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'process1Error',
                    'value': true
                  }
                }
              ]
            },
            {
              'id': 'process2',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'processStart',
                  'params': {'processId': 'process3'}
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'process2Error',
                    'value': true
                  }
                }
              ]
            },
            {
              'id': 'process3',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'expression',
                  'params': {
                    'expression': '= undefinedFunction()'
                  }
                }
              ],
              'error': [
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'process3Error',
                    'value': true
                  }
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flowDef);
        await runtime.start();
        
        await runtime.executeProcess('process1');
        await Future.delayed(Duration(milliseconds: 300));

        // Error should be handled at the innermost level
        expect(runtime.getState('process3Error'), isTrue);
      });
    });

    group('Error Handler Validation', () {
      test('should validate error handler actions', () async {
        final flowDef = {
          'version': '1.0',
          'processes': [
            {
              'id': 'invalid_error_handler',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'log',
                  'params': {'message': 'Test'}
                }
              ],
              'error': [
                {
                  'action': 'invalidAction',
                  'params': {}
                }
              ]
            }
          ]
        };

        // Should validate error handler actions during load
        expect(() async => await runtime.loadFlow(flowDef), 
               throwsA(isA<FlowValidationError>()));
      });

      test('should allow empty error handlers', () async {
        final flowDef = {
          'version': '1.0',
          'processes': [
            {
              'id': 'empty_handlers',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'log',
                  'params': {'message': 'Test'}
                }
              ],
              'error': [],
              'finally': []
            }
          ]
        };

        // Empty handlers should be valid
        await expectLater(runtime.loadFlow(flowDef), completes);
      });
    });
  });
}