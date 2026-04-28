/// MCP Flow Runtime - A declarative runtime for hardware control and IoT orchestration
library mcp_flow_runtime;

// Core runtime
export 'src/core/runtime.dart';
export 'src/core/scheduler.dart';
export 'src/core/process_executor.dart';
export 'src/core/action_executor.dart';

// Hardware Abstraction Layer
export 'src/hal/hal_interface.dart';
export 'src/hal/hal_factory.dart';

// State management
export 'src/state/state_manager.dart';
export 'src/state/state_store.dart';

// Parser
export 'src/parser/json_parser.dart';
export 'src/parser/validator.dart' hide ValidationSeverity, ValidationError;

// Common types
export 'src/types/flow_types.dart';
export 'src/types/runtime_types.dart';
export 'src/types/hardware_types.dart';

// Errors
export 'src/errors/flow_errors.dart';

// Expression
export 'src/expression/expression_evaluator.dart';
export 'src/expression/enhanced_evaluator.dart';

// Channels
export 'src/channels/channel_interface.dart';

// Security
export 'src/security/security_manager.dart' hide SecurityConfig;
export 'src/security/key_manager.dart';

// MCP
export 'src/mcp/client_capabilities.dart';
export 'src/mcp/mcp_integration.dart';
export 'src/mcp/mcp_tool_manager.dart';
export 'src/mcp/mcp_resource_manager.dart';
export 'src/mcp/mcp_event_notifier.dart';

// Monitoring
export 'src/monitoring/runtime_monitor.dart' hide StateChangeEvent;

// Resources
export 'src/resources/resource_pool.dart';

// Network
export 'src/network/tls_config.dart';

// Logging
export 'src/logging/log_rotator.dart';

// Utilities
export 'src/utils/stdio_guard.dart';
export 'src/utils/debounce.dart';

// Core extensions
export 'src/core/backup_manager.dart';
export 'src/core/circuit_breaker.dart';
export 'src/core/watchdog.dart';
export 'src/core/compact_compiler.dart';
export 'src/core/compact_loader.dart';
export 'src/core/compact_types.dart';
export 'src/core/compact_executor.dart';

// Services
export 'src/services/service_manager.dart';
export 'src/services/system_service_manager.dart' hide ServiceConfig, ServiceStatus, ServiceException, SystemdServiceManager, LaunchdServiceManager, WindowsServiceManager;
export 'src/services/system_service_registry.dart';

// State extensions
export 'src/state/encrypted_state_store.dart';

// Bundle adapters (v1.1)
export 'src/bundle/bundle_flow_adapter.dart';
export 'src/bundle/bundle_step_adapter.dart';
export 'src/bundle/bundle_flow_write_adapter.dart';