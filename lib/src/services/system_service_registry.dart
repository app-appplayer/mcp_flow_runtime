/// System Service Registry - Central service discovery and lifecycle management
///
/// MOD-SVC: Provides registration, lookup, and lifecycle management for all
/// system services in the MCP Flow Runtime.
import 'dart:async';

import 'package:logging/logging.dart';

import '../errors/flow_errors.dart';

// ---------------------------------------------------------------------------
// Base contract for all system services
// ---------------------------------------------------------------------------

/// Base class that every system service must extend.
abstract class SystemService {
  /// Initializes the service (open connections, allocate handles).
  Future<void> initialize();

  /// Releases all resources held by the service.
  Future<void> dispose();

  /// Returns true if the service is ready to handle calls.
  bool get isReady;
}

// ---------------------------------------------------------------------------
// SystemServiceRegistry
// ---------------------------------------------------------------------------

/// Central registry that manages system service instances.
///
/// Usage:
/// ```dart
/// final registry = SystemServiceRegistry.instance;
/// registry.register<FileSystemService>(LocalFileSystemService());
/// final fs = registry.get<FileSystemService>();
/// ```
class SystemServiceRegistry {
  static final SystemServiceRegistry instance = SystemServiceRegistry._();

  final Logger _log = Logger('SystemServiceRegistry');
  final Map<Type, SystemService> _services = {};

  SystemServiceRegistry._();

  /// Registers a service implementation under its type.
  void register<T extends SystemService>(T service) {
    final type = T;
    if (_services.containsKey(type)) {
      _log.warning('Replacing existing service registration for $type');
    }
    _services[type] = service;
    _log.info('Registered service: $type');
  }

  /// Returns the registered implementation for type [T].
  ///
  /// Throws [FlowError] with code SERVICE_NOT_FOUND if not registered.
  T get<T extends SystemService>() {
    final service = _services[T];
    if (service == null) {
      throw ConcreteFlowError(
        'SERVICE_NOT_FOUND',
        'No service registered for type $T',
      );
    }
    return service as T;
  }

  /// Returns true if a service of type [T] is registered.
  bool isRegistered<T extends SystemService>() {
    return _services.containsKey(T);
  }

  /// Unregisters and disposes the service of type [T].
  Future<void> unregister<T extends SystemService>() async {
    final service = _services.remove(T);
    if (service != null) {
      try {
        await service.dispose();
        _log.info('Unregistered and disposed service: $T');
      } catch (e) {
        _log.severe('Error disposing service $T: $e');
        rethrow;
      }
    }
  }

  /// Initializes all registered services.
  Future<void> initializeAll() async {
    for (final entry in _services.entries) {
      try {
        await entry.value.initialize();
        _log.info('Initialized service: ${entry.key}');
      } catch (e) {
        _log.severe('Failed to initialize service ${entry.key}: $e');
        rethrow;
      }
    }
  }

  /// Disposes all registered services and clears the registry.
  Future<void> disposeAll() async {
    final errors = <String, dynamic>{};
    for (final entry in _services.entries) {
      try {
        await entry.value.dispose();
      } catch (e) {
        errors[entry.key.toString()] = e;
        _log.severe('Error disposing service ${entry.key}: $e');
      }
    }
    _services.clear();
    if (errors.isNotEmpty) {
      throw ConcreteFlowError(
        'SERVICE_DISPOSE_ERROR',
        'Failed to dispose ${errors.length} service(s): ${errors.keys.join(", ")}',
      );
    }
  }

  /// Returns the number of registered services.
  int get serviceCount => _services.length;

  /// Returns all registered service types.
  Iterable<Type> get registeredTypes => _services.keys;
}
