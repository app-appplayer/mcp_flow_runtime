import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'package:mcp_flow_runtime/src/hal/mock_hal_factory.dart';

void main() {
  group('ResourceEvent Trigger Tests', () {
    late McpFlowRuntime runtime;
    late MockHardwareAbstractionLayer mockHal;
    
    setUp(() async {
      mockHal = MockHalFactory.createMockHal() as MockHardwareAbstractionLayer;
      runtime = McpFlowRuntime(hal: mockHal);
    });

    tearDown(() async {
      await runtime.stop();
    });

    test('should trigger process on GPIO pin state change', () async {
      final flow = {
        'version': '1.0.0',
        'resources': {
          'button': {
            'type': 'gpio',
            'capabilities': ['read', 'interrupt'],
            'config': {
              'pin': 10,
              'mode': 'input',
              'interrupt': 'both'
            }
          }
        },
        'state': {
          'buttonPressCount': {
            'type': 'number',
            'initial': 0
          }
        },
        'processes': [
          {
            'id': 'buttonHandler',
            'name': 'Button Press Handler',
            'trigger': {
              'type': 'resourceEvent',
              'resource': 'gpio_10',
              'event': 'high'
            },
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'buttonPressCount',
                  'value': '= buttonPressCount + 1'
                }
              }
            ]
          }
        ]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Initial count should be 0
      expect(runtime.getState('buttonPressCount'), equals(0));
      
      // Get the mock GPIO provider
      final gpioProvider = mockHal.getProvider<GpioProvider>(ResourceType.gpio) as MockGpioProvider;
      
      // Simulate button press (pin goes high)
      gpioProvider.simulatePinChange(10, true);
      
      // Wait for event processing
      await Future.delayed(Duration(milliseconds: 100));
      
      // Count should have increased
      expect(runtime.getState('buttonPressCount'), equals(1));
      
      // Simulate another button press
      gpioProvider.simulatePinChange(10, false); // First go low
      await Future.delayed(Duration(milliseconds: 50));
      gpioProvider.simulatePinChange(10, true); // Then go high again
      
      // Wait for event processing
      await Future.delayed(Duration(milliseconds: 100));
      
      // Count should have increased again
      expect(runtime.getState('buttonPressCount'), equals(2));
    });

    test('should handle multiple resource events with debouncing', () async {
      final flow = {
        'version': '1.0.0',
        'resources': {
          'sensor': {
            'type': 'gpio',
            'capabilities': ['read', 'interrupt'],
            'config': {
              'pin': 5,
              'mode': 'input'
            }
          }
        },
        'state': {
          'sensorEvents': {
            'type': 'number',
            'initial': 0
          }
        },
        'processes': [
          {
            'id': 'sensorHandler',
            'name': 'Sensor Event Handler',
            'trigger': {
              'type': 'resourceEvent',
              'resource': 'gpio_5',
              'event': 'high',
              'debounceMs': 200
            },
            'steps': [
              {
                'action': 'stateSet',
                'params': {
                  'key': 'sensorEvents',
                  'value': '= sensorEvents + 1'
                }
              }
            ]
          }
        ]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      expect(runtime.getState('sensorEvents'), equals(0));
      
      // Get the mock GPIO provider
      final gpioProvider = mockHal.getProvider<GpioProvider>(ResourceType.gpio) as MockGpioProvider;
      
      // Simulate rapid sensor events (should be debounced)
      for (int i = 0; i < 5; i++) {
        gpioProvider.simulatePinChange(5, true);
        await Future.delayed(Duration(milliseconds: 50));
        gpioProvider.simulatePinChange(5, false);
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      // Wait for debounce period to expire
      await Future.delayed(Duration(milliseconds: 300));
      
      // Should only have triggered once due to debouncing
      expect(runtime.getState('sensorEvents'), equals(1));
    });
  });
}