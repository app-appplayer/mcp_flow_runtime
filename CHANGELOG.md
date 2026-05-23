# Changelog

## [0.2.1] - 2026-05-23 - mcp_bundle 0.4.0 cascade

### Changed (cascade)
- `mcp_bundle` caret bumped from `^0.3.0` to `^0.4.0`. mcp_flow_runtime does not touch `UiSection.pages` directly, so this release is a caret-only cascade. Consumers should bump to `^0.2.1`.

## [0.2.0] - 2026-04-28 - Platform Providers, Compact Runtime, Bundle Integration

### Added
- Real-platform HAL providers — Linux GPIO / I2C / SPI, Windows GPIO, MQTT, alongside the existing mock factory.
- Compact flow subsystem — compiler, loader, executor, and types for embedded / restart-friendly deployment.
- Process resilience — watchdog, circuit breaker, backup manager.
- Channels subsystem and inter-process messaging primitives.
- Expression engine module.
- Encrypted state store (alongside in-memory and persistent stores).
- Bundle integration — load flows from MCP bundles.
- Logging, monitoring, network, resources, security, and services modules.
- MCP integration — flows exposed as MCP tools/resources.
- Examples — multiple-triggers and trigger-debounce flows.

### Changed
- Runtime / scheduler / process executor / action executor refactored around the new compact runtime and HAL.
- New dependency: `mcp_bundle ^0.3.0`.
- License changed from Apache-2.0 to MIT.

---

## 0.1.0

- Initial release
- Core runtime engine with process scheduling
- Hardware Abstraction Layer (HAL) with mock providers
- Support for GPIO, I2C, SPI, PWM, UART, ADC, and Modbus
- State management with persistence options
- JSON parser and validator for Flow DSL
- Comprehensive error handling and retry mechanisms
- Support for all control flow actions (if, while, for, switch, parallel)
- Channel-based inter-process communication
- Expression evaluation support
- File I/O and HTTP request actions
