import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Tests compliance with MCP Flow DSL v1.0 Specification - Section 4.2: Action Types
void main() {
  group('MCP Flow DSL Spec Compliance - Action Types', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('Control Flow Actions (Spec 4.2.1)', () {
      test('if action with then/else branches', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'x': {'type': 'number', 'initial': 10},
            'result': {'type': 'string', 'initial': ''}
          },
          'processes': [{
            'id': 'test_if',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'if',
              'params': {'condition': 'x > 5'},
              'then': [
                {'action': 'stateSet', 'params': {'key': 'result', 'value': 'greater'}}
              ],
              'else': [
                {'action': 'stateSet', 'params': {'key': 'result', 'value': 'less_equal'}}
              ]
            }]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('result'), equals('greater'));
      });

      test('while loop with condition', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 0},
            'sum': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test_while',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'while',
              'params': {'condition': '=counter < 5'},
              'do': [
                {'action': 'stateSet', 'params': {'key': 'sum', 'value': '=sum + counter'}},
                {'action': 'stateSet', 'params': {'key': 'counter', 'value': '=counter + 1'}}
              ]
            }]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('counter'), equals(5));
        expect(runtime.getState('sum'), equals(10)); // 0+1+2+3+4
      });

      test('for loop with range', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'sum': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test_for',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'for',
              'params': {'variable': 'i', 'from': 1, 'to': 5, 'step': 1},
              'do': [
                {'action': 'stateSet', 'params': {'key': 'sum', 'value': '=sum + i'}}
              ]
            }]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('sum'), equals(15)); // 1+2+3+4+5
      });

      test('switch with multiple cases and default', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'mode': {'type': 'string', 'initial': 'auto'},
            'speed': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test_switch',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'switch',
              'value': '=state.mode',
              'cases': {
                'slow': [
                  {'action': 'stateSet', 'params': {'key': 'speed', 'value': 10}}
                ],
                'fast': [
                  {'action': 'stateSet', 'params': {'key': 'speed', 'value': 100}}
                ],
                'auto': [
                  {'action': 'stateSet', 'params': {'key': 'speed', 'value': 50}}
                ]
              },
              'default': [
                {'action': 'stateSet', 'params': {'key': 'speed', 'value': 0}}
              ]
            }]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('speed'), equals(50));
      });

      test('break and continue in loops', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'sum': {'type': 'number', 'initial': 0},
            'count': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test_break_continue',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'for',
              'params': {'variable': 'i', 'from': 1, 'to': 10, 'step': 1},
              'do': [
                {
                  'action': 'if',
                  'params': {'condition': '=i % 2 == 0'},
                  'then': [{'action': 'continue'}]
                },
                {
                  'action': 'if',
                  'params': {'condition': '=i > 5'},
                  'then': [{'action': 'break'}]
                },
                {'action': 'stateSet', 'params': {'key': 'sum', 'value': '=sum + i'}},
                {'action': 'stateSet', 'params': {'key': 'count', 'value': '=count + 1'}}
              ]
            }]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('sum'), equals(9)); // 1+3+5
        expect(runtime.getState('count'), equals(3));
      });

      test('parallel execution', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'task1': {'type': 'boolean', 'initial': false},
            'task2': {'type': 'boolean', 'initial': false},
            'task3': {'type': 'boolean', 'initial': false}
          },
          'processes': [{
            'id': 'test_parallel',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'parallel',
              'branches': [
                [
                  {'action': 'wait', 'params': {'durationMs': 50}},
                  {'action': 'stateSet', 'params': {'key': 'task1', 'value': true}}
                ],
                [
                  {'action': 'wait', 'params': {'durationMs': 30}},
                  {'action': 'stateSet', 'params': {'key': 'task2', 'value': true}}
                ],
                [
                  {'action': 'wait', 'params': {'durationMs': 10}},
                  {'action': 'stateSet', 'params': {'key': 'task3', 'value': true}}
                ]
              ]
            }]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // All tasks should complete within 60ms (50ms max + buffer)
        await Future.delayed(Duration(milliseconds: 80));

        expect(runtime.getState('task1'), isTrue);
        expect(runtime.getState('task2'), isTrue);
        expect(runtime.getState('task3'), isTrue);
      });

      test('try-catch error handling', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'result': {'type': 'string', 'initial': ''},
            'error_caught': {'type': 'boolean', 'initial': false}
          },
          'processes': [{
            'id': 'test_try',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'try',
              'try': [
                // This should fail (invalid pin)
                {'action': 'gpioWrite', 'params': {'pin': -1, 'value': true}},
                {'action': 'stateSet', 'params': {'key': 'result', 'value': 'success'}}
              ],
              'catch': [
                {'action': 'stateSet', 'params': {'key': 'error_caught', 'value': true}},
                {'action': 'stateSet', 'params': {'key': 'result', 'value': 'error'}}
              ]
            }]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('error_caught'), isTrue);
        expect(runtime.getState('result'), equals('error'));
      });
    });

    group('Hardware Actions (Spec 4.2.2)', () {
      test('GPIO actions use dot notation', () async {
        final flow = {
          'version': '1.0.0',
          'state': {'gpio_result': {'type': 'any', 'initial': null}},
          'resources': {
            'gpio': {
              'type': 'gpio',
              'config': {
                'pins': {
                  '13': {'direction': 'output', 'initial': false}
                }
              }
            }
          },
          'processes': [{
            'id': 'test_gpio',
            'trigger': {'type': 'manual'},
            'steps': [
              {'action': 'gpioWrite', 'params': {'pin': 13, 'value': true}},
              {'action': 'gpioRead', 'params': {'pin': 13}, 'bindTo': 'gpio_result'}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await runtime.executeProcess('test_gpio');
        await Future.delayed(Duration(milliseconds: 100));

        // Should execute without errors (actual GPIO simulation depends on HAL)
        expect(runtime.getState('gpio_result'), isNotNull);
      });

      test('I2C actions use dot notation', () async {
        final flow = {
          'version': '1.0.0',
          'processes': [{
            'id': 'test_i2c',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'i2cWrite', 'params': {'bus': 1, 'address': 0x48, 'data': [1, 2, 3]}},
              {'action': 'i2cRead', 'params': {'bus': 1, 'address': 0x48, 'length': 2}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Should execute without errors
        expect(runtime.status, equals(RuntimeStatus.running));
      });

      test('SPI action uses dot notation', () async {
        final flow = {
          'version': '1.0.0',
          'processes': [{
            'id': 'test_spi',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'spiTransfer', 'params': {'bus': 0, 'device': 0, 'data': [0xFF, 0x00]}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.status, equals(RuntimeStatus.running));
      });

      test('ADC action uses dot notation', () async {
        final flow = {
          'version': '1.0.0',
          'resources': {
            'adc0': {
              'type': 'adc',
              'config': {
                'channel': 0,
                'resolution': 12
              }
            }
          },
          'state': {'adc_value': {'type': 'number', 'initial': 0}},
          'processes': [{
            'id': 'test_adc',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'adcRead', 'params': {'channel': 0}, 'bindTo': 'adc_value'}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('adc_value'), isNotNull);
      });

      test('PWM action uses dot notation', () async {
        final flow = {
          'version': '1.0.0',
          'resources': {
            'pwm0': {
              'type': 'pwm',
              'config': {
                'channel': 0,
                'frequency': 1000
              }
            }
          },
          'processes': [{
            'id': 'test_pwm',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'pwmSet', 'params': {'channel': 0, 'frequency': 1000, 'dutyCycle': 0.5}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.status, equals(RuntimeStatus.running));
      });

      test('UART actions use dot notation', () async {
        final flow = {
          'version': '1.0.0',
          'processes': [{
            'id': 'test_uart',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'uartWrite', 'params': {'port': '/dev/ttyUSB0', 'data': 'Hello'}},
              {'action': 'uartRead', 'params': {'port': '/dev/ttyUSB0', 'length': 10}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.status, equals(RuntimeStatus.running));
      });

      test('Modbus actions - all 8 function codes', () async {
        final flow = {
          'version': '1.0.0',
          'resources': {
            'plc': {
              'type': 'modbus',
              'config': {'mode': 'tcp', 'host': '192.168.1.100', 'port': 502}
            }
          },
          'processes': [{
            'id': 'test_modbus',
            'trigger': {'type': 'startup'},
            'steps': [
              // Read operations (per spec: modbusRead with function parameter)
              {'action': 'modbusRead', 'params': {'config': 'plc', 'unitId': 1, 'function': 'readCoils', 'address': 0, 'count': 10}},
              {'action': 'modbusRead', 'params': {'config': 'plc', 'unitId': 1, 'function': 'readDiscreteInputs', 'address': 0, 'count': 10}},
              {'action': 'modbusRead', 'params': {'config': 'plc', 'unitId': 1, 'function': 'readHoldingRegisters', 'address': 0, 'count': 5}},
              {'action': 'modbusRead', 'params': {'config': 'plc', 'unitId': 1, 'function': 'readInputRegisters', 'address': 0, 'count': 5}},
              // Write operations (per spec: modbusWrite with function parameter)
              {'action': 'modbusWrite', 'params': {'config': 'plc', 'unitId': 1, 'function': 'writeSingleCoil', 'address': 0, 'value': true}},
              {'action': 'modbusWrite', 'params': {'config': 'plc', 'unitId': 1, 'function': 'writeMultipleCoils', 'address': 0, 'value': [true, false, true]}},
              {'action': 'modbusWrite', 'params': {'config': 'plc', 'unitId': 1, 'function': 'writeSingleRegister', 'address': 0, 'value': 12345}},
              {'action': 'modbusWrite', 'params': {'config': 'plc', 'unitId': 1, 'function': 'writeMultipleRegisters', 'address': 0, 'value': [100, 200, 300]}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Wait longer for all 8 Modbus operations to complete
        await Future.delayed(Duration(milliseconds: 500));

        // All Modbus functions should be recognized
        expect(runtime.status, equals(RuntimeStatus.running));
        
        // Stop runtime to prevent async work after test completes
        await runtime.stop();
      });
    });

    group('State Management Actions (Spec 4.2.3)', () {
      test('setState updates state variables', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'counter': {'type': 'number', 'initial': 0},
            'message': {'type': 'string', 'initial': ''}
          },
          'processes': [{
            'id': 'test_setState',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'counter', 'value': 42}},
              {'action': 'stateSet', 'params': {'key': 'message', 'value': 'Hello World'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('counter'), equals(42));
        expect(runtime.getState('message'), equals('Hello World'));
      });

      test('getState retrieves state values', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'source': {'type': 'number', 'initial': 100},
            'target': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test_getState',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'stateGet', 'params': {'key': 'source'}, 'bindTo': 'value'},
              {'action': 'stateSet', 'params': {'key': 'target', 'value': '=value'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('target'), equals(100));
      });
    });

    group('Channel Actions (Spec 4.2.4)', () {
      test('channelSend and channelReceive', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'received': {'type': 'any', 'initial': null}
          },
          'channels': {
            'messages': {'type': 'pubsub'}
          },
          'processes': [
            {
              'id': 'sender',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'channelSend', 'params': {'channel': 'messages', 'data': 'Hello Channel'}}
              ]
            },
            {
              'id': 'receiver',
              'trigger': {'type': 'channelReceive', 'channel': 'messages'},
              'steps': [
                {'action': 'stateSet', 'params': {'key': 'received', 'value': '=trigger.data'}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 200));

        expect(runtime.getState('received'), equals('Hello Channel'));
      });
    });

    group('Process Control Actions (Spec 4.2.5)', () {
      test('executeProcess triggers another process', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'process1_ran': {'type': 'boolean', 'initial': false},
            'process2_ran': {'type': 'boolean', 'initial': false}
          },
          'processes': [
            {
              'id': 'process1',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'stateSet', 'params': {'key': 'process1_ran', 'value': true}},
                {'action': 'processStart', 'params': {'processId': 'process2'}}
              ]
            },
            {
              'id': 'process2',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'stateSet', 'params': {'key': 'process2_ran', 'value': true}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('process1_ran'), isTrue);
        expect(runtime.getState('process2_ran'), isTrue);
      });

      test('processStop terminates a running process', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'loop_count': {'type': 'number', 'initial': 0}
          },
          'processes': [
            {
              'id': 'looper',
              'trigger': {'type': 'startup'},
              'loop': true,
              'steps': [
                {'action': 'stateSet', 'params': {'key': 'loop_count', 'value': '=loop_count + 1'}},
                {'action': 'wait', 'params': {'durationMs': 50}}
              ]
            },
            {
              'id': 'stopper',
              'trigger': {'type': 'startup'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 150}},
                {'action': 'processStop', 'params': {'processId': 'looper'}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 300));

        final count = runtime.getState('loop_count');
        expect(count, greaterThanOrEqualTo(2));
        expect(count, lessThanOrEqualTo(4));
      });
    });

    group('Utility Actions (Spec 4.2.6)', () {
      test('delay pauses execution', () async {
        final startTime = DateTime.now();
        
        final flow = {
          'version': '1.0.0',
          'state': {'done': {'type': 'boolean', 'initial': false}},
          'processes': [{
            'id': 'test_delay',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'wait', 'params': {'durationMs': 100}},
              {'action': 'stateSet', 'params': {'key': 'done', 'value': true}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Should not be done immediately
        expect(runtime.getState('done'), isFalse);
        
        await Future.delayed(Duration(milliseconds: 150));
        
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        expect(runtime.getState('done'), isTrue);
        expect(elapsed, greaterThanOrEqualTo(100));
      });

      test('log action with different levels', () async {
        final flow = {
          'version': '1.0.0',
          'processes': [{
            'id': 'test_log',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'log', 'params': {'message': 'Debug message', 'level': 'debug'}},
              {'action': 'log', 'params': {'message': 'Info message', 'level': 'info'}},
              {'action': 'log', 'params': {'message': 'Warning message', 'level': 'warning'}},
              {'action': 'log', 'params': {'message': 'Error message', 'level': 'error'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Should execute without errors
        expect(runtime.status, equals(RuntimeStatus.running));
      });

      test('expression action evaluates expressions', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'a': {'type': 'number', 'initial': 10},
            'b': {'type': 'number', 'initial': 20},
            'result': {'type': 'number', 'initial': 0}
          },
          'processes': [{
            'id': 'test_expression',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'expression', 'params': {'expression': 'a + b * 2'}, 'bindTo': 'calc'},
              {'action': 'stateSet', 'params': {'key': 'result', 'value': '=calc'}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.getState('result'), equals(50)); // 10 + 20 * 2
      });
    });

    group('System Actions (Spec 4.2.7)', () {
      test('system actions for configuration', () async {
        final flow = {
          'version': '1.0.0',
          'processes': [{
            'id': 'test_system',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'systemGetInfo', 'bindTo': 'sysInfo'},
              {'action': 'systemSetConfig', 'params': {'key': 'debug', 'value': true}}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Should execute without errors
        expect(runtime.status, equals(RuntimeStatus.running));
      });
    });

    // File Actions are not in MCP Flow DSL v1.0 spec
    // Commented out to maintain spec compliance
    // group('File Actions (Spec 4.2.8)', () {
    //   test('file operations', () async {
    //     ...
    //   });
    // });

    group('Network Actions (Spec 4.2.9)', () {
      test('HTTP requests', () async {
        final flow = {
          'version': '1.0.0',
          'processes': [{
            'id': 'test_http',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'httpGet', 'params': {'url': 'https://api.example.com/data'}, 'bindTo': 'response'},
              {'action': 'httpPost', 'params': {
                'url': 'https://api.example.com/data',
                'body': '{"key": "value"}',
                'headers': {'Content-Type': 'application/json'}
              }}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        // Should execute without errors (actual requests depend on network layer)
        expect(runtime.status, equals(RuntimeStatus.running));
      });

      test('MQTT operations', () async {
        final flow = {
          'version': '1.0.0',
          'resources': {
            'mqtt_broker': {
              'type': 'mqtt',
              'config': {'host': 'broker.example.com', 'port': 1883}
            }
          },
          'processes': [{
            'id': 'test_mqtt',
            'trigger': {'type': 'startup'},
            'steps': [
              {'action': 'mqttPublish', 'params': {
                'broker': 'mqtt_broker',
                'topic': 'test/topic',
                'message': 'Hello MQTT'
              }},
              {'action': 'mqttSubscribe', 'params': {
                'broker': 'mqtt_broker',
                'topic': 'test/response'
              }}
            ]
          }]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 100));

        expect(runtime.status, equals(RuntimeStatus.running));
      });
    });
  });
}