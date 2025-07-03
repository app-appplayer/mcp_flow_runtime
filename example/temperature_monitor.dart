import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Example: Monitor temperature from I2C sensor and control fan
void main() async {
  // Create runtime
  final runtime = McpFlowRuntime();
  
  // Define flow for temperature monitoring
  final flowDefinition = {
    'version': '1.0.0',
    'metadata': {
      'name': 'Temperature Monitor',
      'description': 'Monitors temperature and controls cooling fan',
      'author': 'MCP Flow Examples',
    },
    'resources': {
      'temp_sensor': {
        'type': 'i2c',
        'config': {
          'bus': 1,
          'address': 0x48, // TMP102 sensor address
        }
      },
      'fan_control': {
        'type': 'pwm',
        'config': {
          'channel': 0,
          'frequency': 25000, // 25kHz for fan control
        }
      },
      'status_led': {
        'type': 'gpio',
        'config': {
          'pin': 22,
          'mode': 'output'
        }
      }
    },
    'state': {
      'temperature': {
        'type': 'number',
        'initial': 20.0,
        'persistent': true,
        'constraints': {
          'min': -40,
          'max': 125
        }
      },
      'fan_speed': {
        'type': 'number',
        'initial': 0,
        'persistent': false,
        'constraints': {
          'min': 0,
          'max': 100
        }
      },
      'high_temp_alert': {
        'type': 'boolean',
        'initial': false,
        'persistent': true
      }
    },
    'channels': {
      'temp_readings': {
        'type': 'queue',
        'capacity': 100
      }
    },
    'processes': [
      {
        'id': 'temp_reader',
        'name': 'Temperature Reader',
        'trigger': {
          'type': 'schedule',
          'interval': 1000 // Read every second
        },
        'steps': [
          // Read temperature from I2C sensor
          {
            'action': 'i2cRead',
            'params': {
              'bus': 1,
              'address': 0x48,
              'length': 2
            },
            'bindTo': 'raw_temp'
          },
          // Convert raw reading to temperature
          {
            'action': 'expression',
            'params': {
              // Simulate temperature calculation (would be sensor-specific)
              'expression': '20 + (raw_temp[0] * 0.1)'
            },
            'bindTo': 'temp_celsius'
          },
          // Update state
          {
            'action': 'setState',
            'params': {
              'variable': 'temperature',
              'value': '=temp_celsius'
            }
          },
          // Send to channel for logging
          {
            'action': 'channelSend',
            'params': {
              'channel': 'temp_readings',
              'data': '={timestamp: Date.now(), temperature: temp_celsius}'
            }
          }
        ]
      },
      {
        'id': 'fan_controller',
        'name': 'Fan Speed Controller',
        'trigger': {
          'type': 'condition',
          'condition': 'temperature > 25'
        },
        'steps': [
          // Calculate fan speed based on temperature
          {
            'action': 'switch',
            'value': '=true',
            'cases': {
              'true': [
                {
                  'action': 'if',
                  'params': {
                    'condition': 'temperature < 30'
                  },
                  'then': [
                    {
                      'action': 'setState',
                      'params': {
                        'variable': 'fan_speed',
                        'value': 30
                      }
                    }
                  ],
                  'else': [
                    {
                      'action': 'if',
                      'params': {
                        'condition': 'temperature < 40'
                      },
                      'then': [
                        {
                          'action': 'setState',
                          'params': {
                            'variable': 'fan_speed',
                            'value': 60
                          }
                        }
                      ],
                      'else': [
                        {
                          'action': 'setState',
                          'params': {
                            'variable': 'fan_speed',
                            'value': 100
                          }
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          },
          // Set PWM duty cycle for fan
          {
            'action': 'pwmWrite',
            'params': {
              'channel': 0,
              'dutyCycle': '=fan_speed / 100'
            }
          },
          // Update alert status
          {
            'action': 'setState',
            'params': {
              'variable': 'high_temp_alert',
              'value': '=temperature > 45'
            }
          },
          // Control status LED
          {
            'action': 'gpioWrite',
            'params': {
              'pin': 22,
              'value': '=high_temp_alert'
            }
          },
          // Log if critical
          {
            'action': 'if',
            'params': {
              'condition': 'temperature > 50'
            },
            'then': [
              {
                'action': 'log',
                'params': {
                  'message': 'CRITICAL: Temperature exceeds 50°C!',
                  'level': 'error'
                }
              }
            ]
          }
        ]
      }
    ]
  };
  
  try {
    // Load the flow
    print('Loading temperature monitor flow...');
    await runtime.loadFlow(flowDefinition);
    
    // Start the runtime
    print('Starting temperature monitoring...');
    await runtime.start();
    
    // Monitor for 60 seconds
    print('Monitoring temperature for 60 seconds...');
    
    // Listen to temperature changes
    runtime.stateEventBus.on<StateChangeEvent>()
        .where((event) => event.variable == 'temperature')
        .listen((event) {
      print('Temperature: ${event.newValue}°C');
    });
    
    await Future.delayed(const Duration(seconds: 60));
    
    // Get statistics
    final temp = runtime.getState('temperature');
    final fanSpeed = runtime.getState('fan_speed');
    final alert = runtime.getState('high_temp_alert');
    
    print('\nFinal readings:');
    print('Temperature: $temp°C');
    print('Fan Speed: $fanSpeed%');
    print('High Temp Alert: $alert');
    
    // Stop the runtime
    await runtime.stop();
    print('Monitoring stopped.');
  } catch (e) {
    print('Error: $e');
  }
}