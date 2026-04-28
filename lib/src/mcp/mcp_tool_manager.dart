/// MCP Tool Manager - Tool exposure framework for MCP Flow Runtime
///
/// Registers flow processes as MCP tools and manages tool lifecycle.
import 'dart:async';

import 'package:logging/logging.dart';

import '../types/flow_types.dart';

/// Manages MCP tool registration, lookup, and execution.
///
/// Processes marked with `mcp.expose: true` in flow definitions
/// are automatically registered as MCP tools.
class McpToolManager {
  final Logger _logger = Logger('McpToolManager');
  final Map<String, McpTool> _tools = {};

  /// Register a tool.
  void registerTool(McpTool tool) {
    if (_tools.containsKey(tool.name)) {
      _logger.warning('Tool "${tool.name}" already registered, replacing');
    }
    _tools[tool.name] = tool;
    _logger.info('Registered tool: ${tool.name}');
  }

  /// Unregister a tool by name.
  void unregisterTool(String name) {
    if (_tools.remove(name) != null) {
      _logger.info('Unregistered tool: $name');
    } else {
      _logger.warning('Tool "$name" not found for unregistration');
    }
  }

  /// List all registered tools.
  List<McpTool> listTools() {
    return List<McpTool>.unmodifiable(_tools.values);
  }

  /// Execute a tool by name with the given parameters.
  ///
  /// Throws [ArgumentError] if the tool is not found.
  /// Throws [StateError] if the tool has no handler.
  Future<dynamic> callTool(String name, Map<String, dynamic> params) async {
    final tool = _tools[name];
    if (tool == null) {
      _logger.severe('Tool "$name" not found');
      throw ArgumentError('Tool "$name" not found');
    }

    if (tool.handler == null) {
      _logger.severe('Tool "$name" has no handler');
      throw StateError('Tool "$name" has no handler (stub only)');
    }

    _logger.fine('Calling tool: $name');
    return tool.handler!(params);
  }

  /// Check if a tool is registered.
  bool hasTool(String name) => _tools.containsKey(name);

  /// Get a tool by name, or null if not found.
  McpTool? getTool(String name) => _tools[name];

  /// Auto-expose processes from a flow definition that have MCP tool bindings.
  ///
  /// Scans the flow definition's configuration for MCP tools and registers them.
  void registerToolsFromFlow(FlowDefinition flow) {
    final mcpConfig = flow.configuration?.mcp;
    if (mcpConfig == null) {
      return;
    }

    final tools = mcpConfig.tools;
    if (tools != null) {
      for (final tool in tools) {
        registerTool(tool);
      }
    }
  }

  /// Remove all registered tools.
  void clear() {
    _tools.clear();
    _logger.info('All tools cleared');
  }
}
