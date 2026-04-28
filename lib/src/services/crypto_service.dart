/// CryptoService - Cryptographic operations for MCP Flow Runtime
///
/// MOD-SVC-007: Provides hashing, symmetric encryption/decryption,
/// signing/verification, key generation, and secure random bytes.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:logging/logging.dart';

import 'system_service_registry.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// Result of an encryption operation.
class CryptoResult {
  final Uint8List ciphertext;
  final Uint8List iv;
  final Uint8List? tag;

  const CryptoResult({
    required this.ciphertext,
    required this.iv,
    this.tag,
  });
}

/// A public/private key pair.
class KeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;
  final String algorithm;
  final int keySize;

  const KeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.algorithm,
    required this.keySize,
  });
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by cryptographic operations.
class CryptoServiceException implements Exception {
  final String serviceId = 'crypto';
  final String operation;
  final String message;
  final dynamic cause;
  final String? algorithm;

  const CryptoServiceException({
    required this.operation,
    required this.message,
    this.cause,
    this.algorithm,
  });

  @override
  String toString() =>
      'CryptoServiceException($operation): $message${algorithm != null ? ' [alg=$algorithm]' : ''}';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract cryptographic service.
abstract class CryptoService extends SystemService {
  /// Computes the hash of [data] using [algorithm].
  Future<Uint8List> hash(Uint8List data, {String algorithm = 'sha256'});

  /// Encrypts [data] using [algorithm] with [key].
  Future<CryptoResult> encrypt(
    Uint8List data,
    Uint8List key, {
    String algorithm = 'aes-256-gcm',
    Uint8List? iv,
  });

  /// Decrypts [data] using [algorithm] with [key].
  Future<Uint8List> decrypt(
    Uint8List data,
    Uint8List key, {
    String algorithm = 'aes-256-gcm',
    Uint8List? iv,
    Uint8List? tag,
  });

  /// Signs [data] using the private key [privateKey] with [algorithm].
  Future<Uint8List> sign(
    Uint8List data,
    Uint8List privateKey, {
    String algorithm = 'ecdsa',
  });

  /// Verifies [signature] against [data] using [publicKey] with [algorithm].
  Future<bool> verify(
    Uint8List data,
    Uint8List signature,
    Uint8List publicKey, {
    String algorithm = 'ecdsa',
  });

  /// Generates a key pair for [algorithm]. Returns {publicKey, privateKey}.
  Future<KeyPair> generateKey({
    String algorithm = 'rsa',
    int keySize = 2048,
  });

  /// Returns [count] cryptographically secure random bytes.
  Future<Uint8List> randomBytes(int count);
}

// ---------------------------------------------------------------------------
// Implementation using crypto + encrypt packages
// ---------------------------------------------------------------------------

/// Crypto service using `package:crypto` for hashing/HMAC and
/// `package:encrypt` for AES encryption.
///
/// RSA/ECDSA signing and key generation are stubbed (require pointycastle
/// or similar for full implementation).
class DartCryptoService extends CryptoService {
  final Logger _log = Logger('DartCryptoService');
  final math.Random _secureRandom = math.Random.secure();
  bool _ready = false;

  @override
  Future<void> initialize() async {
    _ready = true;
    _log.info('DartCryptoService initialized');
  }

  @override
  Future<void> dispose() async {
    _ready = false;
    _log.info('DartCryptoService disposed');
  }

  @override
  bool get isReady => _ready;

  @override
  Future<Uint8List> hash(Uint8List data, {String algorithm = 'sha256'}) async {
    try {
      final crypto_pkg.Hash hasher;
      switch (algorithm) {
        case 'sha256':
          hasher = crypto_pkg.sha256;
        case 'sha512':
          hasher = crypto_pkg.sha512;
        case 'md5':
          hasher = crypto_pkg.md5;
        case 'sha1':
          hasher = crypto_pkg.sha1;
        default:
          throw CryptoServiceException(
            operation: 'hash',
            message: 'Unsupported hash algorithm: $algorithm',
            algorithm: algorithm,
          );
      }
      final digest = hasher.convert(data);
      return Uint8List.fromList(digest.bytes);
    } on CryptoServiceException {
      rethrow;
    } catch (e) {
      throw CryptoServiceException(
        operation: 'hash',
        message: e.toString(),
        cause: e,
        algorithm: algorithm,
      );
    }
  }

