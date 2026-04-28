# MCP Flow Runtime

A declarative runtime for hardware control and IoT orchestration using the MCP Flow DSL. Provides a complete environment for executing hardware control flows with process orchestration, state management, and pluggable hardware providers.

## Features

- **Hardware Abstraction Layer** — cross-platform GPIO, I2C, SPI, PWM, UART, ADC, MQTT, Modbus.
- **Platform providers** — Linux (GPIO / I2C / SPI), Windows GPIO, MQTT, plus mock providers for tests.
- **Process orchestration** — concurrent process execution with scheduler, watchdog, circuit breaker, backup manager.
- **State management** — type-safe state with in-memory and encrypted persistent stores, change notifications.
- **Channels** — inter-process messaging with queue and pub/sub patterns.
- **Compact compiler / executor / loader** — compiled flow representation for faster restart and embedded deployment.
- **Expression engine** — dynamic values and conditions in flow definitions.
- **Bundle integration** — load flows from MCP bundles.
- **Security** — flow signing and encrypted state.
- **Logging / monitoring** — structured runtime telemetry.
- **MCP integration** — expose flows as MCP tools/resources.

## Quick Start

```dart
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

final runtime = FlowRuntime();
await runtime.loadFromJson(flowDefinitionJson);
await runtime.start();
```

Examples in `example/`:

- `led_blink.dart`
- `modbus_control.dart`
- `sensor_logger.dart`
- `temperature_monitor.dart`
- `multiple_triggers_example.dart`
- `trigger_debounce_example.dart`

## Support

- [Issue Tracker](https://github.com/app-appplayer/mcp_flow_runtime/issues)
- [Discussions](https://github.com/app-appplayer/mcp_flow_runtime/discussions)

## License

MIT — see [LICENSE](LICENSE).
