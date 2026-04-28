/// State persistence interfaces and implementations

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:logging/logging.dart';

import 'encrypted_state_store.dart';

/// Abstract state store interface
abstract class StateStore {
  /// Initialize the store
  Future<void> initialize();
  
  /// Get a value
  Future<dynamic> get(String key);
  
  /// Set a value
  Future<void> set(String key, dynamic value);
  
  /// Remove a value
  Future<void> remove(String key);

  /// Load all stored key-value pairs
  Future<Map<String, dynamic>> loadAll();
  
  /// Clear all values
  Future<void> clear();
  
  /// Dispose the store
  Future<void> dispose();
}

/// In-memory state store (no persistence)
class InMemoryStateStore implements StateStore {
  final Map<String, dynamic> _data = {};
  @override
  Future<void> initialize() async {
    // Nothing to initialize
  }

  @override
  Future<dynamic> get(String key) async {
    return _data[key];
  }

  @override
  Future<void> set(String key, dynamic value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<Map<String, dynamic>> loadAll() async {
    return Map<String, dynamic>.from(_data);
  }

  @override
  Future<void> clear() async {
    _data.clear();
  }

  @override
  Future<void> dispose() async {
    _data.clear();
  }
}

/// File-based state store (JSON persistence)
class FileStateStore implements StateStore {
  final String filePath;
  final Logger _logger = Logger('FileStateStore');
  Map<String, dynamic> _data = {};

  FileStateStore({required this.filePath});

  @override
  Future<void> initialize() async {
    final file = File(filePath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _data = json.decode(content) as Map<String, dynamic>;
        _logger.info('Loaded state from $filePath');
      } catch (e) {
        _logger.warning('Failed to load state from $filePath: $e');
        _data = {};
      }
    }
  }

  @override
  Future<dynamic> get(String key) async {
    return _data[key];
  }

  @override
  Future<void> set(String key, dynamic value) async {
    _data[key] = value;
    await _persist();
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
    await _persist();
  }

  @override
  Future<Map<String, dynamic>> loadAll() async {
    return Map<String, dynamic>.from(_data);
  }

  @override
  Future<void> clear() async {
    _data.clear();
    await _persist();
  }

  @override
  Future<void> dispose() async {
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(json.encode(_data));
    } catch (e) {
      _logger.warning('Failed to persist state to $filePath: $e');
    }
  }
}

/// Hive-based state store (efficient persistence)
class HiveStateStore implements StateStore {
  final String boxName;
  final String? directory;
  final Logger _logger = Logger('HiveStateStore');
  Box? _box;

  HiveStateStore({
    this.boxName = 'flow_state',
    this.directory,
  });

  @override
  Future<void> initialize() async {
    if (directory != null) {
      Hive.init(directory);
    }
    _box = await Hive.openBox(boxName);
    _logger.info('Initialized Hive state store: $boxName');
  }

  @override
  Future<dynamic> get(String key) async {
    return _box?.get(key);
  }

  @override
  Future<void> set(String key, dynamic value) async {
    // Convert complex types to serializable format
    final serializable = _makeSerializable(value);
    await _box?.put(key, serializable);
  }

  @override
  Future<void> remove(String key) async {
    await _box?.delete(key);
  }

  @override
  Future<Map<String, dynamic>> loadAll() async {
    final result = <String, dynamic>{};
    if (_box != null) {
      for (final key in _box!.keys) {
        result[key.toString()] = _box!.get(key);
      }
    }
    return result;
  }

  @override
  Future<void> clear() async {
    await _box?.clear();
  }

  @override
  Future<void> dispose() async {
    await _box?.close();
  }

  dynamic _makeSerializable(dynamic value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    } else if (value is List) {
      return value.map(_makeSerializable).toList();
    } else if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _makeSerializable(v)));
    } else {
      // Convert to string representation
      return value.toString();
    }
  }
}

/// Factory for creating state stores
class StateStoreFactory {
  static StateStore create({
    required String type,
    Map<String, dynamic>? config,
  }) {
    switch (type) {
      case 'memory':
        return InMemoryStateStore();
        
      case 'file':
        final filePath = config?['path'] as String? ?? 'flow_state.json';
        return FileStateStore(filePath: filePath);
        
      case 'hive':
        final boxName = config?['boxName'] as String? ?? 'flow_state';
        final directory = config?['directory'] as String?;
        return HiveStateStore(boxName: boxName, directory: directory);

      case 'encrypted':
        final baseType = config?['baseType'] as String? ?? 'memory';
        final encryptionKey = config?['encryptionKey'] as String?;
        if (encryptionKey == null) {
          throw ArgumentError('Encrypted state store requires encryptionKey in config');
        }
        final baseStore = create(type: baseType, config: config);
        return EncryptedStateStore(baseStore: baseStore, encryptionKey: encryptionKey);

      default:
        throw ArgumentError('Unknown state store type: $type');
    }
  }
  
  /// Create an encrypted state store
  static StateStore createEncrypted({
    required String baseType,
    required String encryptionKey,
    Map<String, dynamic>? config,
  }) {
    // This will be implemented by the EncryptedStateStore extension
    throw UnimplementedError('Import encrypted_state_store.dart to use encryption');
  }
}