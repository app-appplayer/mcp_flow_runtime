/// IpcService - Inter-process communication abstraction for MCP Flow Runtime
///
/// MOD-SVC-009: Provides message queue, Unix domain socket, and D-Bus
/// communication. The basic implementation uses stdin/stdout pipes;
/// POSIX message queues and D-Bus require FFI and are stubbed.
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'system_service_registry.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// A message received via IPC.
class IpcMessage {
  final Uint8List data;
  final int priority;
  final DateTime receivedAt;

  const IpcMessage({
    required this.data,
    this.priority = 0,
    required this.receivedAt,
  });
}

/// Reply from a D-Bus method call.
class DbusReply {
  final List<dynamic> values;
  final bool isError;
  final String? errorName;
  final String? errorMessage;

  const DbusReply({
    required this.values,
    this.isError = false,
    this.errorName,
    this.errorMessage,
  });
}

/// A D-Bus signal event.
class DbusSignal {
  final String sender;
  final String objectPath;
  final String interface;
  final String signalName;
  final List<dynamic> args;

  const DbusSignal({
    required this.sender,
    required this.objectPath,
    required this.interface,
    required this.signalName,
    required this.args,
  });
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by IPC operations.
class IpcServiceException implements Exception {
  final String serviceId = 'ipc';
  final String operation;
  final String message;
  final dynamic cause;
  final String? endpoint;

  const IpcServiceException({
    required this.operation,
    required this.message,
    this.cause,
    this.endpoint,
  });

  @override
  String toString() =>
      'IpcServiceException($operation): $message${endpoint != null ? ' [endpoint=$endpoint]' : ''}';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract IPC service.
abstract class IpcService extends SystemService {
  /// Sends [message] to the named message queue [queueName].
  Future<void> mqSend(String queueName, Uint8List message, {int priority = 0});

  /// Receives the next message from [queueName]. Blocks until available.
  Future<IpcMessage> mqReceive(String queueName, {Duration? timeout});

  /// Sends [data] over the Unix domain socket at [socketPath].
  Future<void> unixSocketSend(String socketPath, Uint8List data);

  /// Listens for connections on a Unix domain socket at [socketPath].
  Stream<IpcMessage> unixSocketListen(String socketPath);

  /// Sends a D-Bus method call and returns the reply.
  Future<DbusReply> dbusCall(
    String busName,
    String objectPath,
    String interface,
    String method,
    List<dynamic> args, {
    bool systemBus = true,
  });

  /// Subscribes to a D-Bus signal. Returns a stream of emitted signals.
  Stream<DbusSignal> dbusSubscribe(
    String interface,
    String signalName, {
    String? sender,
    bool systemBus = true,
  });
}

// ---------------------------------------------------------------------------
// Basic pipe-based implementation
// ---------------------------------------------------------------------------

/// IPC service using stdin/stdout pipes for basic subprocess communication.
/// POSIX message queues, Unix domain sockets, and D-Bus require platform
/// FFI and are stubbed or partially implemented.
class PipeIpcService extends IpcService {
  final Logger _log = Logger('PipeIpcService');
  bool _ready = false;

  /// Active subprocess pipes indexed by queue name.
  final Map<String, io.Process> _processes = {};

  /// Pending message queues for simple in-process message passing.
  final Map<String, List<_QueuedMessage>> _queues = {};
  final Map<String, Completer<IpcMessage>> _waiters = {};

  @override
  Future<void> initialize() async {
    _ready = true;
    _log.info('PipeIpcService initialized');
  }

  @override
  Future<void> dispose() async {
    for (final process in _processes.values) {
      process.kill();
    }
    _processes.clear();
    _queues.clear();
    _waiters.clear();
    _ready = false;
    _log.info('PipeIpcService disposed');
  }

  @override
  bool get isReady => _ready;

  @override
  Future<void> mqSend(String queueName, Uint8List message,
      {int priority = 0}) async {
    final queued = _QueuedMessage(data: message, priority: priority);

    // If someone is waiting, deliver immediately
    final waiter = _waiters.remove(queueName);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(IpcMessage(
        data: message,
        priority: priority,
        receivedAt: DateTime.now(),
      ));
      return;
    }

