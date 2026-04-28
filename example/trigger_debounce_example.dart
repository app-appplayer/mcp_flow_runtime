// Trigger Debounce Example - Demonstrates debounce functionality

import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() async {
  // Example: Button press handler with debounce
  final buttonHandlerFlow = {
    "version": "1.0.0",
    "metadata": {
      "name": "Button Handler",
      "description": "Debounced button press handler"
    },
    "resources": {
      "button": {
        "type": "gpio",
        "config": {
          "pin": 2,
          "mode": "input",
          "pull": "up"
        }
      },
      "led": {
        "type": "gpio",
        "config": {
          "pin": 13,
          "mode": "output"
        }
      }
    },
    "state": {
      "button_presses": {"type": "number", "initial": 0},
      "led_state": {"type": "boolean", "initial": false}
    },
    "processes": [{
      "id": "button_handler",
      "trigger": {
        "type": "resourceEvent",
        "resource": "button",
        "event": "change",
        "debounceMs": 50  // Debounce for 50ms to avoid bouncing
      },
      "steps": [
        {
          "action": "setState",
          "params": {
            "variable": "button_presses",
            "value": "= button_presses + 1"
          }
        },
        {
          "action": "setState",
          "params": {
            "variable": "led_state",
            "value": "= !led_state"
          }
        },
        {
          "action": "gpioWrite",
          "params": {
            "pin": 13,
            "value": "= led_state"
          }
        },
        {
          "action": "log",
          "params": {
            "message": "Button pressed (count: = button_presses)"
          }
        }
      ]
    }]
  };

  // Example: Sensor monitoring with debounce
  final sensorMonitorFlow = {
    "version": "1.0.0",
    "metadata": {
      "name": "Sensor Monitor",
      "description": "Debounced sensor value monitoring"
    },
    "state": {
      "temperature": {"type": "number", "initial": 20.0},
      "alert_sent": {"type": "boolean", "initial": false},
      "last_alert_time": {"type": "number", "initial": 0}
    },
    "channels": {
      "alerts": {"type": "queue", "capacity": 100}
    },
    "processes": [{
      "id": "temperature_alert",
      "trigger": {
        "type": "stateChange",
        "variable": "temperature",
        "debounceMs": 5000  // Only trigger after 5 seconds of stable reading
      },
      "steps": [
        {
          "action": "if",
          "params": {"condition": "temperature > 30 && !alert_sent"},
          "then": [
            {
              "action": "channelSend",
              "params": {
                "channel": "alerts",
                "data": "= {type: 'high_temp', value: temperature, time: Date.now()}"
              }
            },
            {
              "action": "setState",
              "params": {"variable": "alert_sent", "value": true}
            },
            {
              "action": "setState",
              "params": {"variable": "last_alert_time", "value": "= Date.now()"}
            }
          ]
        },
        {
          "action": "if",
          "params": {"condition": "temperature <= 25 && alert_sent"},
          "then": [{
            "action": "setState",
            "params": {"variable": "alert_sent", "value": false}
          }]
        }
      ]
    }]
  };

  // Example: Search input handler with debounce
  final searchHandlerFlow = {
    "version": "1.0.0",
    "metadata": {
      "name": "Search Handler",
      "description": "Debounced search input processing"
    },
    "state": {
      "search_query": {"type": "string", "initial": ""},
      "search_results": {"type": "array", "initial": []},
      "is_searching": {"type": "boolean", "initial": false}
    },
    "processes": [{
      "id": "search_processor",
      "trigger": {
        "type": "stateChange",
        "variable": "search_query",
        "debounceMs": 300  // Wait 300ms after user stops typing
      },
      "steps": [
        {
          "action": "if",
          "params": {"condition": "search_query.length >= 3"},
          "then": [
            {
              "action": "setState",
              "params": {"variable": "is_searching", "value": true}
            },
            {
              "action": "log",
              "params": {"message": "Searching for: = search_query"}
            },
            // Simulate search delay
            {
              "action": "delay",
              "params": {"ms": 500}
            },
            {
              "action": "setState",
              "params": {
                "variable": "search_results",
                "value": "= ['Result 1 for ' + search_query, 'Result 2 for ' + search_query]"
              }
            },
            {
              "action": "setState",
              "params": {"variable": "is_searching", "value": false}
            }
          ],
          "else": [{
            "action": "setState",
            "params": {"variable": "search_results", "value": []}
          }]
        }
      ]
    }]
  };

  // Run the button handler example
  print('=== Button Handler Example ===');
  final buttonRuntime = McpFlowRuntime();
  await buttonRuntime.loadFlow(buttonHandlerFlow);
  await buttonRuntime.start();

  // Monitor button presses
  buttonRuntime.stateEventBus.on<StateChangeEvent>().listen((event) {
    if (event.variable == 'button_presses') {
      print('Button press count: ${event.newValue}');
    }
  });

  // Simulate rapid button presses (would be debounced)
  for (int i = 0; i < 5; i++) {
    buttonRuntime.emitResourceEvent('button', 'change');
    await Future.delayed(Duration(milliseconds: 20));
  }

  await Future.delayed(Duration(milliseconds: 200));
  print('Final button press count: ${buttonRuntime.getState('button_presses')}');
  await buttonRuntime.stop();

  // Run the sensor monitor example
  print('\n=== Sensor Monitor Example ===');
  final sensorRuntime = McpFlowRuntime();
  await sensorRuntime.loadFlow(sensorMonitorFlow);
  await sensorRuntime.start();

  // Monitor alerts
  sensorRuntime.getChannelStream('alerts')?.listen((alert) {
    print('ALERT: High temperature detected - ${alert['value']}°C at ${alert['time']}');
  });

  // Simulate temperature fluctuations
  print('Simulating temperature changes...');
  
  // Rapid fluctuations (will be debounced)
  for (int i = 0; i < 5; i++) {
    await sensorRuntime.setState('temperature', 25.0 + i);
    await Future.delayed(Duration(milliseconds: 500));
  }
  
  // Stable high temperature
  await sensorRuntime.setState('temperature', 35.0);
  print('Set temperature to 35°C');
  
  // Wait for debounce
  await Future.delayed(Duration(seconds: 6));
  
  // Return to normal
  await sensorRuntime.setState('temperature', 22.0);
  print('Set temperature to 22°C');
  
  await Future.delayed(Duration(seconds: 2));
  await sensorRuntime.stop();

  // Run the search handler example
  print('\n=== Search Handler Example ===');
  final searchRuntime = McpFlowRuntime();
  await searchRuntime.loadFlow(searchHandlerFlow);
  await searchRuntime.start();

  // Monitor search results
  searchRuntime.stateEventBus.on<StateChangeEvent>().listen((event) {
    if (event.variable == 'search_results' && event.newValue is List && event.newValue.isNotEmpty) {
      print('Search results: ${event.newValue}');
    }
  });

  // Simulate typing
  print('Simulating user typing...');
  final searchText = 'flutter';
  for (int i = 1; i <= searchText.length; i++) {
    await searchRuntime.setState('search_query', searchText.substring(0, i));
    await Future.delayed(Duration(milliseconds: 100));
  }

  // Wait for debounced search to complete
  await Future.delayed(Duration(seconds: 1));
  
  await searchRuntime.stop();
  
  print('\nDebounce examples completed!');
}