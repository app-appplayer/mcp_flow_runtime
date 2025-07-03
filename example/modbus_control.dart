import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Example: Control industrial equipment via Modbus RTU/TCP
void main() async {
  // Create runtime
  final runtime = McpFlowRuntime();
  
  // Define flow for Modbus device control
  final flowDefinition = {
    'version': '1.0.0',
    'metadata': {
      'name': 'Modbus Industrial Control',
      'description': 'Controls pumps and monitors tank levels via Modbus',
      'author': 'MCP Flow Examples',
    },
    'resources': {
      'plc_connection': {
        'type': 'modbus',
        'config': {
          'type': 'tcp',  // or 'rtu' for serial
          'host': '192.168.1.100',
          'port': 502,
          'unitId': 1,
          'timeout': 5000
        }
      },
      'alarm_light': {
        'type': 'gpio',
        'config': {
          'pin': 25,
          'mode': 'output'
        }
      }
    },
    'state': {
      'tank_level': {
        'type': 'number',
        'initial': 0.0,
        'persistent': true,
        'constraints': {
          'min': 0,
          'max': 100
        }
      },
      'pump1_status': {
        'type': 'boolean',
        'initial': false,
        'persistent': true
      },
      'pump2_status': {
        'type': 'boolean',
        'initial': false,
        'persistent': true
      },
      'flow_rate': {
        'type': 'number',
        'initial': 0.0,
        'persistent': false
      },
      'alarm_active': {
        'type': 'boolean',
        'initial': false,
        'persistent': true
      },
      'auto_mode': {
        'type': 'boolean',
        'initial': true,
        'persistent': true
      }
    },
    'channels': {
      'plc_data': {
        'type': 'pubsub'
      },
      'alarm_events': {
        'type': 'queue',
        'capacity': 100
      }
    },
    'processes': [
      {
        'id': 'plc_monitor',
        'name': 'PLC Data Monitor',
        'trigger': {
          'type': 'schedule',
          'interval': 1000  // Poll every second
        },
        'steps': [
          // Read tank level (Holding Register 40001)
          {
            'action': 'modbusRead',
            'params': {
              'connection': 'plc_connection',
              'type': 'holding',
              'address': 0,
              'count': 1
            },
            'bindTo': 'tank_level_raw'
          },
          // Convert to percentage
          {
            'action': 'expression',
            'params': {
              'expression': '(tank_level_raw[0] / 32767) * 100'
            },
            'bindTo': 'tank_percent'
          },
          // Read pump status (Coils 1-2)
          {
            'action': 'modbusRead',
            'params': {
              'connection': 'plc_connection',
              'type': 'coil',
              'address': 0,
              'count': 2
            },
            'bindTo': 'pump_states'
          },
          // Read flow rate (Input Register 30001)
          {
            'action': 'modbusRead',
            'params': {
              'connection': 'plc_connection',
              'type': 'input',
              'address': 0,
              'count': 1
            },
            'bindTo': 'flow_raw'
          },
          // Update state variables
          {
            'action': 'setState',
            'params': {
              'variable': 'tank_level',
              'value': '=tank_percent'
            }
          },
          {
            'action': 'setState',
            'params': {
              'variable': 'pump1_status',
              'value': '=pump_states[0]'
            }
          },
          {
            'action': 'setState',
            'params': {
              'variable': 'pump2_status',
              'value': '=pump_states[1]'
            }
          },
          {
            'action': 'setState',
            'params': {
              'variable': 'flow_rate',
              'value': '=flow_raw[0] * 0.1'  // Convert to L/min
            }
          },
          // Send to monitoring channel
          {
            'action': 'channelSend',
            'params': {
              'channel': 'plc_data',
              'data': '={timestamp: Date.now(), tank: tank_percent, pump1: pump_states[0], pump2: pump_states[1], flow: flow_raw[0] * 0.1}'
            }
          }
        ],
        'error': [
          {
            'action': 'log',
            'params': {
              'message': 'PLC communication error',
              'level': 'error'
            }
          },
          {
            'action': 'setState',
            'params': {
              'variable': 'alarm_active',
              'value': true
            }
          }
        ]
      },
      {
        'id': 'pump_controller',
        'name': 'Automatic Pump Control',
        'trigger': {
          'type': 'condition',
          'condition': 'auto_mode'
        },
        'steps': [
          // Check tank level and control pumps
          {
            'action': 'switch',
            'value': '=true',
            'cases': {
              'true': [
                // Low level - start both pumps
                {
                  'action': 'if',
                  'params': {
                    'condition': 'tank_level < 20'
                  },
                  'then': [
                    {
                      'action': 'modbusWrite',
                      'params': {
                        'connection': 'plc_connection',
                        'type': 'coil',
                        'address': 0,
                        'values': [true, true]  // Start both pumps
                      }
                    },
                    {
                      'action': 'channelSend',
                      'params': {
                        'channel': 'alarm_events',
                        'data': '={type: "low_level", timestamp: Date.now(), level: tank_level}'
                      }
                    },
                    {
                      'action': 'setState',
                      'params': {
                        'variable': 'alarm_active',
                        'value': true
                      }
                    }
                  ]
                },
                // Normal level - run pump 1 only
                {
                  'action': 'if',
                  'params': {
                    'condition': 'tank_level >= 20 && tank_level < 80'
                  },
                  'then': [
                    {
                      'action': 'modbusWrite',
                      'params': {
                        'connection': 'plc_connection',
                        'type': 'coil',
                        'address': 0,
                        'values': [true, false]  // Pump 1 only
                      }
                    },
                    {
                      'action': 'setState',
                      'params': {
                        'variable': 'alarm_active',
                        'value': false
                      }
                    }
                  ]
                },
                // High level - stop all pumps
                {
                  'action': 'if',
                  'params': {
                    'condition': 'tank_level >= 80'
                  },
                  'then': [
                    {
                      'action': 'modbusWrite',
                      'params': {
                        'connection': 'plc_connection',
                        'type': 'coil',
                        'address': 0,
                        'values': [false, false]  // Stop both pumps
                      }
                    },
                    {
                      'action': 'if',
                      'params': {
                        'condition': 'tank_level > 90'
                      },
                      'then': [
                        {
                          'action': 'channelSend',
                          'params': {
                            'channel': 'alarm_events',
                            'data': '={type: "high_level", timestamp: Date.now(), level: tank_level}'
                          }
                        },
                        {
                          'action': 'setState',
                          'params': {
                            'variable': 'alarm_active',
                            'value': true
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          },
          // Delay before next check
          {
            'action': 'delay',
            'params': {
              'ms': 5000  // Check every 5 seconds
            }
          }
        ]
      },
      {
        'id': 'alarm_handler',
        'name': 'Alarm Light Controller',
        'trigger': {
          'type': 'stateChange',
          'variable': 'alarm_active'
        },
        'steps': [
          {
            'action': 'gpioWrite',
            'params': {
              'pin': 25,
              'value': '=alarm_active'
            }
          },
          {
            'action': 'if',
            'params': {
              'condition': 'alarm_active'
            },
            'then': [
              {
                'action': 'log',
                'params': {
                  'message': 'ALARM ACTIVATED',
                  'level': 'warning'
                }
              }
            ],
            'else': [
              {
                'action': 'log',
                'params': {
                  'message': 'Alarm cleared',
                  'level': 'info'
                }
              }
            ]
          }
        ]
      },
      {
        'id': 'emergency_stop',
        'name': 'Emergency Stop Handler',
        'trigger': {
          'type': 'manual'
        },
        'priority': 'realtime',
        'steps': [
          // Stop all pumps immediately
          {
            'action': 'modbusWrite',
            'params': {
              'connection': 'plc_connection',
              'type': 'coil',
              'address': 0,
              'values': [false, false]
            }
          },
          // Disable auto mode
          {
            'action': 'setState',
            'params': {
              'variable': 'auto_mode',
              'value': false
            }
          },
          // Activate alarm
          {
            'action': 'setState',
            'params': {
              'variable': 'alarm_active',
              'value': true
            }
          },
          // Log emergency
          {
            'action': 'log',
            'params': {
              'message': 'EMERGENCY STOP ACTIVATED',
              'level': 'error'
            }
          }
        ]
      }
    ]
  };
  
  try {
    // Load the flow
    print('Loading Modbus control flow...');
    await runtime.loadFlow(flowDefinition);
    
    // Start the runtime
    print('Starting industrial control system...');
    await runtime.start();
    
    // Monitor alarm events
    runtime.getChannelStream('alarm_events')?.listen((event) {
      print('\n!!! ALARM: ${event['type'].toUpperCase()} - Tank level: ${event['level'].toStringAsFixed(1)}%');
    });
    
    // Monitor PLC data
    runtime.getChannelStream('plc_data')?.listen((data) {
      print('Tank: ${data['tank'].toStringAsFixed(1)}% | ' +
            'Pump1: ${data['pump1'] ? "ON" : "OFF"} | ' +
            'Pump2: ${data['pump2'] ? "ON" : "OFF"} | ' +
            'Flow: ${data['flow'].toStringAsFixed(1)} L/min');
    });
    
    // Run for 5 minutes
    print('\nMonitoring industrial equipment for 5 minutes...');
    print('Press Ctrl+C for emergency stop');
    
    await Future.delayed(const Duration(minutes: 5));
    
    // Get final status
    print('\nFinal System Status:');
    print('Tank Level: ${runtime.getState('tank_level')}%');
    print('Pump 1: ${runtime.getState('pump1_status') ? "ON" : "OFF"}');
    print('Pump 2: ${runtime.getState('pump2_status') ? "ON" : "OFF"}');
    print('Flow Rate: ${runtime.getState('flow_rate')} L/min');
    print('Alarm: ${runtime.getState('alarm_active') ? "ACTIVE" : "Clear"}');
    
    // Stop the runtime
    await runtime.stop();
    print('\nIndustrial control system stopped.');
  } catch (e) {
    print('Error: $e');
    
    // Try emergency stop
    try {
      await runtime.executeProcess('emergency_stop');
    } catch (_) {}
  }
}