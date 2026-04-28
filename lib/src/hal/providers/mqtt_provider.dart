/// MQTT provider interface and mock implementation

import 'dart:async';
import 'dart:convert';

import '../../types/hardware_types.dart';
import '../hal_interface.dart';

/// MQTT message class
class MqttMessage {
  final String topic;
  final String payload;
  final int qos;
  final bool retain;
  final DateTime timestamp;

  MqttMessage({
    required this.topic,
    required this.payload,
    this.qos = 0,
    this.retain = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// MQTT provider interface
abstract class MqttProvider extends HardwareProvider {
  /// Connect to MQTT broker
  Future<MqttClient> connect(MqttConfig config);
}

/// MQTT client interface
abstract class MqttClient {
  /// Configuration
  MqttConfig get config;
  
  /// Connection status
  bool get isConnected;
  
  /// Message stream for subscribed topics
  Stream<MqttMessage> get messageStream;
  
  /// Connect to broker
  Future<void> connect();
  
  /// Disconnect from broker
  Future<void> disconnect();
  
  /// Publish message
  Future<void> publish(String topic, String message, {int qos = 0, bool retain = false});
  
  /// Subscribe to topic
  Future<void> subscribe(String topic, {int qos = 0});
  
  /// Unsubscribe from topic
  Future<void> unsubscribe(String topic);
  
  /// Get subscribed topics
  List<String> get subscribedTopics;
}

/// Mock MQTT provider for testing
class MockMqttProvider extends MqttProvider {
  final Map<String, MockMqttClient> _clients = {};
  bool _initialized = false;

  @override
  String get name => 'MockMqttProvider';

  @override
  String get version => '1.0.0';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.mqtt};

  @override
  bool get isReady => _initialized;

  @override
  Map<String, dynamic> get capabilities => {
    'protocols': ['mqtt', 'mqtts'],
    'qosLevels': [0, 1, 2],
    'maxMessageSize': 256 * 1024,
    'maxTopicLength': 65535,
  };

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    for (final client in _clients.values) {
      await client.disconnect();
    }
    _clients.clear();
    _initialized = false;
  }

  @override
  Future<MqttClient> connect(MqttConfig config) async {
    final key = '${config.host}:${config.port}';
    if (!_clients.containsKey(key)) {
      _clients[key] = MockMqttClient(config);
    }
    return _clients[key]!;
  }
}

/// Mock MQTT client for testing
class MockMqttClient implements MqttClient {
  final MqttConfig _config;
  bool _connected = false;
  final List<String> _subscribedTopics = [];
  final _messageController = StreamController<MqttMessage>.broadcast();
  final Map<String, List<MqttMessage>> _messageHistory = {};

  MockMqttClient(this._config);

  @override
  MqttConfig get config => _config;

  @override
  bool get isConnected => _connected;

  @override
  Stream<MqttMessage> get messageStream => _messageController.stream;

  @override
  List<String> get subscribedTopics => List.unmodifiable(_subscribedTopics);

  @override
  Future<void> connect() async {
    if (_connected) return;
    
    // Simulate connection delay
    await Future.delayed(Duration(milliseconds: 100));
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    
    _connected = false;
    _subscribedTopics.clear();
    await _messageController.close();
  }

  @override
  Future<void> publish(String topic, String message, {int qos = 0, bool retain = false}) async {
    if (!_connected) {
      throw StateError('MQTT client not connected');
    }

    final mqttMessage = MqttMessage(
      topic: topic,
      payload: message,
      qos: qos,
      retain: retain,
    );

    // Store in history
    _messageHistory.putIfAbsent(topic, () => []).add(mqttMessage);

    // If we're subscribed to this topic, emit it
    if (_subscribedTopics.contains(topic)) {
      _messageController.add(mqttMessage);
    }

    // Simulate publish delay
    await Future.delayed(Duration(milliseconds: 10));
  }

  @override
  Future<void> subscribe(String topic, {int qos = 0}) async {
    if (!_connected) {
      throw StateError('MQTT client not connected');
    }

    if (!_subscribedTopics.contains(topic)) {
      _subscribedTopics.add(topic);
      
      // Emit any retained messages for this topic
      final retained = _messageHistory[topic]?.where((m) => m.retain) ?? [];
      for (final message in retained) {
        _messageController.add(message);
      }
    }
  }

  @override
  Future<void> unsubscribe(String topic) async {
    if (!_connected) {
      throw StateError('MQTT client not connected');
    }

    _subscribedTopics.remove(topic);
  }
}

/// MQTT configuration
class MqttConfig {
  final String host;
  final int port;
  final String? username;
  final String? password;
  final String? clientId;
  final bool cleanSession;
  final int keepAlive;
  final bool secure;
  final Map<String, dynamic>? tlsConfig;

  MqttConfig({
    required this.host,
    this.port = 1883,
    this.username,
    this.password,
    this.clientId,
    this.cleanSession = true,
    this.keepAlive = 60,
    this.secure = false,
    this.tlsConfig,
  });

  factory MqttConfig.fromJson(Map<String, dynamic> json) {
    return MqttConfig(
      host: json['host'] as String,
      port: json['port'] as int? ?? 1883,
      username: json['username'] as String?,
      password: json['password'] as String?,
      clientId: json['clientId'] as String?,
      cleanSession: json['cleanSession'] as bool? ?? true,
      keepAlive: json['keepAlive'] as int? ?? 60,
      secure: json['secure'] as bool? ?? false,
      tlsConfig: json['tlsConfig'] as Map<String, dynamic>?,
    );
  }
}