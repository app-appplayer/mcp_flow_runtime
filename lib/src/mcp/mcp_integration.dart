/// MCP Integration - Main integration facade for MCP Flow Runtime
///
/// Combines tool manager, resource manager, event notifier, and
/// client capabilities into a single entry point per Spec 10.
import 'package:logging/logging.dart';

import '../types/flow_types.dart';
import 'client_capabilities.dart';
import 'mcp_event_notifier.dart';
import 'mcp_resource_manager.dart';
import 'mcp_tool_manager.dart';

/// Main facade that integrates all MCP subsystems.
///
/// Provides a unified interface for:
/// - Tool exposure (Spec 10.1)
/// - Resource exposure (Spec 10.2)
/// - Event notifications (Spec 10.3)
/// - Client capability detection
/// - Standard MCP tools and resources (Spec 10.5, 10.7)
class McpIntegration {
  final Logger _logger = Logger('McpIntegration');

  /// Tool manager for registering and executing MCP tools.
  final McpToolManager toolManager;

  /// Resource manager for exposing hardware states and flow data.
  final McpResourceManager resourceManager;

  /// Event notifier for sending notifications to MCP clients.
  final McpEventNotifier eventNotifier;

  /// Client capability detector.
  final ClientCapabilityDetector capabilityDetector;

  bool _initialized = false;

  McpIntegration({
    McpToolManager? toolManager,
    McpResourceManager? resourceManager,
    McpEventNotifier? eventNotifier,
    ClientCapabilityDetector? capabilityDetector,
  })  : toolManager = toolManager ?? McpToolManager(),
        resourceManager = resourceManager ?? McpResourceManager(),
        capabilityDetector = capabilityDetector ?? ClientCapabilityDetector(),
        eventNotifier = eventNotifier ??
            McpEventNotifier(
              capabilityDetector: capabilityDetector ?? ClientCapabilityDetector(),
            );

  /// Whether the integration has been initialized.
  bool get isInitialized => _initialized;

  /// Initialize the MCP integration from a flow definition.
  ///
  /// Auto-registers tools and resources from the flow definition,
  /// then registers all standard MCP tools and resources.
  void initialize(FlowDefinition flow) {
    if (_initialized) {
      _logger.warning('McpIntegration already initialized, re-initializing');
      _cleanup();
    }

    _logger.info('Initializing MCP integration');

    // Register tools and resources from flow definition
    toolManager.registerToolsFromFlow(flow);
    resourceManager.registerResourcesFromFlow(flow);

    // Register standard tools and resources
    _registerStandardTools();
    resourceManager.registerStandardResources();

    // Register UI resources if UI definitions are present
    _registerUiResources(flow);

    _initialized = true;
    _logger.info('MCP integration initialized');
  }

  /// Dispose of all MCP integration resources.
  void dispose() {
    _cleanup();
    eventNotifier.dispose();
    _initialized = false;
    _logger.info('MCP integration disposed');
  }

  /// Internal cleanup without disposing the event notifier.
  void _cleanup() {
    toolManager.clear();
    resourceManager.clear();
  }

