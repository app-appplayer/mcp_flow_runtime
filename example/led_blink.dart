import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Example: Blink an LED connected to GPIO pin 13
void main() async {
  // Create runtime
  final runtime = McpFlowRuntime();
  
  // Define flow for LED blinking
  final flowDefinition = {
    'version': '1.0.0',
    'metadata': {
      'name': 'LED Blink Example',
      'description': 'Blinks an LED connected to GPIO pin 13',
      'author': 'MCP Flow Examples',
    },
    'resources': {
      'led_pin': {
        'type': 'gpio',
        'config': {
          'pin': 13,
          'mode': 'output',
          'initial': false
        }
      }
    },
    'state': {
      'led_state': {
        'type': 'boolean',
        'initial': false,
        'persistent': false
      },
      'blink_count': {
        'type': 'number',
        'initial': 0,
        'persistent': true
      }
    },
    'processes': [
      {
        'id': 'led_blinker',
        'name': 'LED Blink Process',
        'description': 'Toggles LED state every second',
        'enabled': true,
        'trigger': {
          'type': 'startup'
        },
        'loop': true,
        'priority': 'normal',
        'steps': [
          // Toggle LED state
          {
            'action': 'setState',
            'params': {
              'variable': 'led_state',
              'value': '=!led_state'
            }
          },
          // Write to GPIO
          {
            'action': 'gpio.write',
            'params': {
              'pin': 13,
              'value': '=led_state'
            }
          },
          // Increment counter
          {
            'action': 'setState',
            'params': {
              'variable': 'blink_count',
              'value': '=blink_count + 1'
            }
          },
          // Log status
          {
            'action': 'log',
            'params': {
              'message': 'LED toggled',
              'level': 'info'
            }
          },
          // Wait 1 second
          {
            'action': 'delay',
            'params': {
              'ms': 1000
            }
          }
        ],
        'error': [
          {
            'action': 'log',
            'params': {
              'message': 'Error in LED blink process',
              'level': 'error'
            }
          }
        ]
      }
    ]
  };
  
  try {
    // Load the flow
    print('Loading flow definition...');
    await runtime.loadFlow(flowDefinition);
    
    // Start the runtime
    print('Starting runtime...');
    await runtime.start();
    
    print('LED blinking started. Press Ctrl+C to stop.');
    
    // Keep running until interrupted
    await Future.delayed(const Duration(seconds: 30));
    
    // Get final blink count
    final blinkCount = runtime.getState('blink_count');
    print('Total blinks: $blinkCount');
    
    // Stop the runtime
    await runtime.stop();
    print('Runtime stopped.');
  } catch (e) {
    print('Error: $e');
  }
}