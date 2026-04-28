/// Encrypted state store implementation
import 'dart:async';
import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'package:logging/logging.dart';
import 'state_store.dart';

/// State store wrapper that provides transparent encryption/decryption
class EncryptedStateStore implements StateStore {
  final StateStore _baseStore;
  late String _encryptionKey;
  final Logger _logger = Logger('EncryptedStateStore');
  late Key _key;
  late Encrypter _encrypter;

  /// Create an encrypted state store
  /// 
  /// [baseStore] - The underlying state store to wrap
  /// [encryptionKey] - 32-character encryption key (256-bit)
  EncryptedStateStore({
    required StateStore baseStore,
    required String encryptionKey,
  })  : _baseStore = baseStore {
    // Check if the key is base64 encoded (typical for config files)
    String decodedKey;
    try {
      // Try to decode as base64
      final decoded = base64.decode(encryptionKey);
      if (decoded.length == 32) {
        // Use the decoded bytes directly
        _key = Key.fromBase64(encryptionKey);
        _encryptionKey = String.fromCharCodes(decoded);
      } else {
        throw ArgumentError('Base64 decoded key must be exactly 32 bytes (256 bits)');
      }
    } catch (e) {
      // Not base64, use as raw string
      if (encryptionKey.length == 32) {
        _encryptionKey = encryptionKey;
        _key = Key.fromUtf8(_encryptionKey);
      } else {
        throw ArgumentError('Encryption key must be exactly 32 characters (256 bits) or a base64-encoded 32-byte key');
      }
    }
    
    // Initialize encryption components
    _encrypter = Encrypter(AES(_key, mode: AESMode.gcm));
  }

  @override
  Future<void> initialize() async {
    await _baseStore.initialize();
    _logger.info('Initialized encrypted state store');
  }

  @override
  Future<dynamic> get(String key) async {
    try {
      // Get encrypted value from base store
      final encryptedData = await _baseStore.get(key);
      if (encryptedData == null) {
        return null;
      }

      // Decrypt the value
      if (encryptedData is Map<String, dynamic> && 
          encryptedData['encrypted'] == true &&
          encryptedData['data'] != null &&
          encryptedData['iv'] != null) {
        
        final encrypted = Encrypted.fromBase64(encryptedData['data'] as String);
        final iv = IV.fromBase64(encryptedData['iv'] as String);
        
        final decrypted = _encrypter.decrypt(encrypted, iv: iv);
        
        // Deserialize the decrypted JSON
        return json.decode(decrypted);
      }
      
      // If not encrypted data format, return as-is (for backward compatibility)
      return encryptedData;
      
    } catch (e) {
      _logger.warning('Failed to decrypt value for key $key: $e');
      // Return null on decryption failure rather than throwing
      return null;
    }
  }

  @override
  Future<void> set(String key, dynamic value) async {
    try {
      // Serialize value to JSON
      final jsonString = json.encode(value);
      
      // Generate new IV for each encryption
      final iv = IV.fromSecureRandom(16);
      
      // Encrypt the JSON string
      final encrypted = _encrypter.encrypt(jsonString, iv: iv);
      
      // Store encrypted data with metadata
      final encryptedData = {
        'encrypted': true,
        'data': encrypted.base64,
        'iv': iv.base64,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await _baseStore.set(key, encryptedData);
      
    } catch (e) {
      _logger.warning('Failed to encrypt value for key $key: $e');
      throw StateStoreException('Failed to encrypt value: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> loadAll() async {
    final encryptedAll = await _baseStore.loadAll();
    final result = <String, dynamic>{};
    for (final entry in encryptedAll.entries) {
      // Decrypt each value individually via get()
      result[entry.key] = await get(entry.key);
    }
    return result;
  }

  @override
  Future<void> remove(String key) async {
    await _baseStore.remove(key);
  }

  @override
  Future<void> clear() async {
    await _baseStore.clear();
  }

  @override
  Future<void> dispose() async {
    await _baseStore.dispose();
  }

  /// Rotates the encryption key: re-encrypts all stored data with newKey.
  /// 1. Reads all entries using the current key.
  /// 2. Re-encrypts each entry with newKey and writes back.
  /// 3. Updates _encryptionKey to newKey.
  /// Throws StateError if re-encryption fails (original data is preserved).
  Future<void> rotateKey(String newEncryptionKey) async {
    if (newEncryptionKey.length != 32) {
      throw ArgumentError('New encryption key must be exactly 32 characters (256 bits)');
    }

    _logger.info('Starting encryption key rotation');

    // 1. Read all entries using current key (decrypts via loadAll)
    final allEntries = await loadAll();

    // 2. Switch to new key
    final oldKey = _key;
    final oldEncrypter = _encrypter;
    final oldEncryptionKey = _encryptionKey;

    _encryptionKey = newEncryptionKey;
    _key = Key.fromUtf8(newEncryptionKey);
    _encrypter = Encrypter(AES(_key, mode: AESMode.gcm));

    // 3. Re-encrypt each entry with the new key
    try {
      for (final entry in allEntries.entries) {
        if (entry.value != null) {
          await set(entry.key, entry.value);
        }
      }
      _logger.info('Key rotation completed successfully for ${allEntries.length} entries');
    } catch (e) {
      // Rollback to old key on failure
      _encryptionKey = oldEncryptionKey;
      _key = oldKey;
      _encrypter = oldEncrypter;
      _logger.severe('Key rotation failed, rolled back to previous key: $e');
      throw StateError('Key rotation failed: $e');
    }
  }

  /// Verify data integrity by attempting to decrypt all values.
  /// Returns a map of key → success/failure for each entry.
  Future<Map<String, bool>> verifyIntegrity() async {
    final rawEntries = await _baseStore.loadAll();
    final result = <String, bool>{};

    for (final entry in rawEntries.entries) {
      try {
        await get(entry.key);
        result[entry.key] = true;
      } catch (_) {
        result[entry.key] = false;
      }
    }
    return result;
  }
}

/// Exception thrown by state store operations
class StateStoreException implements Exception {
  final String message;
  
  StateStoreException(this.message);
  
  @override
  String toString() => 'StateStoreException: $message';
}

/// Factory helper for creating encrypted state stores
class EncryptedStateStoreFactory {
  /// Create an encrypted state store
  static StateStore createEncrypted({
    required String baseType,
    required String encryptionKey,
    Map<String, dynamic>? config,
  }) {
    // Create base store
    final baseStore = StateStoreFactory.create(
      type: baseType,
      config: config,
    );
    
    // Wrap with encryption
    return EncryptedStateStore(
      baseStore: baseStore,
      encryptionKey: encryptionKey,
    );
  }
}