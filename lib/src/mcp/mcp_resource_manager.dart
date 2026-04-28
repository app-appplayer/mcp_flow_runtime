/// MCP Resource Manager - Resource exposure framework for MCP Flow Runtime
///
/// Exposes hardware states and flow data as MCP resources.
import 'dart:async';

import 'package:logging/logging.dart';

import '../types/flow_types.dart';

/// Callback type for resource content providers.
typedef ResourceContentProvider = Future<dynamic> Function();

/// Manages MCP resource registration, reading, and subscriptions.
///
/// Standard resource URIs:
/// - `runtime://info` - Runtime information
/// - `runtime://config` - Runtime configuration
/// - `devices://list` - Device list
/// - `devices://{deviceId}/status` - Individual device status
/// - `processes://list` - Process list
/// - `processes://{processId}/status` - Individual process status
/// - `system://metrics` - System metrics
/// - `system://logs` - System logs
/// - `system://health` - System health
/// - `system://errors` - System errors
/// - `state://*` - State variables
class McpResourceManager {
  final Logger _logger = Logger('McpResourceManager');
  final Map<String, McpResource> _resources = {};
  final Map<String, ResourceContentProvider> _contentProviders = {};
  final Map<String, StreamController<dynamic>> _subscriptionControllers = {};

  /// Register a resource.
  void registerResource(McpResource resource, {ResourceContentProvider? contentProvider}) {
    if (_resources.containsKey(resource.uri)) {
      _logger.warning('Resource "${resource.uri}" already registered, replacing');
    }
    _resources[resource.uri] = resource;
    if (contentProvider != null) {
      _contentProviders[resource.uri] = contentProvider;
    }
    _logger.info('Registered resource: ${resource.uri}');
  }

  /// Unregister a resource by URI.
  void unregisterResource(String uri) {
    if (_resources.remove(uri) != null) {
      _contentProviders.remove(uri);
      final controller = _subscriptionControllers.remove(uri);
      controller?.close();
      _logger.info('Unregistered resource: $uri');
    } else {
      _logger.warning('Resource "$uri" not found for unregistration');
    }
  }

  /// List all registered resources.
  List<McpResource> listResources() {
    return List<McpResource>.unmodifiable(_resources.values);
  }

  /// Read resource content by URI.
  ///
  /// If a content provider is registered, it is invoked to get fresh data.
  /// Otherwise, the static content from the resource definition is returned.
  /// Throws [ArgumentError] if the resource is not found.
  Future<dynamic> readResource(String uri) async {
    final resource = _resources[uri];
    if (resource == null) {
      _logger.severe('Resource "$uri" not found');
      throw ArgumentError('Resource "$uri" not found');
    }

    final provider = _contentProviders[uri];
    if (provider != null) {
      _logger.fine('Reading resource via provider: $uri');
      return provider();
    }

    _logger.fine('Reading static resource: $uri');
    return resource.content;
  }

  /// Subscribe to resource changes.
  ///
  /// Returns a [StreamSubscription] that delivers updates for the given resource URI.
  /// Throws [ArgumentError] if the resource is not found.
  StreamSubscription<dynamic> subscribeResource(String uri, Function callback) {
    if (!_resources.containsKey(uri)) {
      _logger.severe('Resource "$uri" not found for subscription');
      throw ArgumentError('Resource "$uri" not found');
    }

    final controller = _subscriptionControllers.putIfAbsent(
      uri,
      () => StreamController<dynamic>.broadcast(),
    );

    _logger.info('New subscription for resource: $uri');
    return controller.stream.listen((data) => callback(data));
  }

  /// Notify subscribers of a resource update.
  void notifyChange(String uri, dynamic data) {
    final controller = _subscriptionControllers[uri];
    if (controller != null && !controller.isClosed) {
      controller.add(data);
      _logger.fine('Notified subscribers of change to: $uri');
    }
  }

  /// Check if a resource is registered.
  bool hasResource(String uri) => _resources.containsKey(uri);

  /// Get a resource by URI, or null if not found.
  McpResource? getResource(String uri) => _resources[uri];

  /// Auto-register resources from a flow definition.
  ///
  /// Registers resources that have `mcp.expose: true` in their definition,
  /// as well as standard runtime resources.
  void registerResourcesFromFlow(FlowDefinition flow) {
    // Register resources with MCP bindings
    for (final entry in flow.resources.entries) {
      final resourceDef = entry.value;
      if (resourceDef.mcp != null && resourceDef.mcp!.expose) {
        final mcpInfo = resourceDef.mcp!.resource;
        if (mcpInfo != null) {
          registerResource(McpResource(
            name: mcpInfo.name,
            uri: mcpInfo.uri,
            mimeType: mcpInfo.mimeType,
          ));
        }
      }
    }

    // Register resources from MCP config
    final mcpConfig = flow.configuration?.mcp;
    if (mcpConfig != null && mcpConfig.resources != null) {
      for (final resource in mcpConfig.resources!) {
        registerResource(resource);
      }
    }
  }

  /// Register standard runtime resources (stubs).
  void registerStandardResources() {
    final standardResources = [
      const McpResource(
        name: 'Runtime Information',
        uri: 'runtime://info',
        mimeType: 'application/json',
        description: 'Real-time runtime information',
      ),
      const McpResource(
        name: 'Runtime Configuration',
        uri: 'runtime://config',
        mimeType: 'application/json',
        description: 'Current runtime configuration',
      ),
      const McpResource(
        name: 'Device List',
        uri: 'devices://list',
        mimeType: 'application/json',
        description: 'List of all available devices',
      ),
      const McpResource(
        name: 'Process List',
        uri: 'processes://list',
        mimeType: 'application/json',
        description: 'List of all processes',
      ),
      const McpResource(
        name: 'System Metrics',
        uri: 'system://metrics',
        mimeType: 'application/json',
        description: 'System performance metrics',
      ),
      const McpResource(
        name: 'System Logs',
        uri: 'system://logs',
        mimeType: 'application/json',
        description: 'System log stream',
      ),
      const McpResource(
        name: 'System Health',
        uri: 'system://health',
        mimeType: 'application/json',
        description: 'System health status',
      ),
      const McpResource(
        name: 'System Errors',
        uri: 'system://errors',
        mimeType: 'application/json',
        description: 'System error log',
      ),
    ];

    for (final resource in standardResources) {
      registerResource(resource);
    }
  }

  /// Remove all registered resources and close subscriptions.
  void clear() {
    for (final controller in _subscriptionControllers.values) {
      controller.close();
    }
    _subscriptionControllers.clear();
    _contentProviders.clear();
    _resources.clear();
    _logger.info('All resources cleared');
  }
}
