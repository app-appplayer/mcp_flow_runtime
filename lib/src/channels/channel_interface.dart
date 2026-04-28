/// Channel interface and implementations for MCP Flow Runtime

import 'dart:async';
import 'dart:collection';
import '../types/flow_types.dart';
import '../errors/flow_errors.dart';

/// Base channel interface
abstract class Channel {
  final String name;
  final ChannelDefinition definition;
  
  Channel({required this.name, required this.definition});
  
  /// Send data to the channel
  Future<void> send(dynamic data);
  
  /// Get stream for receiving data
  Stream<dynamic> get stream;
  
  /// Close the channel
  Future<void> close();
  
  /// Cancel the channel (alias for close for compatibility)
  Future<void> cancel() => close();
  
  /// Receive one item from the channel stream, with optional timeout.
  Future<dynamic> receive({Duration? timeout}) async {
    if (timeout != null) {
      try {
        return await stream.first.timeout(timeout);
      } on TimeoutException {
        throw ConcreteFlowError(
          'CHANNEL_TIMEOUT',
          'Channel receive timed out',
        );
      }
    }
    return await stream.first;
  }

  /// Check if channel is full (for capacity-limited channels)
  bool get isFull => false;
}

/// Queue channel implementation with FIFO ordering
class QueueChannel extends Channel {
  final Queue<dynamic> _queue = Queue();
  final StreamController<dynamic> _controller;
  StreamSubscription? _processSubscription;
  
  QueueChannel({required super.name, required super.definition}) 
    : _controller = StreamController<dynamic>(sync: true);
  
  @override
  Stream<dynamic> get stream => _controller.stream;
  
  @override
  Future<void> send(dynamic data) async {
    if (_controller.isClosed) {
      throw ConcreteFlowError('CHANNEL_CLOSED', 'Cannot send to closed channel "$name"');
    }
    if (definition.capacity != null && _queue.length >= definition.capacity!) {
      // Handle overflow based on strategy
      final strategy = definition.overflow ?? 'dropNewest';
      if (strategy == 'dropOldest') {
        _queue.removeFirst();
      } else if (strategy == 'dropNewest') {
        return; // Drop the new message
      } else if (strategy == 'block') {
        // Wait until there's space
        while (_queue.length >= definition.capacity! && !_controller.isClosed) {
          await Future.delayed(Duration(milliseconds: 10));
        }
        if (_controller.isClosed) {
          throw ConcreteFlowError('CHANNEL_CLOSED', 'Channel closed while waiting to send');
        }
      } else {
        // Default to dropNewest for unknown strategies
        return;
      }
    }
    
    _queue.add(data);
    _processQueue();
  }
  
  void _processQueue() {
    // Process messages in FIFO order
    if (_processSubscription == null && _queue.isNotEmpty && !_controller.isClosed) {
      // Use microtask to ensure FIFO order
      _processSubscription = Future.microtask(() async {
        while (_queue.isNotEmpty && !_controller.isClosed) {
          final data = _queue.removeFirst();
          _controller.add(data);
          // Small delay to allow receiver to process before next message
          await Future.delayed(Duration(microseconds: 1));
        }
        _processSubscription = null;
      }).asStream().listen((_) {}, onDone: () {
        _processSubscription = null;
      });
    }
  }
  
  @override
  bool get isFull => definition.capacity != null && _queue.length >= definition.capacity!;
  
  @override
  Future<void> close() async {
    // Clear the queue first to break the processing loop
    _queue.clear();
    await _processSubscription?.cancel();
    
    // Workaround for Dart StreamController bug where sync controllers
    // hang on close() if stream was never accessed
    try {
      if (!_controller.hasListener && !_controller.isClosed) {
        // Add and immediately cancel a null listener to initialize the stream
        final sub = _controller.stream.listen(null);
        await sub.cancel();
      }
    } catch (e) {
      // Ignore errors - stream might already have been listened to
    }
    
    await _controller.close();
  }
}

/// PubSub channel implementation with broadcast support
class PubSubChannel extends Channel {
  final StreamController<dynamic> _controller;
  final Queue<dynamic>? _persistentQueue;
  
  PubSubChannel({required super.name, required super.definition}) 
    : _controller = StreamController<dynamic>.broadcast(sync: true),
      _persistentQueue = (definition.persistent == true) ? Queue() : null;
  
  @override
  Stream<dynamic> get stream {
    if (_persistentQueue != null) {
      // Return a stream that first emits persistent messages then live messages
      return Stream.multi((controller) {
        // Emit all persistent messages first
        for (final message in _persistentQueue!) {
          controller.add(message);
        }
        // Then subscribe to live messages
        _controller.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      });
    }
    return _controller.stream;
  }
  
  @override
  Future<void> send(dynamic data) async {
    if (_controller.isClosed) {
      throw ConcreteFlowError('CHANNEL_CLOSED', 'Cannot send to closed channel "$name"');
    }
    if (definition.capacity != null &&
        _persistentQueue != null &&
        _persistentQueue!.length >= definition.capacity!) {
      // Drop oldest persistent message
      _persistentQueue!.removeFirst();
    }
    
    _persistentQueue?.add(data);
    _controller.add(data);
  }
  
  @override
  Future<void> close() async {
    await _controller.close();
  }
}

/// Pipe channel implementation for streaming data
class PipeChannel extends Channel {
  final StreamController<dynamic> _controller;
  
  PipeChannel({required super.name, required super.definition}) 
    : _controller = StreamController<dynamic>(sync: true);
  
  @override
  Stream<dynamic> get stream => _controller.stream;
  
  @override
  Future<void> send(dynamic data) async {
    if (_controller.isClosed) {
      throw ConcreteFlowError('CHANNEL_CLOSED', 'Cannot send to closed channel "$name"');
    }
    _controller.add(data);
  }
  
  @override
  Future<void> close() async {
    await _controller.close();
  }
}

/// Shared memory channel implementation
class SharedMemoryChannel extends Channel {
  final Map<String, dynamic> _memory = {};
  final StreamController<Map<String, dynamic>> _controller;
  bool _mutex = false;
  
  SharedMemoryChannel({required super.name, required super.definition}) 
    : _controller = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  
  @override
  Stream<Map<String, dynamic>> get stream => _controller.stream;
  
  @override
  Future<void> send(dynamic data) async {
    if (_controller.isClosed) {
      throw ConcreteFlowError('CHANNEL_CLOSED', 'Cannot send to closed channel "$name"');
    }
    if (data is! Map<String, dynamic>) {
      throw ConcreteFlowError('INVALID_DATA', 'Shared memory channel requires Map<String, dynamic> data');
    }
    
    if (definition.mutex == true) {
      // Simple mutex implementation
      while (_mutex) {
        await Future.delayed(Duration(microseconds: 10));
      }
      _mutex = true;
    }
    
    try {
      _memory.addAll(data);
      _controller.add(Map.from(_memory));
    } finally {
      if (definition.mutex == true) {
        _mutex = false;
      }
    }
  }
  
  Map<String, dynamic> read() {
    return Map.from(_memory);
  }
  
  @override
  Future<void> close() async {
    await _controller.close();
  }
}

/// Factory for creating channels
class ChannelFactory {
  static Channel create(String name, ChannelDefinition definition) {
    switch (definition.type) {
      case ChannelType.queue:
        return QueueChannel(name: name, definition: definition);
      case ChannelType.pubsub:
        return PubSubChannel(name: name, definition: definition);
      case ChannelType.pipe:
        return PipeChannel(name: name, definition: definition);
      case ChannelType.sharedMemory:
        return SharedMemoryChannel(name: name, definition: definition);
    }
  }
}