/// MCP Event Notifier - Event notification system for MCP Flow Runtime
///
/// Sends notifications to MCP clients using both standard and
/// extension notification formats per Spec 10.3.
import 'dart:async';

import 'package:logging/logging.dart';

import 'client_capabilities.dart';

/// Callback type for delivering notifications to MCP transport layer.
typedef NotificationSink = void Function(Map<String, dynamic> notification);

/// Manages event notifications to MCP clients.
///
/// Supports two notification modes:
/// - **Standard**: Sends resource URI only; client must read resource separately.
/// - **Extension**: Includes resource data directly in notification (makemind extension).
class McpEventNotifier {
  static const String _loggerName = 'mcp-flow-runtime';

  final Logger _logger = Logger('McpEventNotifier');

  /// Capability detector for determining client extension support.
  final ClientCapabilityDetector? capabilityDetector;

  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Optional sink for delivering notifications to the transport layer.
  NotificationSink? notificationSink;

  McpEventNotifier({
    this.capabilityDetector,
    this.notificationSink,
  });

  /// Stream of all outgoing notifications.
  Stream<Map<String, dynamic>> get notifications =>
      _notificationController.stream;

  /// Send a notification to MCP clients.
  ///
  /// [resource] is the resource URI associated with the event.
  /// [level] is the notification severity level (e.g., "info", "warning", "error").
  /// [data] is optional additional data to include (extension mode only).
  /// [includeData] whether to include data directly in the notification.
  void notify(
    String resource,
    String level, {
    dynamic data,
    bool includeData = false,
  }) {
    final notificationData = <String, dynamic>{
      'resource': resource,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    // Include data directly if extension mode is requested
    if (includeData && data != null) {
      notificationData['resourceData'] = data;
    }

    final notification = <String, dynamic>{
      'method': 'notifications/message',
      'params': {
        'level': level,
        'logger': _loggerName,
        'data': notificationData,
      },
    };

    _emit(notification);
    _logger.fine('Sent notification for resource: $resource (level: $level)');
  }

  /// Notify clients of a resource update.
  ///
  /// Sends a standard MCP resource change notification.
  /// If a [ClientCapabilityDetector] is available, extension-capable clients
  /// receive the data directly.
  void notifyResourceUpdate(String uri, dynamic contents) {
    // Standard notification (without data)
    final standardNotification = <String, dynamic>{
      'method': 'notifications/message',
      'params': {
        'level': 'info',
        'logger': _loggerName,
        'data': {
          'resource': uri,
          'event': 'resource_updated',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      },
    };

    _emit(standardNotification);
    _logger.fine('Sent resource update notification for: $uri');
  }

  /// Notify with event-specific information.
  ///
  /// Used for hardware events (interrupts, state changes, etc.)
  void notifyEvent({
    required String eventId,
    required String resource,
    required String level,
    dynamic data,
    bool includeData = false,
  }) {
    final notificationData = <String, dynamic>{
      'resource': resource,
      'event': eventId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    if (includeData && data != null) {
      notificationData['resourceData'] = data;
    }

    final notification = <String, dynamic>{
      'method': 'notifications/message',
      'params': {
        'level': level,
        'logger': _loggerName,
        'data': notificationData,
      },
    };

    _emit(notification);
    _logger.fine('Sent event notification: $eventId for resource: $resource');
  }

  /// Emit a notification through all channels.
  void _emit(Map<String, dynamic> notification) {
    if (!_notificationController.isClosed) {
      _notificationController.add(notification);
    }

    notificationSink?.call(notification);
  }

  /// Dispose of the notifier and close streams.
  void dispose() {
    _notificationController.close();
    _logger.info('McpEventNotifier disposed');
  }
}