    // Otherwise enqueue
    _queues.putIfAbsent(queueName, () => []).add(queued);
    _log.fine('Enqueued message to $queueName (priority=$priority)');
  }

  @override
  Future<IpcMessage> mqReceive(String queueName, {Duration? timeout}) async {
    // Check if there is a queued message
    final queue = _queues[queueName];
    if (queue != null && queue.isNotEmpty) {
      // Sort by priority descending and take highest
      queue.sort((a, b) => b.priority.compareTo(a.priority));
      final msg = queue.removeAt(0);
      return IpcMessage(
        data: msg.data,
        priority: msg.priority,
        receivedAt: DateTime.now(),
      );
    }

    // Wait for next message
    final completer = Completer<IpcMessage>();
    _waiters[queueName] = completer;

    if (timeout != null) {
      return completer.future.timeout(timeout, onTimeout: () {
        _waiters.remove(queueName);
        throw IpcServiceException(
          operation: 'mqReceive',
          message: 'Timeout waiting for message on queue $queueName',
          endpoint: queueName,
        );
      });
    }
    return completer.future;
  }

  @override
  Future<void> unixSocketSend(String socketPath, Uint8List data) async {
    try {
      final address = io.InternetAddress(socketPath,
          type: io.InternetAddressType.unix);
      final socket = await io.Socket.connect(address, 0);
      socket.add(data);
      await socket.flush();
      await socket.close();
    } catch (e) {
      throw IpcServiceException(
        operation: 'unixSocketSend',
        message: e.toString(),
        cause: e,
        endpoint: socketPath,
      );
    }
  }

  @override
  Stream<IpcMessage> unixSocketListen(String socketPath) {
    final controller = StreamController<IpcMessage>();

    () async {
      try {
        final address = io.InternetAddress(socketPath,
            type: io.InternetAddressType.unix);
        final server = await io.ServerSocket.bind(address, 0);
        controller.onCancel = () async {
          await server.close();
        };
        await for (final client in server) {
          final data = await client.fold<List<int>>(
            <int>[],
            (prev, chunk) => prev..addAll(chunk),
          );
          controller.add(IpcMessage(
            data: Uint8List.fromList(data),
            receivedAt: DateTime.now(),
          ));
        }
      } catch (e) {
        controller.addError(IpcServiceException(
          operation: 'unixSocketListen',
          message: e.toString(),
          cause: e,
          endpoint: socketPath,
        ));
        await controller.close();
      }
    }();

    return controller.stream;
  }

  @override
  Future<DbusReply> dbusCall(
    String busName,
    String objectPath,
    String interface,
    String method,
    List<dynamic> args, {
    bool systemBus = true,
  }) async {
    // TODO: Implement using dbus package or dart:ffi with libdbus
    throw IpcServiceException(
      operation: 'dbusCall',
      message: 'D-Bus support not yet implemented. Requires dbus package.',
      endpoint: '$busName:$objectPath',
    );
  }

  @override
  Stream<DbusSignal> dbusSubscribe(
    String interface,
    String signalName, {
    String? sender,
    bool systemBus = true,
  }) {
    // TODO: Implement using dbus package or dart:ffi with libdbus
    throw IpcServiceException(
      operation: 'dbusSubscribe',
      message: 'D-Bus support not yet implemented. Requires dbus package.',
      endpoint: '$interface.$signalName',
    );
  }
}

/// Internal queued message with priority.
class _QueuedMessage {
  final Uint8List data;
  final int priority;

  const _QueuedMessage({required this.data, required this.priority});
}

// ---------------------------------------------------------------------------
// Mock implementation for testing
// ---------------------------------------------------------------------------

/// In-memory mock IPC service for testing.
///
/// Message queues, Unix domain sockets, and D-Bus operations all use
/// in-memory data structures with no platform dependencies.
class MockIpcService extends IpcService {
  bool _ready = false;

