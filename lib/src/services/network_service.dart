/// NetworkService - Network communication abstraction for MCP Flow Runtime
///
/// MOD-SVC-004: Provides HTTP, TCP, UDP, WebSocket, and MQTT communication
/// through a unified abstract interface.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'system_service_registry.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// HTTP response wrapper.
class HttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;

  const HttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// Decodes the body as UTF-8 text.
  String get bodyText => utf8.decode(body);
}

/// Abstract TCP connection handle.
abstract class TcpConnection {
  /// Stream of incoming data chunks.
  Stream<Uint8List> get incoming;

  /// Sends [data] over the connection.
  Future<void> send(Uint8List data);

  /// Closes the connection.
  Future<void> close();
}

/// Abstract WebSocket connection handle.
abstract class WebSocketConnection {
  /// Unique connection identifier.
  final String id;

  WebSocketConnection(this.id);

  /// Stream of incoming messages (String or Uint8List).
  Stream<dynamic> get messages;

  /// Sends [data] over the WebSocket.
  Future<void> send(dynamic data);

  /// Closes the WebSocket with an optional [code] and [reason].
  Future<void> close([int? code, String? reason]);
}

/// MQTT message wrapper.
class MqttMessage {
  final String topic;
  final Uint8List payload;
  final int qos;
  final bool retain;

  const MqttMessage({
    required this.topic,
    required this.payload,
    this.qos = 0,
    this.retain = false,
  });
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by network operations.
class NetworkServiceException implements Exception {
  final String serviceId = 'network';
  final String operation;
  final String message;
  final dynamic cause;
  final int? statusCode;
  final String? url;

  const NetworkServiceException({
    required this.operation,
    required this.message,
    this.cause,
    this.statusCode,
    this.url,
  });

  @override
  String toString() =>
      'NetworkServiceException($operation): $message${url != null ? ' [url=$url]' : ''}';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract network service.
abstract class NetworkService extends SystemService {
  /// Sends an HTTP request and returns the response.
  Future<HttpResponse> httpRequest(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
    Duration timeout = const Duration(seconds: 30),
  });

  /// Opens a TCP connection to [host]:[port].
  Future<TcpConnection> tcpConnect(String host, int port, {Duration? timeout});

  /// Sends a UDP datagram to [host]:[port].
  Future<void> udpSend(String host, int port, Uint8List data);

  /// Opens a WebSocket connection to [url].
  Future<WebSocketConnection> websocketConnect(
    String url, {
    List<String>? protocols,
    Map<String, String>? headers,
  });

  /// Publishes [payload] to an MQTT [topic].
  Future<void> mqttPublish(
    String topic,
    dynamic payload, {
    int qos = 0,
    bool retain = false,
  });

  /// Subscribes to an MQTT [topic] pattern. Returns a stream of incoming messages.
  Stream<MqttMessage> mqttSubscribe(String topicPattern, {int qos = 0});
}

// ---------------------------------------------------------------------------
// Dart IO implementation
// ---------------------------------------------------------------------------

/// Network service implementation using dart:io HttpClient and sockets.
class DartNetworkService extends NetworkService {
  final Logger _log = Logger('DartNetworkService');
  io.HttpClient? _httpClient;
  bool _ready = false;

  @override
  Future<void> initialize() async {
    _httpClient = io.HttpClient();
    _ready = true;
    _log.info('DartNetworkService initialized');
  }

  @override
  Future<void> dispose() async {
    _httpClient?.close(force: true);
    _httpClient = null;
    _ready = false;
    _log.info('DartNetworkService disposed');
  }

  @override
  bool get isReady => _ready;