  /// Register all standard MCP tools as stubs per Spec 10.5.
  void _registerStandardTools() {
    final standardTools = <McpTool>[
      // Runtime management tools (Spec 10.5.1)
      const McpTool(
        name: 'runtimeGetInfo',
        description: 'Get runtime information and status',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      const McpTool(
        name: 'runtimeGetConfig',
        description: 'Get runtime configuration',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      const McpTool(
        name: 'runtimeSetConfig',
        description: 'Update runtime configuration',
        inputSchema: {
          'type': 'object',
          'properties': {
            'tickRateMs': {'type': 'number', 'minimum': 1},
            'maxProcesses': {'type': 'number', 'minimum': 1},
            'maxMemoryKB': {'type': 'number', 'minimum': 1},
            'watchdogMs': {'type': 'number', 'minimum': 100},
          },
        },
      ),
      const McpTool(
        name: 'runtimeRestart',
        description: 'Restart the runtime',
        inputSchema: {
          'type': 'object',
          'properties': {
            'graceful': {'type': 'boolean', 'default': true},
            'timeout': {'type': 'number', 'default': 5000},
          },
        },
      ),
      const McpTool(
        name: 'runtimeGetStats',
        description: 'Get runtime statistics',
        inputSchema: {'type': 'object', 'properties': {}},
      ),

      // Device management tools (Spec 10.5.2)
      const McpTool(
        name: 'deviceList',
        description: 'List all available hardware devices',
        inputSchema: {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['gpio', 'i2c', 'spi', 'pwm', 'uart', 'adc', 'dac'],
            },
          },
        },
      ),
      const McpTool(
        name: 'deviceGetInfo',
        description: 'Get device information',
        inputSchema: {
          'type': 'object',
          'properties': {
            'deviceId': {'type': 'string'},
          },
          'required': ['deviceId'],
        },
      ),
      const McpTool(
        name: 'deviceConfigure',
        description: 'Configure a hardware device',
        inputSchema: {
          'type': 'object',
          'properties': {
            'deviceId': {'type': 'string'},
            'config': {'type': 'object'},
          },
          'required': ['deviceId', 'config'],
        },
      ),

      // Process management tools (Spec 10.5.3)
      const McpTool(
        name: 'processList',
        description: 'List all processes',
        inputSchema: {
          'type': 'object',
          'properties': {
            'filter': {
              'type': 'object',
              'properties': {
                'status': {
                  'type': 'string',
                  'enum': ['idle', 'ready', 'running', 'waiting', 'completed', 'error'],
                },
              },
            },
          },
        },
      ),
      const McpTool(
        name: 'processGetStatus',
        description: 'Get detailed process status',
        inputSchema: {
          'type': 'object',
          'properties': {
            'processId': {'type': 'string'},
          },
          'required': ['processId'],
        },
      ),
      const McpTool(
        name: 'processStart',
        description: 'Start a process',
        inputSchema: {
          'type': 'object',
          'properties': {
            'processId': {'type': 'string'},
            'args': {'type': 'object'},
          },
          'required': ['processId'],
        },
      ),
      const McpTool(
        name: 'processStop',
        description: 'Stop a running process',
        inputSchema: {
          'type': 'object',
          'properties': {
            'processId': {'type': 'string'},
            'force': {'type': 'boolean', 'default': false},
          },
          'required': ['processId'],
        },
      ),
      const McpTool(
        name: 'processDebug',
        description: 'Enable/disable debug mode for a process',
        inputSchema: {
          'type': 'object',
          'properties': {
            'processId': {'type': 'string'},
            'enabled': {'type': 'boolean'},
            'breakpoints': {
              'type': 'array',
              'items': {'type': 'number'},
            },
            'traceLevel': {
              'type': 'string',
              'enum': ['none', 'basic', 'verbose'],
            },
          },
          'required': ['processId', 'enabled'],
        },
      ),

      // System management tools (Spec 10.5.4)
      const McpTool(
        name: 'systemGetLogs',
        description: 'Get system logs',
        inputSchema: {
          'type': 'object',
          'properties': {
            'level': {
              'type': 'string',
              'enum': ['debug', 'info', 'warn', 'error'],
            },
            'category': {'type': 'string'},
            'since': {'type': 'string', 'format': 'date-time'},
            'limit': {'type': 'number', 'default': 100},
          },
        },
      ),
      const McpTool(
        name: 'systemStreamLogs',
        description: 'Stream live system logs',
        inputSchema: {
          'type': 'object',
          'properties': {
            'level': {
              'type': 'string',
              'enum': ['debug', 'info', 'warn', 'error'],
            },
            'category': {'type': 'string'},
            'follow': {'type': 'boolean', 'default': true},
          },
        },
      ),
      const McpTool(
        name: 'systemSetLogLevel',
        description: 'Set minimum log level',
        inputSchema: {
          'type': 'object',
          'properties': {
            'level': {
              'type': 'string',
              'enum': ['debug', 'info', 'warn', 'error'],
            },
            'category': {'type': 'string'},
          },
          'required': ['level'],
        },
      ),
      const McpTool(
        name: 'systemGetMetrics',
        description: 'Get system performance metrics',
        inputSchema: {
          'type': 'object',
          'properties': {
            'category': {
              'type': 'string',
              'enum': ['cpu', 'memory', 'io', 'network', 'all'],
            },
          },
        },
      ),
      const McpTool(
        name: 'systemHealth',
        description: 'Perform system health check',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      const McpTool(
        name: 'systemGetBootConfig',
        description: 'Get system boot configuration',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      const McpTool(
        name: 'systemSetBootConfig',
        description: 'Update system boot configuration',
        inputSchema: {
          'type': 'object',
          'properties': {
            'boot': {'type': 'object'},
            'autoStart': {'type': 'object'},
          },
        },
      ),
      const McpTool(
        name: 'systemEnableAutoStart',
        description: 'Enable auto-start for a process',
        inputSchema: {
          'type': 'object',
          'properties': {
            'processId': {'type': 'string'},
            'priority': {'type': 'number', 'default': 10},
            'critical': {'type': 'boolean', 'default': false},
          },
          'required': ['processId'],
        },
      ),
      const McpTool(
        name: 'systemDisableAutoStart',
        description: 'Disable auto-start for a process',
        inputSchema: {
          'type': 'object',
          'properties': {
            'processId': {'type': 'string'},
          },
          'required': ['processId'],
        },
      ),
      const McpTool(
        name: 'systemInstallService',
        description: 'Install runtime as system service',
        inputSchema: {
          'type': 'object',
          'properties': {
            'serviceName': {'type': 'string', 'default': 'mcp-flow-runtime'},
            'serviceType': {
              'type': 'string',
              'enum': ['systemd', 'init.d', 'openrc'],
            },
            'autoStart': {'type': 'boolean', 'default': true},
          },
        },
      ),
      const McpTool(
        name: 'systemUninstallService',
        description: 'Uninstall system service',
        inputSchema: {
          'type': 'object',
          'properties': {
            'serviceName': {'type': 'string', 'default': 'mcp-flow-runtime'},
          },
        },
      ),

      // Flow management tools (Spec 10.5.5)
      const McpTool(
        name: 'flowLoad',
        description: 'Load a new flow definition',
        inputSchema: {
          'type': 'object',
          'properties': {
            'definition': {'type': 'object'},
            'validate': {'type': 'boolean', 'default': true},
          },
          'required': ['definition'],
        },
      ),
      const McpTool(
        name: 'flowValidate',
        description: 'Validate a flow definition',
        inputSchema: {
          'type': 'object',
          'properties': {
            'definition': {'type': 'object'},
          },
          'required': ['definition'],
        },
      ),
      const McpTool(
        name: 'flowGetDefinition',
        description: 'Get current flow definition',
        inputSchema: {
          'type': 'object',
          'properties': {
            'includeRuntime': {'type': 'boolean', 'default': false},
          },
        },
      ),

      // UI management tools (Spec 10.5 UI Integration)
      const McpTool(
        name: 'uiList',
        description: 'List all available UI definitions',
        inputSchema: {'type': 'object', 'properties': {}},
      ),
      const McpTool(
        name: 'uiRegister',
        description: 'Register a new UI definition',
        inputSchema: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'definition': {'type': 'object'},
          },
          'required': ['id', 'definition'],
        },
      ),
      const McpTool(
        name: 'uiUpdate',
        description: 'Update an existing UI definition',
        inputSchema: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'definition': {'type': 'object'},
          },
          'required': ['id', 'definition'],
        },
      ),
      const McpTool(
        name: 'uiRemove',
        description: 'Remove a UI definition',
        inputSchema: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
          },
          'required': ['id'],
        },
      ),
    ];

    for (final tool in standardTools) {
      toolManager.registerTool(tool);
    }

    _logger.info('Registered ${standardTools.length} standard MCP tools');
  }

  /// Register UI definitions as MCP resources per Spec 10.5.2.
  void _registerUiResources(FlowDefinition flow) {
    final uiDefs = flow.uiDefinitions;
    if (uiDefs == null || uiDefs.isEmpty) {
      return;
    }

    // Register individual UI resources
    for (final entry in uiDefs.entries) {
      final uiId = entry.key;
      final uiDef = entry.value;

      String uiName = uiId;
      if (uiDef is Map<String, dynamic>) {
        final metadata = uiDef['metadata'] as Map<String, dynamic>?;
        if (metadata != null && metadata['name'] is String) {
          uiName = metadata['name'] as String;
        }
      }

      resourceManager.registerResource(McpResource(
        name: uiName,
        uri: 'ui://$uiId',
        mimeType: 'application/json',
        description: 'UI DSL definition',
      ));
    }

    // Register UI list resource
    resourceManager.registerResource(const McpResource(
      name: 'UI List',
      uri: 'ui://list',
      mimeType: 'application/json',
      description: 'List of all available UIs',
    ));

    _logger.info('Registered ${uiDefs.length} UI resources');
  }
}
