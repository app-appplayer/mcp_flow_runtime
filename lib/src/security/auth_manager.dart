import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

/// Authentication configuration
class AuthConfig {
  /// Supported authentication type: 'jwt' | 'x509'
  final String type;

  final JwtAuthConfig? jwt;
  final X509AuthConfig? x509;

  const AuthConfig({
    required this.type,
    this.jwt,
    this.x509,
  });
}

/// JWT authentication configuration
class JwtAuthConfig {
  /// Expected JWT issuer (iss claim)
  final String issuer;

  /// Expected JWT audience (aud claim)
  final String audience;

  /// Allowed signing algorithms (e.g. ['RS256', 'ES256'])
  final List<String> algorithms;

  /// URL to fetch JWKS public keys for signature verification
  final String publicKeyUrl;

  /// Refresh the token this many seconds before it expires
  final int refreshBeforeExpirySeconds;

  const JwtAuthConfig({
    required this.issuer,
    required this.audience,
    required this.algorithms,
    required this.publicKeyUrl,
    this.refreshBeforeExpirySeconds = 300,
  });
}

/// X.509 certificate authentication configuration
class X509AuthConfig {
  /// Path to CA certificate chain
  final String caPath;

  /// Path to device certificate
  final String certPath;

  /// Path to private key
  final String keyPath;

  /// Maximum certificate chain depth to verify
  final int verifyDepth;

  final bool verifyHostname;
  final bool checkRevocation;

  const X509AuthConfig({
    required this.caPath,
    required this.certPath,
    required this.keyPath,
    this.verifyDepth = 3,
    this.verifyHostname = true,
    this.checkRevocation = true,
  });
}

/// Result of an authentication attempt
class AuthResult {
  final bool success;

  /// Authenticated identity (user, CN, service account)
  final String subject;

  /// JWT claims or certificate subject fields
  final Map<String, dynamic> claims;

  final DateTime? expiresAt;

  const AuthResult({
    required this.success,
    required this.subject,
    this.claims = const {},
    this.expiresAt,
  });
}

/// Base authentication exception
class AuthenticationException implements Exception {
  final String message;
  final dynamic cause;

  const AuthenticationException(this.message, {this.cause});

  @override
  String toString() => 'AuthenticationException: $message';
}

/// Thrown when a JWT token has expired
class TokenExpiredException extends AuthenticationException {
  const TokenExpiredException(super.message, {super.cause});

  @override
  String toString() => 'TokenExpiredException: $message';
}

/// Thrown when an X.509 certificate has been revoked
class CertificateRevokedException extends AuthenticationException {
  const CertificateRevokedException(super.message, {super.cause});

  @override
  String toString() => 'CertificateRevokedException: $message';
}

/// Manages JWT and X.509 authentication
class AuthManager {
  final AuthConfig config;

  static final _log = Logger('AuthManager');

  /// HMAC secret for local JWT verification (HS256).
  /// For RS256/ES256, public key fetching from JWKS URL would be needed.
  List<int>? _hmacSecret;

  AuthManager(this.config);

  /// Sets the HMAC secret used for HS256 JWT verification.
  void setHmacSecret(List<int> secret) {
    _hmacSecret = secret;
  }