  @override
  Future<HttpResponse> httpRequest(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _httpClient;
    if (client == null) {
      throw NetworkServiceException(
        operation: 'httpRequest',
        message: 'Service not initialized',
        url: url,
      );
    }

    try {
      final uri = Uri.parse(url);
      client.connectionTimeout = timeout;

      final io.HttpClientRequest request;
      switch (method.toUpperCase()) {
        case 'GET':
          request = await client.getUrl(uri);
        case 'POST':
          request = await client.postUrl(uri);
        case 'PUT':
          request = await client.putUrl(uri);
        case 'DELETE':
          request = await client.deleteUrl(uri);
        case 'PATCH':
          request = await client.patchUrl(uri);
        case 'HEAD':
          request = await client.headUrl(uri);
        default:
          request = await client.openUrl(method.toUpperCase(), uri);
      }

      // Apply headers
      headers?.forEach((key, value) {
        request.headers.set(key, value);
      });

      // Write body if present
      if (body != null) {
        if (body is Uint8List) {
          request.add(body);
        } else if (body is String) {
          request.write(body);
        } else {
          request.write(jsonEncode(body));
        }
      }

      final ioResponse = await request.close();
      final responseBody = await ioResponse.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );

      final responseHeaders = <String, String>{};
      ioResponse.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      final statusCode = ioResponse.statusCode;
      if (statusCode >= 400 && statusCode < 500) {
        throw NetworkServiceException(
          operation: 'httpRequest',
          message: 'HTTP_CLIENT_ERROR',
          statusCode: statusCode,
          url: url,
        );
      } else if (statusCode >= 500) {
        throw NetworkServiceException(
          operation: 'httpRequest',
          message: 'HTTP_SERVER_ERROR',
          statusCode: statusCode,
          url: url,
        );
      }

      return HttpResponse(
        statusCode: statusCode,
        headers: responseHeaders,
        body: Uint8List.fromList(responseBody),
      );
    } on NetworkServiceException {
      rethrow;
    } on io.SocketException catch (e) {
      throw NetworkServiceException(
        operation: 'httpRequest',
        message: 'CONNECTION_TIMEOUT',
        cause: e,
        url: url,
      );
    } catch (e) {
      throw NetworkServiceException(
        operation: 'httpRequest',
        message: e.toString(),
        cause: e,
        url: url,
      );
    }
  }

  @override
  Future<TcpConnection> tcpConnect(String host, int port,
      {Duration? timeout}) async {
    try {
      final socket = await io.Socket.connect(host, port,
          timeout: timeout ?? const Duration(seconds: 30));
      return _DartTcpConnection(socket);
    } on io.SocketException catch (e) {
      throw NetworkServiceException(
        operation: 'tcpConnect',
        message: 'CONNECTION_TIMEOUT',
        cause: e,
        url: '$host:$port',
      );
    }
  }

  @override
  Future<void> udpSend(String host, int port, Uint8List data) async {
    try {
      final socket = await io.RawDatagramSocket.bind(
          io.InternetAddress.anyIPv4, 0);
      final address = (await io.InternetAddress.lookup(host)).first;
      socket.send(data, address, port);
      socket.close();
    } catch (e) {
      throw NetworkServiceException(
        operation: 'udpSend',
        message: e.toString(),
        cause: e,
        url: '$host:$port',
      );
    }
  }

  @override
  Future<WebSocketConnection> websocketConnect(
    String url, {
    List<String>? protocols,
    Map<String, String>? headers,
  }) async {
    try {
      final ws = await io.WebSocket.connect(
        url,
        protocols: protocols,
        headers: headers,
      );
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      return _DartWebSocketConnection(id, ws);
    } catch (e) {
      throw NetworkServiceException(
        operation: 'websocketConnect',
        message: e.toString(),
        cause: e,
        url: url,
      );
    }
  }

  @override
  Future<void> mqttPublish(
    String topic,
    dynamic payload, {
    int qos = 0,
    bool retain = false,
  }) async {
    // TODO: Implement using mqtt_client package
    throw NetworkServiceException(
      operation: 'mqttPublish',
      message: 'MQTT support not yet implemented. Requires mqtt_client package.',
    );
  }

  @override
  Stream<MqttMessage> mqttSubscribe(String topicPattern, {int qos = 0}) {
    // TODO: Implement using mqtt_client package
    throw NetworkServiceException(
      operation: 'mqttSubscribe',
      message: 'MQTT support not yet implemented. Requires mqtt_client package.',
    );
  }
}

// ---------------------------------------------------------------------------
// Internal TCP connection wrapper
// ---------------------------------------------------------------------------

