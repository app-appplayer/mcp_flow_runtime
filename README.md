# MCP Flow Runtime

## 🙌 Support This Project

If you find this package useful, consider supporting ongoing development on PayPal.

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/ncp/payment/F7G56QD9LSJ92)  
Support makemind via [PayPal](https://www.paypal.com/ncp/payment/F7G56QD9LSJ92)

---

### 🔗 MCP Dart Package Family

- [`mcp_server`](https://pub.dev/packages/mcp_server): Exposes tools, resources, and prompts to LLMs. Acts as the AI server.
- [`mcp_client`](https://pub.dev/packages/mcp_client): Connects Flutter/Dart apps to MCP servers. Acts as the client interface.
- [`mcp_llm`](https://pub.dev/packages/mcp_llm): Bridges LLMs (Claude, OpenAI, etc.) to MCP clients/servers. Acts as the LLM brain.
- [`flutter_mcp`](https://pub.dev/packages/flutter_mcp): Complete Flutter plugin for MCP integration with platform features.
- [`flutter_mcp_ui_core`](https://pub.dev/packages/flutter_mcp_ui_core): Core models, constants, and utilities for Flutter MCP UI system. 
- [`flutter_mcp_ui_runtime`](https://pub.dev/packages/flutter_mcp_ui_runtime): Comprehensive runtime for building dynamic, reactive UIs through JSON specifications. 
- [`flutter_mcp_ui_generator`](https://pub.dev/packages/flutter_mcp_ui_generator): JSON generation toolkit for creating UI definitions with templates and fluent API. 
- [`mcp_flow_runtime`](https://pub.dev/packages/mcp_flow_runtime): Declarative runtime for hardware control and IoT orchestration using MCP Flow DSL.

---

A declarative runtime for hardware control and IoT orchestration using the MCP (Model Context Protocol) Flow DSL v1.0 specification. This package provides a complete runtime environment for executing hardware control flows with process orchestration and state management.

📋 **Based on [MCP Flow DSL v1.0 Specification](https://github.com/app-appplayer/makemind/blob/main/doc/mcp_flow_dsl/specification/MCP_Flow_DSL_v1.0_Specification.md)** - The standard specification for Model Context Protocol Flow Definition Language.

## Features

- 🔌 **Hardware Abstraction Layer** - Cross-platform GPIO, I2C, SPI, PWM, UART, ADC, and Modbus support
- 🔄 **Process Orchestration** - Concurrent process execution with scheduling and synchronization
- 💾 **State Management** - Type-safe state with persistence options and change notifications
- 📡 **Channel Communication** - Inter-process messaging with queue and pub/sub patterns
- ⚡ **Expression Evaluation** - Dynamic values and conditions in flow definitions
- 🛡️ **Error Handling** - Comprehensive error recovery with retry strategies
- 🔧 **Extensible Architecture** - Easy to add custom actions and hardware providers
- 🧩 **MCP Protocol Ready** - Designed for AI-powered hardware control
- 📐 **Standardized Structure** - Follows MCP Flow DSL v1.0 specification

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  mcp_flow_runtime: ^0.1.0
```

## Quick Start

### Basic Usage

```dart
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

// Define your flow in JSON
final flowDefinition = {
  "version": "1.0.0",
  "metadata": {
    "name": "LED Blinker",
    "description": "Simple LED control example"
  },
  "resources": {
    "led": {
      "type": "gpio",
      "config": {
        "pin": 13,
        "mode": "output"
      }
    }
  },
  "state": {
    "led_state": {
      "type": "boolean",
      "initial": false
    }
  },
  "processes": [
    {
      "id": "blink",
      "trigger": {
        "type": "startup"
      },
      "loop": true,
      "steps": [
        {
          "action": "setState",
          "params": {
            "variable": "led_state",
            "value": "=!led_state"
          }
        },
        {
          "action": "gpioWrite",
          "params": {
            "pin": 13,
            "value": "=led_state"
          }
        },
        {
          "action": "delay",
          "params": {"ms": 1000}
        }
      ]
    }
  ]
};

// Create and start runtime
final runtime = McpFlowRuntime();
await runtime.loadFlow(flowDefinition);
await runtime.start();

// Monitor state changes
runtime.stateEventBus.on<StateChangeEvent>().listen((event) {
  print('${event.variable} changed to ${event.newValue}');
});

// Stop when done
await runtime.stop();
```

### Full Application Example

```dart
// Define a complete IoT monitoring system
final iotSystemDefinition = {
  "version": "1.0.0",
  "metadata": {
    "name": "IoT Monitoring System",
    "description": "Environmental monitoring with alerts"
  },
  "resources": {
    "temp_sensor": {
      "type": "i2c",
      "config": {"bus": 1, "address": 0x48}
    },
    "fan": {
      "type": "pwm",
      "config": {"channel": 0, "frequency": 25000}
    },
    "alert_led": {
      "type": "gpio",
      "config": {"pin": 22, "mode": "output"}
    }
  },
  "state": {
    "temperature": {"type": "number", "initial": 20.0},
    "fan_speed": {"type": "number", "initial": 0},
    "alert": {"type": "boolean", "initial": false}
  },
  "channels": {
    "sensor_data": {"type": "pubsub"},
    "alerts": {"type": "queue", "capacity": 100}
  },
  "processes": [
    {
      "id": "monitor",
      "trigger": {"type": "schedule", "interval": 5000},
      "steps": [
        {
          "action": "i2cRead",
          "params": {"bus": 1, "address": 0x48, "length": 2},
          "bindTo": "raw_temp"
        },
        {
          "action": "expression",
          "params": {"expression": "(raw_temp[0] * 256 + raw_temp[1]) / 100"},
          "bindTo": "temp_celsius"
        },
        {
          "action": "setState",
          "params": {"variable": "temperature", "value": "=temp_celsius"}
        },
        {
          "action": "channelSend",
          "params": {
            "channel": "sensor_data",
            "data": "={temp: temp_celsius, time: Date.now()}"
          }
        }
      ]
    },
    {
      "id": "control",
      "trigger": {"type": "stateChange", "variable": "temperature"},
      "steps": [
        {
          "action": "if",
          "params": {"condition": "temperature > 30"},
          "then": [
            {
              "action": "setState",
              "params": {"variable": "fan_speed", "value": 100}
            },
            {
              "action": "setState",
              "params": {"variable": "alert", "value": true}
            }
          ],
          "else": [
            {
              "action": "setState",
              "params": {"variable": "fan_speed", "value": "=temperature * 2"}
            },
            {
              "action": "setState",
              "params": {"variable": "alert", "value": false}
            }
          ]
        },
        {
          "action": "pwmWrite",
          "params": {"channel": 0, "dutyCycle": "=fan_speed / 100"}
        },
        {
          "action": "gpioWrite",
          "params": {"pin": 22, "value": "=alert"}
        }
      ]
    }
  ]
};

// Initialize and run the system
final runtime = McpFlowRuntime();
await runtime.loadFlow(iotSystemDefinition);
await runtime.start();

// Subscribe to sensor data
runtime.getChannelStream('sensor_data')?.listen((data) {
  print('Sensor: ${data['temp']}°C at ${data['time']}');
});

// Monitor alerts
runtime.getChannelStream('alerts')?.listen((alert) {
  print('ALERT: $alert');
});
```

## Supported Hardware (7+ Protocols)

The MCP Flow Runtime supports hardware control across multiple protocols:

### GPIO (General Purpose I/O)
- Digital input/output
- Pull-up/down resistors
- Interrupt detection
- Debouncing support

### I2C (Inter-Integrated Circuit)
- Multi-master support
- Clock stretching
- 7-bit and 10-bit addressing
- Block read/write operations

### SPI (Serial Peripheral Interface)
- Full duplex communication
- Multiple chip select
- Configurable clock modes
- Variable word sizes

### PWM (Pulse Width Modulation)
- Hardware PWM channels
- Software PWM fallback
- Frequency and duty cycle control
- Phase-correct modes

### UART (Serial Communication)
- Configurable baud rates
- Hardware flow control
- Parity and stop bits
- Break detection

### ADC (Analog to Digital)
- Multi-channel support
- Configurable resolution
- Sampling rate control
- Voltage reference options

### Modbus
- RTU and TCP modes
- Master/slave support
- Function codes 1-6, 15-16
- Exception handling

## Action System

### State Actions
```json
{
  "action": "setState",
  "params": {
    "variable": "counter",
    "value": 42
  }
}
```

### Hardware Actions
```json
{
  "action": "gpioWrite",
  "params": {
    "pin": 13,
    "value": true
  }
}
```

### Control Flow Actions
```json
{
  "action": "if",
  "params": {"condition": "temperature > 30"},
  "then": [
    {"action": "setState", "params": {"variable": "alert", "value": true}}
  ],
  "else": [
    {"action": "setState", "params": {"variable": "alert", "value": false}}
  ]
}
```

### Channel Actions
```json
{
  "action": "channelSend",
  "params": {
    "channel": "events",
    "data": "={type: 'sensor', value: temperature}"
  }
}
```

## Expression System

The runtime supports dynamic expressions for values and conditions:

### Supported Expressions

- **Variable access**: `=temperature`
- **Nested paths**: `=sensor.value`
- **Array indexing**: `=values[0]`
- **Arithmetic**: `=temperature * 1.8 + 32`
- **Comparison**: `=temperature > 30`
- **Boolean logic**: `=alert && temperature > 40`
- **Negation**: `=!led_state`

### Expression Context

All expressions have access to:
- State variables
- Process-local variables (from `bindTo`)
- Built-in functions (Date.now(), Math operations)

## Platform Support

| Platform | GPIO | I2C | SPI | PWM | UART | ADC | Modbus |
|----------|------|-----|-----|-----|------|-----|--------|
| Android  | ⚠️   | ⚠️  | ⚠️  | ⚠️  | ✅   | ⚠️  | ✅     |
| Linux    | ✅   | ✅  | ✅  | ✅  | ✅   | ✅  | ✅     |
| macOS    | ❌   | ⚠️  | ⚠️  | ❌  | ✅   | ❌  | ✅     |
| Windows  | ❌   | ⚠️  | ⚠️  | ❌  | ✅   | ❌  | ✅     |

✅ = Full support
⚠️ = Limited support (USB adapters, Android Things, or rooted devices)
❌ = Not supported

## Examples

Check out the `example/` directory for complete examples:

- **[LED Blink](example/led_blink.dart)** - Simple GPIO control example demonstrating:
  - GPIO output control
  - State management
  - Process loops with delays
  - Error handling

- **[Temperature Monitor](example/temperature_monitor.dart)** - Advanced sensor monitoring with:
  - I2C temperature sensor reading
  - PWM fan speed control based on temperature
  - Conditional logic and thresholds
  - State change event monitoring
  - Channel-based data streaming

- **[Sensor Logger](example/sensor_logger.dart)** - Data logging and statistics:
  - Multiple ADC sensor readings
  - CSV file logging with timestamps
  - Running statistics calculation
  - Channel-based pub/sub messaging
  - File I/O operations

- **[Modbus Control](example/modbus_control.dart)** - Industrial control example:
  - Modbus TCP/RTU communication
  - Reading holding registers, coils, and input registers
  - Writing control commands
  - Automatic pump control logic
  - Alarm handling and emergency stops
  - Real-time priority processes

## API Reference

### McpFlowRuntime

Main class for executing flow definitions.

```dart
class McpFlowRuntime {
  // Constructor with optional configuration
  McpFlowRuntime({RuntimeConfig? config, HardwareAbstractionLayer? hal});
  
  // Flow management
  Future<void> loadFlow(Map<String, dynamic> json);
  Future<void> loadFlowFromFile(String path);
  
  // Runtime control
  Future<void> start();
  Future<void> stop();
  RuntimeStatus get status;
  
  // State management
  dynamic getState(String name);
  Future<void> setState(String name, dynamic value);
  EventBus get stateEventBus;
  
  // Channel management
  Future<void> sendToChannel(String channelName, dynamic data);
  Stream? getChannelStream(String channelName);
  
  // Process control
  Future<void> executeProcess(String processId, {Map<String, dynamic>? args});
  
  // Monitoring
  RuntimeStatistics getStatistics();
  EventBus get eventBus;
}
```

### State Management

```dart
// Listen to state changes
runtime.stateEventBus.on<StateChangeEvent>().listen((event) {
  print('${event.variable}: ${event.oldValue} -> ${event.newValue}');
});

// Get state value
var temperature = runtime.getState('temperature');

// Set state value
await runtime.setState('fan_speed', 50);
```

### Channel Communication

```dart
// Send data to channel
await runtime.sendToChannel('sensor_data', {
  'temperature': 25.5,
  'humidity': 60,
  'timestamp': DateTime.now()
});

// Subscribe to channel
runtime.getChannelStream('sensor_data')?.listen((data) {
  print('Received: $data');
});
```

## Architecture

The package follows a modular architecture with these core components:

- **Runtime Engine**: Main orchestration and flow execution
- **HAL (Hardware Abstraction Layer)**: Platform-specific hardware interfaces
- **State Manager**: Type-safe state management with persistence
- **Process Scheduler**: Priority-based process scheduling
- **Process Executor**: Action execution engine
- **Expression Evaluator**: Dynamic expression evaluation
- **Channel Manager**: Inter-process communication

## Documentation

- [MCP Flow DSL v1.0 Specification](https://github.com/app-appplayer/makemind/blob/main/doc/mcp_flow_dsl/specification/MCP_Flow_DSL_v1.0_Specification.md) - Complete specification for Model Context Protocol Flow Definition Language
- [API Reference](https://pub.dev/documentation/mcp_flow_runtime/latest/) - Detailed API documentation
- [Hardware Setup Guide](https://github.com/app-appplayer/makemind/blob/main/doc/mcp_flow_dsl/guides/hardware-setup.md) - Platform-specific hardware configuration
- [Getting Started Guide](https://github.com/app-appplayer/makemind/blob/main/doc/mcp_flow_dsl/guides/getting-started.md) - Quick start guide
- [Examples](./example/) - Sample implementations

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

Made with ❤️ for the Dart and MCP communities.