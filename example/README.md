# MCP Flow Runtime Examples

This directory contains example flows demonstrating various capabilities of the MCP Flow Runtime.

## Running Examples

Each example can be run directly using Dart:

```bash
dart run example/led_blink.dart
```

## Available Examples

### [led_blink.dart](led_blink.dart)
Simple GPIO control example that blinks an LED connected to pin 13.

**Demonstrates:**
- GPIO output control
- State management
- Process loops
- Delays between actions
- Error handling

### [temperature_monitor.dart](temperature_monitor.dart)
Advanced example that monitors temperature from an I2C sensor and controls a cooling fan based on temperature thresholds.

**Demonstrates:**
- I2C sensor reading
- PWM fan control
- Conditional logic (if/else)
- State constraints
- Channel-based communication
- Event monitoring

### [sensor_logger.dart](sensor_logger.dart)
Logs sensor data to a CSV file and calculates running statistics.

**Demonstrates:**
- ADC sensor reading
- File I/O operations
- Expression evaluation
- Channel pub/sub pattern
- Scheduled processes
- Statistics calculation

### [modbus_control.dart](modbus_control.dart)
Industrial control example using Modbus protocol to control pumps and monitor tank levels.

**Demonstrates:**
- Modbus TCP/RTU communication
- Reading/writing Modbus registers
- Complex control logic
- Alarm handling
- Priority processes
- Emergency stop procedures

## Hardware Requirements

Most examples use mock hardware providers by default. To run with real hardware:

1. **Linux**: Install required drivers and ensure proper permissions
2. **macOS/Windows**: Use USB-to-GPIO/I2C/SPI adapters where needed

## Creating Your Own Flows

Use these examples as templates for your own flows. Key concepts:

1. **Resources**: Define hardware interfaces (GPIO, I2C, etc.)
2. **State**: Define variables with types and constraints
3. **Channels**: Define communication channels between processes
4. **Processes**: Define the control logic with triggers and steps

See the [MCP Flow DSL Specification](https://github.com/makemind/mcp_flow_dsl/blob/main/specification/MCP_Flow_DSL_v1.0_Specification.md) for complete documentation.