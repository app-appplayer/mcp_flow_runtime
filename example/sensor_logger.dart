import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Example: Log sensor data to file and calculate statistics
void main() async {
  // Create runtime
  final runtime = McpFlowRuntime();
  
  // Define flow for sensor data logging
  final flowDefinition = {
    'version': '1.0.0',
    'metadata': {
      'name': 'Sensor Data Logger',
      'description': 'Logs sensor data to file and calculates running statistics',
      'author': 'MCP Flow Examples',
    },
    'resources': {
      'humidity_sensor': {
        'type': 'adc',
        'config': {
          'channel': 0,
          'resolution': 12
        }
      },
      'temperature_sensor': {
        'type': 'adc',
        'config': {
          'channel': 1,
          'resolution': 12
        }
      }
    },
    'state': {
      'humidity': {
        'type': 'number',
        'initial': 0.0,
        'persistent': true
      },
      'temperature': {
        'type': 'number',
        'initial': 0.0,
        'persistent': true
      },
      'readings_count': {
        'type': 'number',
        'initial': 0,
        'persistent': true
      },
      'humidity_sum': {
        'type': 'number',
        'initial': 0.0,
        'persistent': true
      },
      'temperature_sum': {
        'type': 'number',
        'initial': 0.0,
        'persistent': true
      },
      'log_filename': {
        'type': 'string',
        'initial': 'sensor_data.csv',
        'persistent': true
      }
    },
    'channels': {
      'sensor_data': {
        'type': 'pubsub',
        'capacity': 1000
      },
      'stats_updates': {
        'type': 'pubsub'
      }
    },
    'processes': [
      {
        'id': 'sensor_reader',
        'name': 'Sensor Data Reader',
        'trigger': {
          'type': 'schedule',
          'interval': 5000 // Read every 5 seconds
        },
        'steps': [
          // Read humidity
          {
            'action': 'adc.read',
            'params': {
              'channel': 0
            },
            'bindTo': 'humidity_raw'
          },
          // Convert to percentage (assuming 0-4095 maps to 0-100%)
          {
            'action': 'expression',
            'params': {
              'expression': '(humidity_raw / 4095) * 100'
            },
            'bindTo': 'humidity_percent'
          },
          // Read temperature
          {
            'action': 'adc.read',
            'params': {
              'channel': 1
            },
            'bindTo': 'temp_raw'
          },
          // Convert to Celsius (assuming sensor output)
          {
            'action': 'expression',
            'params': {
              'expression': '((temp_raw / 4095) * 3.3 - 0.5) * 100'
            },
            'bindTo': 'temp_celsius'
          },
          // Update state
          {
            'action': 'setState',
            'params': {
              'variable': 'humidity',
              'value': '=humidity_percent'
            }
          },
          {
            'action': 'setState',
            'params': {
              'variable': 'temperature',
              'value': '=temp_celsius'
            }
          },
          // Send to channel
          {
            'action': 'channelSend',
            'params': {
              'channel': 'sensor_data',
              'data': '={timestamp: Date.now(), humidity: humidity_percent, temperature: temp_celsius}'
            }
          }
        ]
      },
      {
        'id': 'data_logger',
        'name': 'Data Logger to File',
        'trigger': {
          'type': 'channelReceive',
          'channel': 'sensor_data'
        },
        'steps': [
          // Increment counter
          {
            'action': 'setState',
            'params': {
              'variable': 'readings_count',
              'value': '=readings_count + 1'
            }
          },
          // Update running sums
          {
            'action': 'setState',
            'params': {
              'variable': 'humidity_sum',
              'value': '=humidity_sum + humidity'
            }
          },
          {
            'action': 'setState',
            'params': {
              'variable': 'temperature_sum',
              'value': '=temperature_sum + temperature'
            }
          },
          // Format CSV line
          {
            'action': 'expression',
            'params': {
              'expression': 'timestamp + "," + humidity + "," + temperature'
            },
            'bindTo': 'csv_line'
          },
          // Append to file
          {
            'action': 'fileAppend',
            'params': {
              'path': '=log_filename',
              'content': '=csv_line + "\\n"'
            }
          },
          // Log status
          {
            'action': 'log',
            'params': {
              'message': 'Data logged',
              'level': 'debug'
            }
          }
        ]
      },
      {
        'id': 'stats_calculator',
        'name': 'Statistics Calculator',
        'trigger': {
          'type': 'schedule',
          'interval': 30000 // Calculate stats every 30 seconds
        },
        'steps': [
          // Calculate averages
          {
            'action': 'if',
            'params': {
              'condition': 'readings_count > 0'
            },
            'then': [
              {
                'action': 'expression',
                'params': {
                  'expression': 'humidity_sum / readings_count'
                },
                'bindTo': 'avg_humidity'
              },
              {
                'action': 'expression',
                'params': {
                  'expression': 'temperature_sum / readings_count'
                },
                'bindTo': 'avg_temperature'
              },
              // Send stats update
              {
                'action': 'channelSend',
                'params': {
                  'channel': 'stats_updates',
                  'data': '={count: readings_count, avgHumidity: avg_humidity, avgTemperature: avg_temperature}'
                }
              },
              // Log statistics
              {
                'action': 'log',
                'params': {
                  'message': 'Statistics calculated',
                  'level': 'info'
                }
              }
            ]
          }
        ]
      },
      {
        'id': 'file_initializer',
        'name': 'Initialize CSV File',
        'trigger': {
          'type': 'startup'
        },
        'steps': [
          // Check if file exists
          {
            'action': 'fileExists',
            'params': {
              'path': '=log_filename'
            },
            'bindTo': 'file_exists'
          },
          // Create header if new file
          {
            'action': 'if',
            'params': {
              'condition': '!file_exists'
            },
            'then': [
              {
                'action': 'fileWrite',
                'params': {
                  'path': '=log_filename',
                  'content': 'timestamp,humidity,temperature\n'
                }
              },
              {
                'action': 'log',
                'params': {
                  'message': 'Created new log file with headers',
                  'level': 'info'
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
    print('Loading sensor logger flow...');
    await runtime.loadFlow(flowDefinition);
    
    // Start the runtime
    print('Starting sensor data logging...');
    await runtime.start();
    
    // Monitor stats updates
    runtime.getChannelStream('stats_updates')?.listen((stats) {
      print('\nStatistics Update:');
      print('  Total Readings: ${stats['count']}');
      print('  Avg Humidity: ${stats['avgHumidity'].toStringAsFixed(1)}%');
      print('  Avg Temperature: ${stats['avgTemperature'].toStringAsFixed(1)}°C');
    });
    
    // Monitor for 2 minutes
    print('Logging sensor data for 2 minutes...');
    await Future.delayed(const Duration(minutes: 2));
    
    // Get final statistics
    final count = runtime.getState('readings_count');
    final avgHumidity = runtime.getState('humidity_sum') / count;
    final avgTemp = runtime.getState('temperature_sum') / count;
    
    print('\nFinal Statistics:');
    print('Total readings: $count');
    print('Average humidity: ${avgHumidity.toStringAsFixed(2)}%');
    print('Average temperature: ${avgTemp.toStringAsFixed(2)}°C');
    print('Data saved to: ${runtime.getState('log_filename')}');
    
    // Stop the runtime
    await runtime.stop();
    print('Data logging stopped.');
  } catch (e) {
    print('Error: $e');
  }
}