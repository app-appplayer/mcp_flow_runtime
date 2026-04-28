// Multiple Triggers Example - Demonstrates processes with multiple trigger types

import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() async {
  // Example: Multi-source data collector
  final dataCollectorFlow = {
    "version": "1.0.0",
    "metadata": {
      "name": "Data Collector",
      "description": "Collects data from multiple sources"
    },
    "state": {
      "data_points": {"type": "array", "initial": []},
      "collection_count": {"type": "number", "initial": 0},
      "last_source": {"type": "string", "initial": ""}
    },
    "channels": {
      "sensor_data": {"type": "pubsub"},
      "manual_data": {"type": "queue"}
    },
    "processes": [{
      "id": "data_collector",
      "triggers": [
        // Collect on startup
        {"type": "startup"},
        // Collect every 5 seconds
        {"type": "schedule", "interval": 5000},
        // Collect when sensor data arrives
        {"type": "channelReceive", "channel": "sensor_data"},
        // Collect on manual trigger
        {"type": "event", "event": "collect_now"}
      ],
      "steps": [
        {
          "action": "expression",
          "params": {
            "expression": "(trigger && trigger.type) || 'unknown'"
          },
          "bindTo": "source"
        },
        {
          "action": "expression",
          "params": {
            "expression": "trigger && trigger.data || {value: Math.random() * 100}"
          },
          "bindTo": "data"
        },
        {
          "action": "setState",
          "params": {
            "variable": "data_points",
            "value": "= [...data_points, {source: source, data: data, time: Date.now()}]"
          }
        },
        {
          "action": "setState",
          "params": {
            "variable": "collection_count",
            "value": "= collection_count + 1"
          }
        },
        {
          "action": "setState",
          "params": {
            "variable": "last_source",
            "value": "= source"
          }
        },
        {
          "action": "log",
          "params": {
            "message": "Data collected from = source (total: = collection_count)"
          }
        }
      ]
    }]
  };

  // Example: System monitor with multiple alert conditions
  final systemMonitorFlow = {
    "version": "1.0.0",
    "metadata": {
      "name": "System Monitor",
      "description": "Monitors system health from multiple angles"
    },
    "resources": {
      "status_led": {
        "type": "gpio",
        "config": {"pin": 13, "mode": "output"}
      }
    },
    "state": {
      "cpu_usage": {"type": "number", "initial": 0},
      "memory_usage": {"type": "number", "initial": 0},
      "disk_space": {"type": "number", "initial": 100},
      "alert_level": {"type": "string", "initial": "normal"}
    },
    "processes": [{
      "id": "alert_handler",
      "triggers": [
        // Check when CPU usage changes
        {"type": "stateChange", "variable": "cpu_usage"},
        // Check when memory usage changes
        {"type": "stateChange", "variable": "memory_usage"},
        // Check when disk space changes
        {"type": "stateChange", "variable": "disk_space"},
        // Regular health check every minute
        {"type": "schedule", "interval": 60000}
      ],
      "steps": [
        {
          "action": "expression",
          "params": {
            "expression": "cpu_usage > 80 || memory_usage > 90 || disk_space < 10"
          },
          "bindTo": "is_critical"
        },
        {
          "action": "expression",
          "params": {
            "expression": "cpu_usage > 60 || memory_usage > 70 || disk_space < 20"
          },
          "bindTo": "is_warning"
        },
        {
          "action": "if",
          "params": {"condition": "is_critical"},
          "then": [
            {
              "action": "setState",
              "params": {"variable": "alert_level", "value": "critical"}
            },
            {
              "action": "gpioWrite",
              "params": {"pin": 13, "value": true}
            },
            {
              "action": "log",
              "params": {
                "level": "error",
                "message": "CRITICAL: CPU=cpu_usage%, MEM=memory_usage%, DISK=disk_space%"
              }
            }
          ],
          "else": [{
            "action": "if",
            "params": {"condition": "is_warning"},
            "then": [
              {
                "action": "setState",
                "params": {"variable": "alert_level", "value": "warning"}
              },
              {
                "action": "log",
                "params": {
                  "level": "warn",
                  "message": "WARNING: CPU=cpu_usage%, MEM=memory_usage%, DISK=disk_space%"
                }
              }
            ],
            "else": [
              {
                "action": "setState",
                "params": {"variable": "alert_level", "value": "normal"}
              },
              {
                "action": "gpioWrite",
                "params": {"pin": 13, "value": false}
              }
            ]
          }]
        }
      ]
    }]
  };

  // Example: Command processor with multiple input methods
  final commandProcessorFlow = {
    "version": "1.0.0",
    "metadata": {
      "name": "Command Processor",
      "description": "Processes commands from various sources"
    },
    "state": {
      "last_command": {"type": "string", "initial": ""},
      "command_count": {"type": "number", "initial": 0},
      "mode": {"type": "string", "initial": "idle"}
    },
    "channels": {
      "serial_commands": {"type": "queue"},
      "network_commands": {"type": "queue"},
      "scheduled_commands": {"type": "queue"}
    },
    "processes": [
      {
        "id": "command_processor",
        "triggers": [
          // Process commands from serial port
          {"type": "channelReceive", "channel": "serial_commands"},
          // Process commands from network
          {"type": "channelReceive", "channel": "network_commands"},
          // Process scheduled commands
          {"type": "channelReceive", "channel": "scheduled_commands"},
          // Process on mode change
          {"type": "stateChange", "variable": "mode"},
          // Manual command event
          {"type": "event", "event": "execute_command"}
        ],
        "steps": [
          {
            "action": "expression",
            "params": {
              "expression": "trigger && trigger.data && trigger.data.command || 'status'"
            },
            "bindTo": "command"
          },
          {
            "action": "setState",
            "params": {
              "variable": "last_command",
              "value": "= command"
            }
          },
          {
            "action": "setState",
            "params": {
              "variable": "command_count",
              "value": "= command_count + 1"
            }
          },
          {
            "action": "switch",
            "params": {"value": "= command"},
            "cases": {
              "start": [{
                "action": "setState",
                "params": {"variable": "mode", "value": "running"}
              }],
              "stop": [{
                "action": "setState",
                "params": {"variable": "mode", "value": "idle"}
              }],
              "pause": [{
                "action": "setState",
                "params": {"variable": "mode", "value": "paused"}
              }],
              "status": [{
                "action": "log",
                "params": {
                  "message": "Status: mode=mode, commands=command_count"
                }
              }]
            },
            "default": [{
              "action": "log",
              "params": {
                "level": "warn",
                "message": "Unknown command: = command"
              }
            }]
          }
        ]
      },
      {
        "id": "scheduled_task_generator",
        "trigger": {"type": "schedule", "interval": 10000},
        "steps": [{
          "action": "channelSend",
          "params": {
            "channel": "scheduled_commands",
            "data": "= {command: 'status', source: 'scheduler'}"
          }
        }]
      }
    ]
  };

  // Run data collector example
  print('=== Data Collector Example ===');
  final collectorRuntime = McpFlowRuntime();
  await collectorRuntime.loadFlow(dataCollectorFlow);
  await collectorRuntime.start();

  // Monitor data collection
  collectorRuntime.stateEventBus.on<StateChangeEvent>().listen((event) {
    if (event.variable == 'collection_count') {
      print('Data points collected: ${event.newValue} (from ${collectorRuntime.getState('last_source')})');
    }
  });

  // Send sensor data
  await collectorRuntime.sendToChannel('sensor_data', {'value': 25.5, 'sensor': 'temp1'});
  await Future.delayed(Duration(milliseconds: 100));

  // Manual trigger
  collectorRuntime.emitEvent('collect_now');
  await Future.delayed(Duration(milliseconds: 100));

  // Wait for scheduled collection
  print('Waiting for scheduled collection...');
  await Future.delayed(Duration(seconds: 6));

  await collectorRuntime.stop();

  // Run system monitor example
  print('\n=== System Monitor Example ===');
  final monitorRuntime = McpFlowRuntime();
  await monitorRuntime.loadFlow(systemMonitorFlow);
  await monitorRuntime.start();

  // Monitor alert level
  monitorRuntime.stateEventBus.on<StateChangeEvent>().listen((event) {
    if (event.variable == 'alert_level' && event.newValue != event.oldValue) {
      print('Alert level changed: ${event.oldValue} -> ${event.newValue}');
    }
  });

  // Simulate system load changes
  print('Simulating system load...');
  await monitorRuntime.setState('cpu_usage', 45);
  await Future.delayed(Duration(milliseconds: 100));
  
  await monitorRuntime.setState('memory_usage', 75);
  await Future.delayed(Duration(milliseconds: 100));
  
  await monitorRuntime.setState('disk_space', 15);
  await Future.delayed(Duration(milliseconds: 100));
  
  // Critical state
  await monitorRuntime.setState('cpu_usage', 85);
  await Future.delayed(Duration(milliseconds: 100));

  await Future.delayed(Duration(seconds: 1));
  await monitorRuntime.stop();

  // Run command processor example
  print('\n=== Command Processor Example ===');
  final commandRuntime = McpFlowRuntime();
  await commandRuntime.loadFlow(commandProcessorFlow);
  await commandRuntime.start();

  // Monitor mode changes
  commandRuntime.stateEventBus.on<StateChangeEvent>().listen((event) {
    if (event.variable == 'mode') {
      print('Mode changed to: ${event.newValue}');
    }
  });

  // Send commands from different sources
  await commandRuntime.sendToChannel('serial_commands', {'command': 'start', 'source': 'serial'});
  await Future.delayed(Duration(milliseconds: 100));

  await commandRuntime.sendToChannel('network_commands', {'command': 'pause', 'source': 'network'});
  await Future.delayed(Duration(milliseconds: 100));

  commandRuntime.emitEvent('execute_command');
  await Future.delayed(Duration(milliseconds: 100));

  // Wait for scheduled status
  print('Waiting for scheduled status check...');
  await Future.delayed(Duration(seconds: 11));

  final commands = commandRuntime.getState('command_count');
  print('Total commands processed: $commands');

  await commandRuntime.stop();
  
  print('\nMultiple triggers examples completed!');
}