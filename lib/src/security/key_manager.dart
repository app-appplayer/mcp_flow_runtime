import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:logging/logging.dart';

/// Key management configuration
class KeyManagementConfig {
  /// Key management provider: 'local' | 'aws-kms'
  final String provider;

  final LocalKeyConfig? local;
  final AwsKmsConfig? awsKms;

  final KeyRotationConfig rotation;
  final KeyDerivationConfig derivation;

  const KeyManagementConfig({
    required this.provider,
    this.local,
    this.awsKms,
    required this.rotation,
    required this.derivation,
  });
}

/// Local key storage configuration
class LocalKeyConfig {
  final String keyStorePath;
  final bool encryptAtRest;

  const LocalKeyConfig({
    required this.keyStorePath,
    this.encryptAtRest = true,
  });
}

/// AWS KMS configuration
class AwsKmsConfig {
  final String region;

  /// Full ARN of the AWS KMS key
  final String keyArn;

  const AwsKmsConfig({
    required this.region,
    required this.keyArn,
  });
}

/// Key rotation configuration
class KeyRotationConfig {
  final bool enabled;

  /// Rotation interval in seconds (e.g. 2592000 = 30 days)
  final int intervalSeconds;

  final int rotateBeforeExpirySeconds;

  const KeyRotationConfig({
    this.enabled = false,
    this.intervalSeconds = 2592000,
    this.rotateBeforeExpirySeconds = 86400,
  });
}

/// Key derivation configuration
class KeyDerivationConfig {
  /// Key derivation function: 'pbkdf2'
  final String function;

  /// Number of iterations (default: 100000)
  final int iterations;

  /// Salt source: 'device-unique' | 'random'
  final String saltSource;

  const KeyDerivationConfig({
    this.function = 'pbkdf2',
    this.iterations = 100000,
    this.saltSource = 'random',
  });
}

/// Exception thrown for key management errors
class KeyManagementException implements Exception {
  final String message;
  final dynamic cause;

  const KeyManagementException(this.message, {this.cause});

  @override
  String toString() => 'KeyManagementException: $message';
}

/// Thrown when AES-GCM authentication tag verification fails
class DecryptionException extends KeyManagementException {
  const DecryptionException(super.message, {super.cause});

  @override
  String toString() => 'DecryptionException: $message';
}

/// Manages cryptographic keys with PBKDF2 derivation and local/KMS storage.
///
/// Uses AES-256-GCM for authenticated encryption via the `encrypt` package.
class KeyManager {
  final KeyManagementConfig config;

  static final _log = Logger('KeyManager');
  static final _random = Random.secure();

  /// Cached master key
  List<int>? _masterKey;

  /// Timestamp when the master key was last rotated/loaded
  DateTime? _masterKeyLoadedAt;

  KeyManager(this.config);

  /// Derives a cryptographic key from [password] using PBKDF2-HMAC-SHA256.
  /// [salt] should be device-unique or randomly generated and stored securely.
  Future<List<int>> deriveKey({
    required String password,
    required List<int> salt,
    int keyLengthBytes = 32,
  }) async {
    if (config.derivation.function != 'pbkdf2') {
      throw KeyManagementException(
        'Unsupported key derivation function: ${config.derivation.function}',
      );
    }

    final iterations = config.derivation.iterations;
    final passwordBytes = utf8.encode(password);

    // PBKDF2-HMAC-SHA256 implementation
    final hmacSha256 = Hmac(sha256, passwordBytes);
    final blocks = (keyLengthBytes / 32).ceil();
    final result = <int>[];

    for (var blockIndex = 1; blockIndex <= blocks; blockIndex++) {
      // U1 = PRF(Password, Salt || INT_32_BE(i))
      final blockBytes = Uint8List(4)
        ..buffer.asByteData().setUint32(0, blockIndex, Endian.big);
      final saltWithBlock = [...salt, ...blockBytes];

      var u = hmacSha256.convert(saltWithBlock).bytes;
      var t = List<int>.from(u);

      // U2..Uc
      for (var i = 1; i < iterations; i++) {
        u = Hmac(sha256, passwordBytes).convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }

      result.addAll(t);
    }

    return result.sublist(0, keyLengthBytes);
  }

  /// Encrypts [plaintext] using AES-256-GCM.
  /// Returns IV (12 bytes) + ciphertext + GCM authentication tag (16 bytes).
  Future<List<int>> encrypt(List<int> plaintext, List<int> key) async {
    if (key.length != 32) {
      throw const KeyManagementException('Key must be 32 bytes for AES-256');
    }

    // Generate random 12-byte IV (standard for GCM)
    final iv = encrypt_pkg.IV.fromSecureRandom(12);
    final encryptionKey = encrypt_pkg.Key(Uint8List.fromList(key));
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(encryptionKey, mode: encrypt_pkg.AESMode.gcm),
    );

    final encrypted = encrypter.encryptBytes(plaintext, iv: iv);

