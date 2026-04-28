import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Tests for MCP Flow DSL v1.0 Specification - Section 6.6: Communication Actions
void main() {
  group('MCP Flow DSL Spec - MCP Communication Actions', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('mcpNotify Action', () {
      test('mcpNotify sends standard notification', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'temperature': {'type': 'number', 'initial': 25.5},
            'notification_sent': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'temperature_monitor',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'mcpNotify',
                  'params': {
                    'resource': 'sensor://temperature',
                    'level': 'info'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'notification_sent', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('notification_sent'), isTrue);
      });

      test('mcpNotify with data extension', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'temperature': {'type': 'number', 'initial': 32.5},
            'humidity': {'type': 'number', 'initial': 65},
            'alert_sent': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'sensor_reporter',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'mcpNotify',
                  'params': {
                    'resource': 'sensor://environment',
                    'level': 'warn',
                    'includeData': true,
                    'data': {
                      'temperature': '=state.temperature',
                      'humidity': '=state.humidity',
                      'timestamp': '=Date.now()',
                      'alert': 'High temperature detected'
                    }
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'alert_sent', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('alert_sent'), isTrue);
      });

      test('mcpNotify with different log levels', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'debug_sent': {'type': 'boolean', 'initial': false},
            'info_sent': {'type': 'boolean', 'initial': false},
            'warn_sent': {'type': 'boolean', 'initial': false},
            'error_sent': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'level_tester',
              'trigger': {'type': 'startup'},
              'steps': [
                // Debug level
                {
                  'action': 'mcpNotify',
                  'params': {
                    'resource': 'debug://test',
                    'level': 'debug'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'debug_sent', 'value': true}
                },
                // Info level
                {
                  'action': 'mcpNotify',
                  'params': {
                    'resource': 'info://test',
                    'level': 'info'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'info_sent', 'value': true}
                },
                // Warn level
                {
                  'action': 'mcpNotify',
                  'params': {
                    'resource': 'warn://test',
                    'level': 'warn'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'warn_sent', 'value': true}
                },
                // Error level
                {
                  'action': 'mcpNotify',
                  'params': {
                    'resource': 'error://test',
                    'level': 'error'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'error_sent', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('debug_sent'), isTrue);
        expect(runtime.getState('info_sent'), isTrue);
        expect(runtime.getState('warn_sent'), isTrue);
        expect(runtime.getState('error_sent'), isTrue);
      });

      test('mcpNotify in error handler', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'error_notified': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'failing_process',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'try',
                  'try': [
                    // This will fail (or use a different action that will fail)
                    {
                      'action': 'expression',
                      'params': {
                        'expression': 'error("Hardware error simulation")'
                      },
                      'bindTo': 'data'
                    }
                  ],
                  'catch': [
                    {
                      'action': 'mcpNotify',
                      'params': {
                        'resource': 'error://hardware',
                        'level': 'error',
                        'includeData': true,
                        'data': {
                          'error': '=catchError.message',
                          'type': '=catchError.type',
                          'component': 'i2c_sensor'
                        }
                      }
                    },
                    {
                      'action': 'stateSet',
                      'params': {'key': 'error_notified', 'value': true}
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('error_notified'), isTrue);
      });
    });

    group('mcpUpdateResource Action', () {
      test('mcpUpdateResource updates resource contents', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'sensor_value': {'type': 'number', 'initial': 0},
            'resource_updated': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'resource_updater',
              'trigger': {'type': 'startup'},
              'steps': [
                // Read sensor value
                {
                  'action': 'stateSet',
                  'params': {'key': 'sensor_value', 'value': 42}
                },
                // Update MCP resource
                {
                  'action': 'mcpUpdateResource',
                  'params': {
                    'uri': 'sensor://temperature/current',
                    'contents': {
                      'value': '=state.sensor_value',
                      'unit': 'celsius',
                      'timestamp': '=Date.now()'
                    }
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'resource_updated', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('resource_updated'), isTrue);
        expect(runtime.getState('sensor_value'), equals(42));
      });

      test('mcpUpdateResource with array data', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'buffer': {'type': 'array', 'initial': []},
            'buffer_published': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'buffer_publisher',
              'trigger': {'type': 'startup'},
              'steps': [
                // Collect data
                {
                  'action': 'for',
                  'params': {
                    'variable': 'i',
                    'from': 0,
                    'to': 5,
                    'step': 1
                  },
                  'do': [
                    {
                      'action': 'stateUpdate',
                      'params': {
                        'key': 'buffer',
                        'operation': 'append',
                        'value': '={index: i, value: i * 10}'
                      }
                    }
                  ]
                },
                // Publish buffer as resource
                {
                  'action': 'mcpUpdateResource',
                  'params': {
                    'uri': 'data://buffer',
                    'contents': '=state.buffer'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'buffer_published', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        expect(runtime.getState('buffer_published'), isTrue);
        final buffer = runtime.getState('buffer') as List;
        expect(buffer.length, equals(6)); // 0, 1, 2, 3, 4, 5 (inclusive)
      });

      test('mcpUpdateResource with complex nested data', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'system_status': {'type': 'object', 'initial': {}},
            'status_published': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'status_reporter',
              'trigger': {'type': 'startup'},
              'steps': [
                // Build complex status object
                {
                  'action': 'stateSet',
                  'params': {
                    'key': 'system_status',
                    'value': {
                      'hardware': {
                        'gpio': {
                          'pins': [
                            {'pin': 1, 'mode': 'output', 'value': 1},
                            {'pin': 2, 'mode': 'input', 'value': 0}
                          ],
                          'status': 'operational'
                        },
                        'i2c': {
                          'devices': ['0x48', '0x49', '0x4A'],
                          'bus': 1,
                          'speed': 100000
                        }
                      },
                      'processes': {
                        'active': 3,
                        'idle': 2,
                        'error': 0
                      },
                      'memory': {
                        'used': 1024,
                        'free': 3072,
                        'total': 4096
                      },
                      'timestamp': '=Date.now()'
                    }
                  }
                },
                // Update resource with complex data
                {
                  'action': 'mcpUpdateResource',
                  'params': {
                    'uri': 'system://status',
                    'contents': '=state.system_status'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'status_published', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('status_published'), isTrue);
        final status = runtime.getState('system_status') as Map;
        expect(status['hardware'], isNotNull);
        expect(status['processes'], isNotNull);
        expect(status['memory'], isNotNull);
      });

      test('mcpUpdateResource in scheduled process', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'update_count': {'type': 'number', 'initial': 0},
            'last_update': {'type': 'number', 'initial': 0},
          },
          'processes': [
            {
              'id': 'periodic_updater',
              'trigger': {
                'type': 'schedule',
                'interval': 100
              },
              'steps': [
                {
                  'action': 'stateUpdate',
                  'params': {
                    'key': 'update_count',
                    'operation': 'increment'
                  }
                },
                {
                  'action': 'mcpUpdateResource',
                  'params': {
                    'uri': 'metrics://updates',
                    'contents': {
                      'count': '=state.update_count',
                      'timestamp': '=Date.now()'
                    }
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'last_update', 'value': '=Date.now()'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Wait for multiple updates
        await Future.delayed(Duration(milliseconds: 350));
        
        final count = runtime.getState('update_count');
        expect(count, greaterThanOrEqualTo(3));
        expect(runtime.getState('last_update'), greaterThan(0));
      });
    });

    group('MCP Integration Patterns', () {
      test('sensor data pipeline with MCP notifications', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'readings': {'type': 'array', 'initial': []},
            'alert_triggered': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'sensor_pipeline',
              'trigger': {'type': 'startup'},
              'steps': [
                // Simulate sensor readings
                {
                  'action': 'for',
                  'params': {
                    'variable': 'i',
                    'from': 0,
                    'to': 5,
                    'step': 1
                  },
                  'do': [
                    {
                      'action': 'stateUpdate',
                      'params': {
                        'key': 'readings',
                        'operation': 'append',
                        'value': '=20 + i * 3'
                      }
                    }
                  ]
                },
                // Update resource with readings
                {
                  'action': 'mcpUpdateResource',
                  'params': {
                    'uri': 'sensor://temperature/history',
                    'contents': '=state.readings'
                  }
                },
                // Check for alerts
                {
                  'action': 'if',
                  'condition': '=max(state.readings) > 30',
                  'then': [
                    {
                      'action': 'mcpNotify',
                      'params': {
                        'resource': 'alert://temperature',
                        'level': 'warn',
                        'includeData': true,
                        'data': {
                          'max_value': '=max(state.readings)',
                          'readings': '=state.readings'
                        }
                      }
                    },
                    {
                      'action': 'stateSet',
                      'params': {'key': 'alert_triggered', 'value': true}
                    }
                  ]
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        final readings = runtime.getState('readings') as List;
        expect(readings.length, equals(6)); // for loop from 0 to 5 is inclusive (0,1,2,3,4,5)
        expect(runtime.getState('alert_triggered'), isTrue);
      });
    });
  });
}