  @override
  Future<CryptoResult> encrypt(
    Uint8List data,
    Uint8List key, {
    String algorithm = 'aes-256-gcm',
    Uint8List? iv,
  }) async {
    try {
      if (key.length != 32) {
        throw CryptoServiceException(
          operation: 'encrypt',
          message: 'INVALID_KEY_SIZE: AES-256 requires a 32-byte key, got ${key.length}',
          algorithm: algorithm,
        );
      }

      final encryptKey = encrypt_pkg.Key(key);
      final encryptIv =
          iv != null ? encrypt_pkg.IV(iv) : encrypt_pkg.IV(await randomBytes(16));

      switch (algorithm) {
        case 'aes-256-gcm':
          // package:encrypt does not directly expose GCM tags; use AES with SIC mode
          // as a practical approximation. For production GCM, use pointycastle directly.
          final encrypter =
              encrypt_pkg.Encrypter(encrypt_pkg.AES(encryptKey, mode: encrypt_pkg.AESMode.sic));
          final encrypted = encrypter.encryptBytes(data, iv: encryptIv);
          // Compute HMAC-SHA256 as authentication tag substitute
          final hmacKey = crypto_pkg.Hmac(crypto_pkg.sha256, key);
          final tag = hmacKey.convert(encrypted.bytes);
          return CryptoResult(
            ciphertext: Uint8List.fromList(encrypted.bytes),
            iv: Uint8List.fromList(encryptIv.bytes),
            tag: Uint8List.fromList(tag.bytes),
          );

        case 'aes-256-cbc':
          final encrypter =
              encrypt_pkg.Encrypter(encrypt_pkg.AES(encryptKey, mode: encrypt_pkg.AESMode.cbc));
          final encrypted = encrypter.encryptBytes(data, iv: encryptIv);
          return CryptoResult(
            ciphertext: Uint8List.fromList(encrypted.bytes),
            iv: Uint8List.fromList(encryptIv.bytes),
          );

        default:
          throw CryptoServiceException(
            operation: 'encrypt',
            message: 'Unsupported encryption algorithm: $algorithm',
            algorithm: algorithm,
          );
      }
    } on CryptoServiceException {
      rethrow;
    } catch (e) {
      throw CryptoServiceException(
        operation: 'encrypt',
        message: e.toString(),
        cause: e,
        algorithm: algorithm,
      );
    }
  }

  @override
  Future<Uint8List> decrypt(
    Uint8List data,
    Uint8List key, {
    String algorithm = 'aes-256-gcm',
    Uint8List? iv,
    Uint8List? tag,
  }) async {
    try {
      if (key.length != 32) {
        throw CryptoServiceException(
          operation: 'decrypt',
          message: 'INVALID_KEY_SIZE: AES-256 requires a 32-byte key, got ${key.length}',
          algorithm: algorithm,
        );
      }
      if (iv == null) {
        throw CryptoServiceException(
          operation: 'decrypt',
          message: 'IV is required for decryption',
          algorithm: algorithm,
        );
      }

      final encryptKey = encrypt_pkg.Key(key);
      final encryptIv = encrypt_pkg.IV(iv);

      switch (algorithm) {
        case 'aes-256-gcm':
          // Verify HMAC tag before decryption
          if (tag != null) {
            final hmacKey = crypto_pkg.Hmac(crypto_pkg.sha256, key);
            final expectedTag = hmacKey.convert(data);
            if (!_constantTimeEquals(
                Uint8List.fromList(expectedTag.bytes), tag)) {
              throw CryptoServiceException(
                operation: 'decrypt',
                message: 'AUTHENTICATION_FAILED: Tag verification failed',
                algorithm: algorithm,
              );
            }
          }
          final encrypter =
              encrypt_pkg.Encrypter(encrypt_pkg.AES(encryptKey, mode: encrypt_pkg.AESMode.sic));
          final decrypted = encrypter.decryptBytes(
              encrypt_pkg.Encrypted(data), iv: encryptIv);
          return Uint8List.fromList(decrypted);

        case 'aes-256-cbc':
          final encrypter =
              encrypt_pkg.Encrypter(encrypt_pkg.AES(encryptKey, mode: encrypt_pkg.AESMode.cbc));
          final decrypted = encrypter.decryptBytes(
              encrypt_pkg.Encrypted(data), iv: encryptIv);
          return Uint8List.fromList(decrypted);

        default:
          throw CryptoServiceException(
            operation: 'decrypt',
            message: 'Unsupported decryption algorithm: $algorithm',
            algorithm: algorithm,
          );
      }
    } on CryptoServiceException {
      rethrow;
    } catch (e) {
      throw CryptoServiceException(
        operation: 'decrypt',
        message: e.toString(),
        cause: e,
        algorithm: algorithm,
      );
    }
  }

  @override
  Future<Uint8List> sign(
    Uint8List data,
    Uint8List privateKey, {
    String algorithm = 'ecdsa',
  }) async {
    // TODO: Implement using pointycastle for RSA/ECDSA signing
    throw CryptoServiceException(
      operation: 'sign',
      message: 'Signing not yet implemented. Requires pointycastle package.',
      algorithm: algorithm,
    );
  }

  @override
  Future<bool> verify(
    Uint8List data,
    Uint8List signature,
    Uint8List publicKey, {
    String algorithm = 'ecdsa',
  }) async {
    // TODO: Implement using pointycastle for RSA/ECDSA verification
    throw CryptoServiceException(
      operation: 'verify',
      message: 'Verification not yet implemented. Requires pointycastle package.',
      algorithm: algorithm,
    );
  }

