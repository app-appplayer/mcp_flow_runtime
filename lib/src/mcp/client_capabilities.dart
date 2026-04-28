/// Client capability detection and management for MCP Flow Runtime
import 'package:logging/logging.dart';

/// Client capabilities that can be detected
class ClientCapabilities {
  /// Whether the client supports extended data mode
  final bool supportsExtendedData;
  
  /// Whether the client supports streaming responses
  final bool supportsStreaming;
  
  /// Whether the client supports notifications
  final bool supportsNotifications;
  
  /// Whether the client supports resource subscriptions
  final bool supportsSubscriptions;
  
  /// Whether the client supports batch operations
  final bool supportsBatch;
  
  /// Client version string if available
  final String? clientVersion;
  
  /// Custom capabilities reported by the client
  final Map<String, dynamic> customCapabilities;
  
  const ClientCapabilities({
    this.supportsExtendedData = false,
    this.supportsStreaming = false,
    this.supportsNotifications = false,
    this.supportsSubscriptions = false,
    this.supportsBatch = false,
    this.clientVersion,
    this.customCapabilities = const {},
  });
  
  /// Default capabilities for unknown clients
  static const ClientCapabilities defaults = ClientCapabilities();

  /// Create from JSON map
  factory ClientCapabilities.fromJson(Map<String, dynamic> json) {
    return ClientCapabilities(
      supportsExtendedData: json['supportsExtendedData'] as bool? ?? false,
      supportsStreaming: json['supportsStreaming'] as bool? ?? false,
      supportsNotifications: json['supportsNotifications'] as bool? ?? false,
      supportsSubscriptions: json['supportsSubscriptions'] as bool? ?? false,
      supportsBatch: json['supportsBatch'] as bool? ?? false,
      clientVersion: json['clientVersion'] as String?,
      customCapabilities: json['customCapabilities'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Create from client info
  factory ClientCapabilities.fromClientInfo(Map<String, dynamic> clientInfo) {
    final capabilities = clientInfo['capabilities'] as Map<String, dynamic>? ?? {};
    
    return ClientCapabilities(
      supportsExtendedData: capabilities['extendedData'] as bool? ?? false,
      supportsStreaming: capabilities['streaming'] as bool? ?? false,
      supportsNotifications: capabilities['notifications'] as bool? ?? false,
      supportsSubscriptions: capabilities['subscriptions'] as bool? ?? false,
      supportsBatch: capabilities['batch'] as bool? ?? false,
      clientVersion: clientInfo['version'] as String?,
      customCapabilities: Map<String, dynamic>.from(capabilities)
        ..remove('extendedData')
        ..remove('streaming')
        ..remove('notifications')
        ..remove('subscriptions')
        ..remove('batch'),
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'supportsExtendedData': supportsExtendedData,
    'supportsStreaming': supportsStreaming,
    'supportsNotifications': supportsNotifications,
    'supportsSubscriptions': supportsSubscriptions,
    'supportsBatch': supportsBatch,
    if (clientVersion != null) 'clientVersion': clientVersion,
    if (customCapabilities.isNotEmpty) 'customCapabilities': customCapabilities,
  };
}

/// Client capability detector
class ClientCapabilityDetector {
  final Logger _logger = Logger('ClientCapabilityDetector');
  final Map<String, ClientCapabilities> _clientCapabilities = {};
  final Map<String, DateTime> _lastSeen = {};
  final Duration _clientTimeout;
  
  ClientCapabilityDetector({
    Duration? clientTimeout,
  }) : _clientTimeout = clientTimeout ?? const Duration(minutes: 5);
  
  /// Register client capabilities
  void registerClient(String clientId, ClientCapabilities capabilities) {
    _clientCapabilities[clientId] = capabilities;
    _lastSeen[clientId] = DateTime.now();

    _logger.info('Registered client $clientId with capabilities: ${capabilities.toJson()}');
  }

  /// Check if a client is registered
  bool isRegistered(String clientId) {
    return _clientCapabilities.containsKey(clientId);
  }

  /// Update client last seen time
  void updateClientActivity(String clientId) {
    if (_clientCapabilities.containsKey(clientId)) {
      _lastSeen[clientId] = DateTime.now();
    }
  }

  /// Get client capabilities, returns defaults for unknown clients
  ClientCapabilities getClientCapabilities(String clientId) {
    final lastSeen = _lastSeen[clientId];
    if (lastSeen != null) {
      final elapsed = DateTime.now().difference(lastSeen);
      if (elapsed > _clientTimeout) {
        // Client timed out
        _logger.warning('Client $clientId has timed out');
        _clientCapabilities.remove(clientId);
        _lastSeen.remove(clientId);
        return ClientCapabilities.defaults;
      }
    }
    return _clientCapabilities[clientId] ?? ClientCapabilities.defaults;
  }
  
  /// Check if a client supports a specific capability
  bool clientSupports(String clientId, String capability) {
    final caps = getClientCapabilities(clientId);

    switch (capability) {
      case 'extendedData':
        return caps.supportsExtendedData;
      case 'streaming':
        return caps.supportsStreaming;
      case 'notifications':
        return caps.supportsNotifications;
      case 'subscriptions':
        return caps.supportsSubscriptions;
      case 'batch':
        return caps.supportsBatch;
      default:
        return caps.customCapabilities[capability] == true;
    }
  }
  
  /// Remove a client
  void removeClient(String clientId) {
    _clientCapabilities.remove(clientId);
    _lastSeen.remove(clientId);
    _logger.info('Removed client $clientId');
  }
  
  /// Get all registered client IDs (after pruning timed-out clients)
  List<String> get registeredClients {
    final now = DateTime.now();

    // Clean up timed out clients
    final timedOutClients = <String>[];
    for (final entry in _lastSeen.entries) {
      if (now.difference(entry.value) > _clientTimeout) {
        timedOutClients.add(entry.key);
      }
    }

    for (final clientId in timedOutClients) {
      removeClient(clientId);
    }

    return List<String>.unmodifiable(_clientCapabilities.keys);
  }
  
  /// Clean up inactive clients
  void cleanup() {
    final clients = registeredClients;
    _logger.fine('Cleanup complete. Active clients: ${clients.length}');
  }
}

/// Capability-aware response builder
class CapabilityAwareResponseBuilder {
  final ClientCapabilityDetector detector;
  
  CapabilityAwareResponseBuilder(this.detector);
  
  /// Build a response based on client capabilities
  Map<String, dynamic> buildResponse({
    required String clientId,
    required dynamic data,
    Map<String, dynamic>? extras,
  }) {
    final capabilities = detector.getClientCapabilities(clientId);

    final response = <String, dynamic>{};

    // Add data based on capabilities
    if (capabilities.supportsExtendedData) {
      response['data'] = data;
      response['timestamp'] = DateTime.now().toIso8601String();
      response['format'] = 'extended';
    } else {
      // Simplified data for clients that don't support extended format
      if (data is Map) {
        response['data'] = _simplifyData(Map<String, dynamic>.from(data));
      } else {
        response['data'] = data;
      }
      response['format'] = 'simple';
    }

    // Merge extras if provided
    if (extras != null) {
      response.addAll(extras);
    }

    return response;
  }

  /// Build a streaming response for clients that support it
  Map<String, dynamic> buildStreamingResponse({
    required String clientId,
    required Stream<dynamic> data,
  }) {
    final capabilities = detector.getClientCapabilities(clientId);

    if (!capabilities.supportsStreaming) {
      return {'error': 'Client does not support streaming', 'clientId': clientId};
    }

    // Streaming setup placeholder; actual stream handling is caller's responsibility
    return {
      'clientId': clientId,
      'streaming': true,
      'format': capabilities.supportsExtendedData ? 'extended' : 'simple',
    };
  }

  /// Build a notification payload for a client
  Map<String, dynamic> buildNotification({
    required String clientId,
    required String event,
    required dynamic data,
  }) {
    final capabilities = detector.getClientCapabilities(clientId);

    if (!capabilities.supportsNotifications) {
      return {'error': 'Client does not support notifications', 'clientId': clientId};
    }

    return {
      'clientId': clientId,
      'event': event,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Build a batch response for a client
  Map<String, dynamic> buildBatchResponse({
    required String clientId,
    required List<dynamic> items,
  }) {
    final capabilities = detector.getClientCapabilities(clientId);

    if (!capabilities.supportsBatch) {
      return {'error': 'Client does not support batch operations', 'clientId': clientId};
    }

    return {
      'clientId': clientId,
      'batch': true,
      'items': items,
      'count': items.length,
    };
  }

  /// Simplify complex data structures for limited clients
  Map<String, dynamic> _simplifyData(Map<String, dynamic> data) {
    final simplified = <String, dynamic>{};

    for (final entry in data.entries) {
      if (entry.value is Map<dynamic, dynamic> || entry.value is List) {
        // Skip complex nested structures
        continue;
      }
      simplified[entry.key] = entry.value;
    }

    return simplified;
  }
}