  /// Message queues keyed by queue name.
  final Map<String, List<_QueuedMessage>> _queues = {};
  final Map<String, Completer<IpcMessage>> _waiters = {};

  /// Unix socket listeners keyed by socket path.
  final Map<String, StreamController<IpcMessage>> _socketListeners = {};

  /// In-memory D-Bus method registry.
  /// Key: '$busName:$objectPath:$interface:$method'
  final Map<String, Future<DbusReply> Function(List<dynamic> args)>
      dbusMethodHandlers = {};

  /// In-memory D-Bus signal controllers.
  /// Key: '$interface:$signalName'
  final Map<String, StreamController<DbusSignal>> _dbusSignalControllers = {};

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    _queues.clear();
    _waiters.clear();
    for (final ctrl in _socketListeners.values) {
      await ctrl.close();
    }
    _socketListeners.clear();
    for (final ctrl in _dbusSignalControllers.values) {
      await ctrl.close();
    }
    _dbusSignalControllers.clear();
    dbusMethodHandlers.clear();
    _ready = false;
  }

  @override
  bool get isReady => _ready;

  @override
  Future<void> mqSend(String queueName, Uint8List message,
      {int priority = 0}) async {
    // Deliver immediately if a waiter exists
    final waiter = _waiters.remove(queueName);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(IpcMessage(
        data: message,
        priority: priority,
        receivedAt: DateTime.now(),
      ));
      return;
    }
    _queues.putIfAbsent(queueName, () => []).add(
      _QueuedMessage(data: message, priority: priority),
    );
  }

  @override
  Future<IpcMessage> mqReceive(String queueName, {Duration? timeout}) async {
    final queue = _queues[queueName];
    if (queue != null && queue.isNotEmpty) {
      queue.sort((a, b) => b.priority.compareTo(a.priority));
      final msg = queue.removeAt(0);
      return IpcMessage(
        data: msg.data,
        priority: msg.priority,
        receivedAt: DateTime.now(),
      );
    }

    final completer = Completer<IpcMessage>();
    _waiters[queueName] = completer;

    if (timeout != null) {
      return completer.future.timeout(timeout, onTimeout: () {
        _waiters.remove(queueName);
        throw IpcServiceException(
          operation: 'mqReceive',
          message: 'Timeout waiting for message on queue $queueName',
          endpoint: queueName,
        );
      });
    }
    return completer.future;
  }

  @override
  Future<void> unixSocketSend(String socketPath, Uint8List data) async {
    final controller = _socketListeners[socketPath];
    if (controller != null && !controller.isClosed) {
      controller.add(IpcMessage(
        data: data,
        receivedAt: DateTime.now(),
      ));
    }
    // If no listener, data is silently discarded (mirrors real behavior).
  }

  @override
  Stream<IpcMessage> unixSocketListen(String socketPath) {
    final controller = _socketListeners.putIfAbsent(
      socketPath,
      () => StreamController<IpcMessage>.broadcast(),
    );
    return controller.stream;
  }

  @override
  Future<DbusReply> dbusCall(
    String busName,
    String objectPath,
    String interface,
    String method,
    List<dynamic> args, {
    bool systemBus = true,
  }) async {
    final key = '$busName:$objectPath:$interface:$method';
    final handler = dbusMethodHandlers[key];
    if (handler != null) {
      return handler(args);
    }
    // Default: return empty successful reply
    return const DbusReply(values: []);
  }

  @override
  Stream<DbusSignal> dbusSubscribe(
    String interface,
    String signalName, {
    String? sender,
    bool systemBus = true,
  }) {
    final key = '$interface:$signalName';
    final controller = _dbusSignalControllers.putIfAbsent(
      key,
      () => StreamController<DbusSignal>.broadcast(),
    );
    return controller.stream;
  }

  /// Emits a simulated D-Bus signal for testing.
  void emitDbusSignal(DbusSignal signal) {
    final key = '${signal.interface}:${signal.signalName}';
    final controller = _dbusSignalControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(signal);
    }
  }
}