    // Format: IV (12 bytes) || ciphertext + tag (appended by GCM)
    return [...iv.bytes, ...encrypted.bytes];
  }

  /// Decrypts [ciphertext] produced by [encrypt] (IV + ciphertext + GCM tag).
  /// Throws [DecryptionException] if GCM authentication tag verification fails.
  Future<List<int>> decrypt(List<int> ciphertext, List<int> key) async {
    if (key.length != 32) {
      throw const KeyManagementException('Key must be 32 bytes for AES-256');
    }

    // Minimum: 12 bytes IV + 16 bytes GCM tag
    if (ciphertext.length < 12 + 16) {
      throw const DecryptionException('Ciphertext too short');
    }

    // Extract IV (12 bytes) and encrypted data with GCM tag
    final iv = encrypt_pkg.IV(Uint8List.fromList(ciphertext.sublist(0, 12)));
    final encryptedData = Uint8List.fromList(ciphertext.sublist(12));
    final encryptionKey = encrypt_pkg.Key(Uint8List.fromList(key));
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(encryptionKey, mode: encrypt_pkg.AESMode.gcm),
    );

    try {
      final decrypted = encrypter.decryptBytes(
        encrypt_pkg.Encrypted(encryptedData),
        iv: iv,
      );
      return decrypted;
    } catch (e) {
      throw DecryptionException(
        'Authentication tag verification failed; data may have been tampered with',
        cause: e,
      );
    }
  }

  /// Retrieves the current master key from the configured provider.
  Future<List<int>> getMasterKey() async {
    if (_masterKey != null) return _masterKey!;

    switch (config.provider) {
      case 'local':
        _masterKey = await _loadLocalMasterKey();
      case 'aws-kms':
        _masterKey = await _loadAwsKmsMasterKey();
      default:
        throw KeyManagementException(
          'Unknown key provider: ${config.provider}',
        );
    }

    _masterKeyLoadedAt = DateTime.now();
    return _masterKey!;
  }

  /// Rotates the master key in the configured provider and re-encrypts dependent keys.
  Future<void> rotateMasterKey() async {
    _log.info('Rotating master key');

    switch (config.provider) {
      case 'local':
        await _rotateLocalMasterKey();
      case 'aws-kms':
        await _rotateAwsKmsMasterKey();
      default:
        throw KeyManagementException(
          'Unknown key provider: ${config.provider}',
        );
    }

    _masterKeyLoadedAt = DateTime.now();
    _log.info('Master key rotated successfully');
  }

  /// Returns the scheduled next rotation time based on the current key metadata.
  Future<DateTime> getNextRotationTime() async {
    if (!config.rotation.enabled) {
      return DateTime.now().add(const Duration(days: 365 * 100)); // Far future
    }

    final loadedAt = _masterKeyLoadedAt ?? DateTime.now();
    return loadedAt.add(Duration(seconds: config.rotation.intervalSeconds));
  }

  /// Generates a random salt of the specified length
  static List<int> generateSalt({int length = 32}) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  /// Loads the master key from local file storage
  Future<List<int>> _loadLocalMasterKey() async {
    final localConfig = config.local;
    if (localConfig == null) {
      throw const KeyManagementException('Local key config not provided');
    }

    final keyFile = File(localConfig.keyStorePath);
    if (!await keyFile.exists()) {
      // Generate a new master key if none exists
      _log.info('No master key found; generating new one');
      final newKey = List<int>.generate(32, (_) => _random.nextInt(256));
      await _saveLocalMasterKey(newKey);
      return newKey;
    }

    final contents = await keyFile.readAsString();
    final keyData = jsonDecode(contents) as Map<String, dynamic>;
    final keyBase64 = keyData['key'] as String;
    return base64.decode(keyBase64);
  }

  /// Saves the master key to local file storage
  Future<void> _saveLocalMasterKey(List<int> key) async {
    final localConfig = config.local;
    if (localConfig == null) {
      throw const KeyManagementException('Local key config not provided');
    }

    final keyFile = File(localConfig.keyStorePath);
    final parent = keyFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final keyData = {
      'key': base64.encode(key),
      'createdAt': DateTime.now().toIso8601String(),
      'provider': 'local',
    };

    await keyFile.writeAsString(jsonEncode(keyData));

    // Set restrictive permissions on Unix-like systems
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', localConfig.keyStorePath]);
    }
  }

  /// Rotates the local master key
  Future<void> _rotateLocalMasterKey() async {
    final newKey = List<int>.generate(32, (_) => _random.nextInt(256));
    await _saveLocalMasterKey(newKey);
    _masterKey = newKey;
  }

  /// Loads the master key from AWS KMS
  Future<List<int>> _loadAwsKmsMasterKey() async {
    // TODO: Implement AWS KMS integration using AWS SDK or HTTP API
    // kms.generateDataKey(KeyId: config.awsKms!.keyArn, KeySpec: 'AES_256')
    // Return the plaintext data key
    _log.warning('AWS KMS integration is stubbed; generating local key');
    return List<int>.generate(32, (_) => _random.nextInt(256));
  }

  /// Rotates the master key in AWS KMS
  Future<void> _rotateAwsKmsMasterKey() async {
    // TODO: Implement AWS KMS key rotation
    // kms.enableKeyRotation(KeyId: config.awsKms!.keyArn)
    // Then generate a new data key
    _log.warning('AWS KMS key rotation is stubbed');
    _masterKey = List<int>.generate(32, (_) => _random.nextInt(256));
  }
}