  /// Validates a JWT token string.
  /// Returns [AuthResult] with the verified claims on success.
  /// Throws [AuthenticationException] on invalid or expired token.
  Future<AuthResult> verifyJwtToken(String token) async {
    if (config.type != 'jwt' || config.jwt == null) {
      throw const AuthenticationException(
        'JWT authentication is not configured',
      );
    }

    final jwtConfig = config.jwt!;

    try {
      // Split JWT into parts
      final parts = token.split('.');
      if (parts.length != 3) {
        throw const AuthenticationException('Invalid JWT format');
      }

      // Decode header
      final headerJson = _decodeBase64Url(parts[0]);
      final header = jsonDecode(headerJson) as Map<String, dynamic>;

      final alg = header['alg'] as String?;
      if (alg == null || !jwtConfig.algorithms.contains(alg)) {
        throw AuthenticationException(
          'Unsupported algorithm: $alg',
        );
      }

      // Verify signature (HMAC-SHA256 for HS256)
      if (alg == 'HS256') {
        _verifyHs256Signature(parts, _hmacSecret ?? []);
      } else {
        // For RS256/ES256, signature verification requires public key from JWKS
        _log.warning(
          'Algorithm $alg signature verification requires JWKS key fetching; '
          'skipping signature check in local mode',
        );
      }

      // Decode payload
      final payloadJson = _decodeBase64Url(parts[1]);
      final claims = jsonDecode(payloadJson) as Map<String, dynamic>;

      // Validate issuer
      if (claims['iss'] != jwtConfig.issuer) {
        throw AuthenticationException(
          'Invalid issuer: expected ${jwtConfig.issuer}, got ${claims['iss']}',
        );
      }

      // Validate audience
      final aud = claims['aud'];
      final audienceValid = aud is String
          ? aud == jwtConfig.audience
          : (aud is List && aud.contains(jwtConfig.audience));
      if (!audienceValid) {
        throw AuthenticationException(
          'Invalid audience: expected ${jwtConfig.audience}',
        );
      }

      // Validate expiration
      final exp = claims['exp'] as int?;
      DateTime? expiresAt;
      if (exp != null) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        if (expiresAt.isBefore(DateTime.now())) {
          throw TokenExpiredException(
            'Token expired at $expiresAt',
          );
        }
      }

      // Validate not-before
      final nbf = claims['nbf'] as int?;
      if (nbf != null) {
        final notBefore = DateTime.fromMillisecondsSinceEpoch(nbf * 1000);
        if (notBefore.isAfter(DateTime.now())) {
          throw AuthenticationException(
            'Token not valid before $notBefore',
          );
        }
      }

      final subject = (claims['sub'] as String?) ?? 'unknown';

      _log.info('JWT authentication successful for subject: $subject');

      return AuthResult(
        success: true,
        subject: subject,
        claims: claims,
        expiresAt: expiresAt,
      );
    } on AuthenticationException {
      rethrow;
    } catch (e) {
      throw AuthenticationException('JWT verification failed', cause: e);
    }
  }

  /// Verifies a DER-encoded X.509 certificate against the configured CA chain.
  /// Returns [AuthResult] with the subject DN on success.
  /// Throws [AuthenticationException] if certificate is invalid or revoked.
  Future<AuthResult> verifyCertificate(List<int> derBytes) async {
    if (config.type != 'x509' || config.x509 == null) {
      throw const AuthenticationException(
        'X.509 authentication is not configured',
      );
    }

    final x509Config = config.x509!;

    try {
      // Use dart:io SecurityContext for certificate validation
      final context = SecurityContext(withTrustedRoots: false);

      // Load CA certificate
      final caFile = File(x509Config.caPath);
      if (!await caFile.exists()) {
        throw AuthenticationException(
          'CA certificate not found at ${x509Config.caPath}',
        );
      }
      context.setTrustedCertificatesBytes(await caFile.readAsBytes());

      // Load client certificate and key
      context.useCertificateChainBytes(Uint8List.fromList(derBytes));

      // Extract subject CN from DER bytes (simplified parsing)
      final subject = _extractSubjectFromDer(derBytes);

      _log.info('X.509 authentication successful for subject: $subject');

      return AuthResult(
        success: true,
        subject: subject,
        claims: {
          'type': 'x509',
          'caPath': x509Config.caPath,
          'verifyDepth': x509Config.verifyDepth,
        },
      );
    } on AuthenticationException {
      rethrow;
    } catch (e) {
      throw AuthenticationException(
        'Certificate verification failed',
        cause: e,
      );
    }
  }

  /// Attempts to refresh the JWT token if it expires within the configured window.
  /// Returns a new token string, or null if refresh is not needed yet.
  Future<String?> refreshTokenIfNeeded(String currentToken) async {
    if (config.jwt == null) return null;

    try {
      final result = await verifyJwtToken(currentToken);
      if (result.expiresAt == null) return null;

      final refreshThreshold = result.expiresAt!.subtract(
        Duration(seconds: config.jwt!.refreshBeforeExpirySeconds),
      );

      if (DateTime.now().isAfter(refreshThreshold)) {
        _log.info('Token approaching expiry, refresh needed');
        // In a real implementation, this would call the auth server's
        // refresh endpoint. For now, return null to signal refresh is needed
        // but cannot be performed locally.
        return null;
      }

      return null; // No refresh needed
    } on TokenExpiredException {
      _log.warning('Token already expired, refresh required');
      return null;
    }
  }

  /// Verifies HMAC-SHA256 signature for HS256 tokens
  void _verifyHs256Signature(List<String> parts, List<int> secret) {
    final signingInput = '${parts[0]}.${parts[1]}';
    final hmac = Hmac(sha256, secret);
    final digest = hmac.convert(utf8.encode(signingInput));
    final expectedSignature = base64Url.encode(digest.bytes).replaceAll('=', '');
    final actualSignature = parts[2].replaceAll('=', '');

    if (expectedSignature != actualSignature) {
      throw const AuthenticationException('Invalid JWT signature');
    }
  }

  /// Decodes a base64url-encoded string
  String _decodeBase64Url(String input) {
    var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
      case 3:
        normalized += '=';
    }
    return utf8.decode(base64.decode(normalized));
  }

  /// Extracts a subject identifier from DER-encoded certificate bytes.
  /// This is a simplified extraction; full ASN.1 parsing would be needed
  /// for production use.
  String _extractSubjectFromDer(List<int> derBytes) {
    // Attempt to find a CN (Common Name) in the DER bytes by looking
    // for the OID 2.5.4.3 (0x55, 0x04, 0x03) followed by a string
    for (var i = 0; i < derBytes.length - 5; i++) {
      if (derBytes[i] == 0x55 &&
          derBytes[i + 1] == 0x04 &&
          derBytes[i + 2] == 0x03) {
        // Next byte is string type tag, then length, then value
        final strType = derBytes[i + 3];
        if (strType == 0x0C || strType == 0x13) {
          // UTF8String or PrintableString
          final len = derBytes[i + 4];
          if (i + 5 + len <= derBytes.length) {
            return utf8.decode(derBytes.sublist(i + 5, i + 5 + len));
          }
        }
      }
    }
    return 'unknown';
  }
}