  @override
  Future<KeyPair> generateKey({
    String algorithm = 'rsa',
    int keySize = 2048,
  }) async {
    // TODO: Implement using pointycastle for RSA/ECDSA key generation
    throw CryptoServiceException(
      operation: 'generateKey',
      message: 'Key generation not yet implemented. Requires pointycastle package.',
      algorithm: algorithm,
    );
  }

  @override
  Future<Uint8List> randomBytes(int count) async {
    final bytes = Uint8List(count);
    for (var i = 0; i < count; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Constant-time byte comparison to prevent timing attacks.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

// ---------------------------------------------------------------------------
// Mock implementation for testing
// ---------------------------------------------------------------------------

/// Mock crypto service for testing with simple, deterministic implementations.
///
/// - hash: uses `package:crypto` (real hashing, no external dependencies beyond
///   what is already imported).
/// - encrypt/decrypt: XOR-based simple cipher (NOT secure, testing only).
/// - sign/verify: HMAC-SHA256 based (deterministic, testable).
/// - generateKey: returns deterministic dummy key pairs.
/// - randomBytes: uses [math.Random] with a fixed seed for reproducibility.
class MockCryptoService extends CryptoService {
  bool _ready = false;
  final math.Random _rng = math.Random(42);

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    _ready = false;
  }

  @override
  bool get isReady => _ready;

  @override
  Future<Uint8List> hash(Uint8List data, {String algorithm = 'sha256'}) async {
    final crypto_pkg.Hash hasher;
    switch (algorithm) {
      case 'sha256':
        hasher = crypto_pkg.sha256;
      case 'sha512':
        hasher = crypto_pkg.sha512;
      case 'md5':
        hasher = crypto_pkg.md5;
      case 'sha1':
        hasher = crypto_pkg.sha1;
      default:
        throw CryptoServiceException(
          operation: 'hash',
          message: 'Unsupported hash algorithm: $algorithm',
          algorithm: algorithm,
        );
    }
    final digest = hasher.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  @override
  Future<CryptoResult> encrypt(
    Uint8List data,
    Uint8List key, {
    String algorithm = 'aes-256-gcm',
    Uint8List? iv,
  }) async {
    // Simple XOR cipher for testing
    final usedIv = iv ?? await randomBytes(16);
    final ciphertext = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      ciphertext[i] = data[i] ^ key[i % key.length] ^ usedIv[i % usedIv.length];
    }
    // HMAC tag for authentication simulation
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, key);
    final tag = hmac.convert(ciphertext);
    return CryptoResult(
      ciphertext: ciphertext,
      iv: Uint8List.fromList(usedIv),
      tag: Uint8List.fromList(tag.bytes),
    );
  }

  @override
  Future<Uint8List> decrypt(
    Uint8List data,
    Uint8List key, {
    String algorithm = 'aes-256-gcm',
    Uint8List? iv,
    Uint8List? tag,
  }) async {
    if (iv == null) {
      throw CryptoServiceException(
        operation: 'decrypt',
        message: 'IV is required for decryption',
        algorithm: algorithm,
      );
    }
    // Verify tag if provided
    if (tag != null) {
      final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, key);
      final expectedTag = hmac.convert(data);
      if (!_constantTimeEquals(Uint8List.fromList(expectedTag.bytes), tag)) {
        throw CryptoServiceException(
          operation: 'decrypt',
          message: 'AUTHENTICATION_FAILED: Tag verification failed',
          algorithm: algorithm,
        );
      }
    }
    // Reverse XOR cipher
    final plaintext = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      plaintext[i] = data[i] ^ key[i % key.length] ^ iv[i % iv.length];
    }
    return plaintext;
  }

  @override
  Future<Uint8List> sign(
    Uint8List data,
    Uint8List privateKey, {
    String algorithm = 'ecdsa',
  }) async {
    // HMAC-SHA256 based signing for testing
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, privateKey);
    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  @override
  Future<bool> verify(
    Uint8List data,
    Uint8List signature,
    Uint8List publicKey, {
    String algorithm = 'ecdsa',
  }) async {
    // In mock, publicKey == privateKey for HMAC-based verification
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, publicKey);
    final expected = hmac.convert(data);
    return _constantTimeEquals(
      Uint8List.fromList(expected.bytes),
      signature,
    );
  }

  @override
  Future<KeyPair> generateKey({
    String algorithm = 'rsa',
    int keySize = 2048,
  }) async {
    // Generate deterministic dummy keys for testing
    final keyBytes = keySize ~/ 8;
    final publicKey = await randomBytes(keyBytes);
    final privateKey = await randomBytes(keyBytes);
    return KeyPair(
      publicKey: publicKey,
      privateKey: privateKey,
      algorithm: algorithm,
      keySize: keySize,
    );
  }

  @override
  Future<Uint8List> randomBytes(int count) async {
    final bytes = Uint8List(count);
    for (var i = 0; i < count; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }

  /// Constant-time byte comparison.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
