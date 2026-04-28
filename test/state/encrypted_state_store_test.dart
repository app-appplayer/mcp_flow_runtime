import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/state/state_store.dart';
import 'package:mcp_flow_runtime/src/state/encrypted_state_store.dart';

void main() {
  group('EncryptedStateStore Tests', () {
    late StateStore encryptedStore;
    const testKey = '12345678901234567890123456789012'; // 32 chars
    
    setUp(() async {
      // Create encrypted store with in-memory base store
      encryptedStore = EncryptedStateStoreFactory.createEncrypted(
        baseType: 'memory',
        encryptionKey: testKey,
      );
      await encryptedStore.initialize();
    });
    
    tearDown(() async {
      await encryptedStore.dispose();
    });
    
    test('should store and retrieve encrypted values', () async {
      // Test various data types
      await encryptedStore.set('string', 'Hello, World!');
      await encryptedStore.set('number', 42);
      await encryptedStore.set('boolean', true);
      await encryptedStore.set('array', [1, 2, 3]);
      await encryptedStore.set('object', {'name': 'Test', 'value': 123});
      
      expect(await encryptedStore.get('string'), equals('Hello, World!'));
      expect(await encryptedStore.get('number'), equals(42));
      expect(await encryptedStore.get('boolean'), equals(true));
      expect(await encryptedStore.get('array'), equals([1, 2, 3]));
      expect(await encryptedStore.get('object'), equals({'name': 'Test', 'value': 123}));
    });
    
    test('should return null for non-existent keys', () async {
      expect(await encryptedStore.get('nonexistent'), isNull);
    });
    
    test('should remove values', () async {
      await encryptedStore.set('toRemove', 'value');
      expect(await encryptedStore.get('toRemove'), equals('value'));
      
      await encryptedStore.remove('toRemove');
      expect(await encryptedStore.get('toRemove'), isNull);
    });
    
    test('should clear all values', () async {
      await encryptedStore.set('key1', 'value1');
      await encryptedStore.set('key2', 'value2');
      await encryptedStore.set('key3', 'value3');
      
      await encryptedStore.clear();
      
      expect(await encryptedStore.get('key1'), isNull);
      expect(await encryptedStore.get('key2'), isNull);
      expect(await encryptedStore.get('key3'), isNull);
    });
    
    test('should handle complex nested objects', () async {
      final complexData = {
        'user': {
          'id': 123,
          'name': 'John Doe',
          'preferences': {
            'theme': 'dark',
            'notifications': true,
            'languages': ['en', 'es', 'fr']
          }
        },
        'metadata': {
          'created': DateTime.now().toIso8601String(),
          'version': '1.0.0'
        }
      };
      
      await encryptedStore.set('complex', complexData);
      final retrieved = await encryptedStore.get('complex');
      
      expect(retrieved, equals(complexData));
    });
    
    test('should reject invalid encryption keys', () {
      expect(
        () => EncryptedStateStore(
          baseStore: InMemoryStateStore(),
          encryptionKey: 'tooshort',
        ),
        throwsArgumentError,
      );
      
      expect(
        () => EncryptedStateStore(
          baseStore: InMemoryStateStore(),
          encryptionKey: 'thiskeytoolongforencryption12345678901234567890',
        ),
        throwsArgumentError,
      );
    });
    
    test('should handle special characters in values', () async {
      final specialChars = 'Special chars: éñ中文🚀\n\t\r';
      await encryptedStore.set('special', specialChars);
      expect(await encryptedStore.get('special'), equals(specialChars));
    });
    
    test('should use different IV for each encryption', () async {
      // Create a test base store that captures encrypted data
      final capturedData = <String, dynamic>{};
      final testBaseStore = _TestStateStore(capturedData);
      
      final encStore = EncryptedStateStore(
        baseStore: testBaseStore,
        encryptionKey: testKey,
      );
      await encStore.initialize();
      
      // Store same value twice
      await encStore.set('test', 'same value');
      final firstData = Map<String, dynamic>.from(capturedData['test']);
      
      await encStore.set('test', 'same value');
      final secondData = Map<String, dynamic>.from(capturedData['test']);
      
      // IVs should be different even for same value
      expect(firstData['iv'], isNot(equals(secondData['iv'])));
      // Encrypted data should also be different due to different IVs
      expect(firstData['data'], isNot(equals(secondData['data'])));
    });
    
    test('should gracefully handle corrupted data', () async {
      // Create a base store with corrupted data
      final baseStore = InMemoryStateStore();
      await baseStore.initialize();
      
      // Store corrupted encrypted data
      await baseStore.set('corrupted', <String, dynamic>{
        'encrypted': true,
        'data': 'invalid_base64_data',
        'iv': 'also_invalid',
      });
      
      final encStore = EncryptedStateStore(
        baseStore: baseStore,
        encryptionKey: testKey,
      );
      await encStore.initialize();
      
      // Should return null on decryption failure
      expect(await encStore.get('corrupted'), isNull);
    });
    
    test('should handle backward compatibility with unencrypted data', () async {
      // Create a base store with unencrypted data
      final baseStore = InMemoryStateStore();
      await baseStore.initialize();
      
      // Store unencrypted data directly
      await baseStore.set('legacy', 'unencrypted value');
      await baseStore.set('legacyObject', {'key': 'value'});
      
      final encStore = EncryptedStateStore(
        baseStore: baseStore,
        encryptionKey: testKey,
      );
      await encStore.initialize();
      
      // Should return unencrypted data as-is
      expect(await encStore.get('legacy'), equals('unencrypted value'));
      expect(await encStore.get('legacyObject'), equals({'key': 'value'}));
    });
  });
}

/// Test state store that captures encrypted data
class _TestStateStore implements StateStore {
  final Map<String, dynamic> _data;
  
  _TestStateStore(this._data);
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<dynamic> get(String key) async => _data[key];
  
  @override
  Future<void> set(String key, dynamic value) async {
    _data[key] = value;
  }
  
  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }
  
  @override
  Future<Map<String, dynamic>> loadAll() async => Map.from(_data);

  @override
  Future<void> clear() async {
    _data.clear();
  }

  @override
  Future<void> dispose() async {}
}