class _DartTcpConnection extends TcpConnection {
  final io.Socket _socket;

  _DartTcpConnection(this._socket);

  @override
  Stream<Uint8List> get incoming => _socket;

  @override
  Future<void> send(Uint8List data) async {
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    await _socket.close();
  }
}

// ---------------------------------------------------------------------------
// Internal WebSocket connection wrapper
// ---------------------------------------------------------------------------

class _DartWebSocketConnection extends WebSocketConnection {
  final io.WebSocket _ws;

  _DartWebSocketConnection(super.id, this._ws);

  @override
  Stream<dynamic> get messages => _ws;

  @override
  Future<void> send(dynamic data) async {
    _ws.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _ws.close(code, reason);
  }
}

// ---------------------------------------------------------------------------
// Mock implementation for testing
// ---------------------------------------------------------------------------

/// In-memory mock network service for testing.
///
/// HTTP methods return configurable mock responses. TCP/WebSocket/MQTT use
/// in-memory queues and streams without any real network I/O.
class MockNetworkService extends NetworkService {
  bool _ready = false;

  /// Configurable default HTTP response returned by [httpRequest].
  HttpResponse defaultHttpResponse;

  /// Optional per-URL response overrides. Key is the URL string.
  final Map<String, HttpResponse> httpResponses = {};

  /// In-memory MQTT topic streams.
  final Map<String, StreamController<MqttMessage>> _mqttControllers = {};

  MockNetworkService({
    HttpResponse? defaultResponse,
  }) : defaultHttpResponse = defaultResponse ??
            HttpResponse(
              statusCode: 200,
              headers: const {'content-type': 'application/json'},
              body: Uint8List.fromList(utf8.encode('{"mock":true}')),
            );

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    for (final ctrl in _mqttControllers.values) {
      await ctrl.close();
    }
    _mqttControllers.clear();
    _ready = false;
  }

  @override
  bool get isReady => _ready;

  @override
  Future<HttpResponse> httpRequest(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return httpResponses[url] ?? defaultHttpResponse;
  }

  @override
  Future<TcpConnection> tcpConnect(String host, int port,
      {Duration? timeout}) async {
    return _MockTcpConnection();
  }

  @override
  Future<void> udpSend(String host, int port, Uint8List data) async {
    // No-op in mock; data is silently discarded.
  }

  @override
  Future<WebSocketConnection> websocketConnect(
    String url, {
    List<String>? protocols,
    Map<String, String>? headers,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return _MockWebSocketConnection(id);
  }

  @override
  Future<void> mqttPublish(
    String topic,
    dynamic payload, {
    int qos = 0,
    bool retain = false,
  }) async {
    final controller = _mqttControllers[topic];
    if (controller != null && !controller.isClosed) {
      final data = payload is Uint8List
          ? payload
          : Uint8List.fromList(utf8.encode(payload.toString()));
      controller.add(MqttMessage(
        topic: topic,
        payload: data,
        qos: qos,
        retain: retain,
      ));
    }
  }

  @override
  Stream<MqttMessage> mqttSubscribe(String topicPattern, {int qos = 0}) {
    final controller = _mqttControllers.putIfAbsent(
      topicPattern,
      () => StreamController<MqttMessage>.broadcast(),
    );
    return controller.stream;
  }
}

/// Mock TCP connection backed by in-memory stream.
class _MockTcpConnection extends TcpConnection {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  final List<Uint8List> sentData = [];

  @override
  Stream<Uint8List> get incoming => _controller.stream;

  @override
  Future<void> send(Uint8List data) async {
    sentData.add(data);
    // Echo back for testing convenience
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

/// Mock WebSocket connection backed by in-memory stream.
class _MockWebSocketConnection extends WebSocketConnection {
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();
  final List<dynamic> sentData = [];

  _MockWebSocketConnection(super.id);

  @override
  Stream<dynamic> get messages => _controller.stream;

  @override
  Future<void> send(dynamic data) async {
    sentData.add(data);
    // Echo back for testing convenience
    if (!_controller.isClosed) {
      _controller.add(data);
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _controller.close();
  }
}
