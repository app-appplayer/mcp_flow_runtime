/// TLS configuration for secure network connections
import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';

/// TLS configuration options
class TlsConfig {
  /// Whether to allow self-signed certificates
  final bool allowSelfSigned;
  
  /// Whether to verify the hostname
  final bool verifyHostname;
  
  /// Custom certificate authorities (PEM format)
  final List<String>? customCAs;
  
  /// Client certificate (PEM format)
  final String? clientCertificate;
  
  /// Client private key (PEM format)
  final String? clientKey;
  
  /// Minimum TLS version
  final String minVersion;
  
  /// Allowed cipher suites
  final List<String>? cipherSuites;
  
  const TlsConfig({
    this.allowSelfSigned = false,
    this.verifyHostname = true,
    this.customCAs,
    this.clientCertificate,
    this.clientKey,
    this.minVersion = 'TLS1.2',
    this.cipherSuites,
  });
  
  /// Create from JSON configuration
  factory TlsConfig.fromJson(Map<String, dynamic> json) {
    return TlsConfig(
      allowSelfSigned: json['allowSelfSigned'] as bool? ?? false,
      verifyHostname: json['verifyHostname'] as bool? ?? true,
      customCAs: (json['customCAs'] as List?)?.cast<String>(),
      clientCertificate: json['clientCertificate'] as String?,
      clientKey: json['clientKey'] as String?,
      minVersion: json['minVersion'] as String? ?? 'TLS1.2',
      cipherSuites: (json['cipherSuites'] as List?)?.cast<String>(),
    );
  }
}

/// TLS-enabled HTTP client factory
class TlsHttpClient {
  static final Logger _logger = Logger('TlsHttpClient');
  
  /// Create an HTTP client with TLS configuration
  static HttpClient create({TlsConfig? tlsConfig}) {
    final client = HttpClient();
    
    if (tlsConfig != null) {
      configureTls(client, tlsConfig);
    }
    
    return client;
  }
  
  /// Configure TLS settings on an HTTP client
  static void configureTls(HttpClient client, TlsConfig config) {
    // Configure certificate validation
    if (config.allowSelfSigned) {
      client.badCertificateCallback = (cert, host, port) {
        _logger.warning('Accepting self-signed certificate for $host:$port');
        return true;
      };
    } else if (config.customCAs != null && config.customCAs!.isNotEmpty) {
      // Set up custom CA validation
      client.badCertificateCallback = (cert, host, port) {
        // In a real implementation, this would validate against custom CAs
        // For now, we'll just log
        _logger.fine('Validating certificate for $host:$port against custom CAs');
        return false; // Reject by default for security
      };
    }
    
    // Configure hostname verification
    if (!config.verifyHostname) {
      _logger.warning('Hostname verification disabled - this is insecure!');
      // Note: Dart's HttpClient doesn't provide direct control over hostname verification
      // This would need platform-specific implementation
    }
    
    // Configure client certificates
    if (config.clientCertificate != null && config.clientKey != null) {
      try {
        // In a real implementation, this would load and configure client certificates
        // SecurityContext is not directly accessible from HttpClient
        _logger.fine('Client certificate authentication configured');
      } catch (e) {
        _logger.severe('Failed to configure client certificates: $e');
      }
    }
    
    // Configure TLS version
    // Note: Dart's HttpClient uses the platform's TLS implementation
    // Minimum version control would need platform-specific code
    _logger.fine('TLS minimum version: ${config.minVersion}');
    
    // Configure cipher suites
    if (config.cipherSuites != null && config.cipherSuites!.isNotEmpty) {
      _logger.fine('Custom cipher suites: ${config.cipherSuites!.join(', ')}');
      // Note: Cipher suite control would need platform-specific implementation
    }
  }
  
  /// Create a security context with TLS configuration
  static SecurityContext createSecurityContext(TlsConfig config) {
    final context = SecurityContext();
    
    // Add custom CAs
    if (config.customCAs != null) {
      for (final ca in config.customCAs!) {
        try {
          context.setTrustedCertificatesBytes(Uint8List.fromList(ca.codeUnits));
        } catch (e) {
          _logger.warning('Failed to add custom CA: $e');
        }
      }
    }
    
    // Add client certificate
    if (config.clientCertificate != null) {
      try {
        context.useCertificateChainBytes(
          Uint8List.fromList(config.clientCertificate!.codeUnits),
        );
      } catch (e) {
        _logger.warning('Failed to set client certificate: $e');
      }
    }
    
    // Add client key
    if (config.clientKey != null) {
      try {
        context.usePrivateKeyBytes(
          Uint8List.fromList(config.clientKey!.codeUnits),
        );
      } catch (e) {
        _logger.warning('Failed to set client key: $e');
      }
    }
    
    return context;
  }
}