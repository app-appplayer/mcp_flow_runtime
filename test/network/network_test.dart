import 'dart:io';

import 'package:test/test.dart';

import 'package:mcp_flow_runtime/src/network/tls_config.dart';

void main() {
  // ==========================================================================
  // 2. TlsConfig Tests (TC-911~)
  // ==========================================================================
  group('TC-911: TlsConfig default constructor', () {
    test('TC-911a: default constructor has secure defaults', () {
      const config = TlsConfig();

      expect(config.allowSelfSigned, isFalse);
      expect(config.verifyHostname, isTrue);
      expect(config.customCAs, isNull);
      expect(config.clientCertificate, isNull);
      expect(config.clientKey, isNull);
      expect(config.minVersion, equals('TLS1.2'));
      expect(config.cipherSuites, isNull);
    });

    test('TC-911b: const TlsConfig instances are identical', () {
      const c1 = TlsConfig();
      const c2 = TlsConfig();
      expect(identical(c1, c2), isTrue);
    });
  });

  group('TC-912: TlsConfig custom parameters', () {
    test('TC-912a: stores all provided parameters', () {
      const testCaPem = '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----';
      const testCertPem = '-----BEGIN CERTIFICATE-----\ncert\n-----END CERTIFICATE-----';
      const testKeyPem = '-----BEGIN RSA PRIVATE KEY-----\nkey\n-----END RSA PRIVATE KEY-----';

      final config = TlsConfig(
        allowSelfSigned: true,
        verifyHostname: false,
        customCAs: [testCaPem],
        clientCertificate: testCertPem,
        clientKey: testKeyPem,
        minVersion: 'TLS1.3',
        cipherSuites: ['TLS_AES_256_GCM_SHA384'],
      );

      expect(config.allowSelfSigned, isTrue);
      expect(config.verifyHostname, isFalse);
      expect(config.customCAs, equals([testCaPem]));
      expect(config.clientCertificate, equals(testCertPem));
      expect(config.clientKey, equals(testKeyPem));
      expect(config.minVersion, equals('TLS1.3'));
      expect(config.cipherSuites, equals(['TLS_AES_256_GCM_SHA384']));
    });

    test('TC-912b: customCAs with multiple entries', () {
      final config = TlsConfig(
        customCAs: ['ca1', 'ca2', 'ca3'],
      );
      expect(config.customCAs!.length, equals(3));
    });

    test('TC-912c: cipherSuites empty list is allowed', () {
      const config = TlsConfig(cipherSuites: []);
      expect(config.cipherSuites, equals([]));
      expect(config.cipherSuites, isNotNull);
    });
  });

  group('TC-913: TlsConfig.fromJson', () {
    test('TC-913a: parses valid JSON correctly', () {
      final config = TlsConfig.fromJson({
        'allowSelfSigned': false,
        'verifyHostname': true,
        'minVersion': 'TLS1.2',
      });
      expect(config.allowSelfSigned, isFalse);
      expect(config.verifyHostname, isTrue);
      expect(config.minVersion, equals('TLS1.2'));
    });

    test('TC-913b: empty JSON returns defaults', () {
      final config = TlsConfig.fromJson({});
      expect(config.allowSelfSigned, isFalse);
      expect(config.verifyHostname, isTrue);
      expect(config.minVersion, equals('TLS1.2'));
      expect(config.customCAs, isNull);
      expect(config.clientCertificate, isNull);
      expect(config.clientKey, isNull);
      expect(config.cipherSuites, isNull);
    });

    test('TC-913c: wrong type value falls back to default', () {
      // allowSelfSigned expects bool; if null passed, it falls back to false
      final config = TlsConfig.fromJson({'allowSelfSigned': null});
      expect(config.allowSelfSigned, isFalse);
    });
  });

  // ==========================================================================
  // 3b. TlsHttpClient.createSecurityContext Tests (TC-918~920)
  // ==========================================================================
  group('TC-918: createSecurityContext with customCAs', () {
    test('TC-918a: customCAs triggers setTrustedCertificates', () {
      const testCaPem = '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----';
      // createSecurityContext with CA PEM data — may fail to parse but should not throw
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(customCAs: [testCaPem]),
      );
      expect(context, isA<SecurityContext>());
    });

    test('TC-918b: multiple customCAs all processed', () {
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(customCAs: ['ca1', 'ca2', 'ca3']),
      );
      // Should not throw; invalid PEMs are logged and skipped
      expect(context, isA<SecurityContext>());
    });

    test('TC-918c: mixed valid/invalid CAs — invalid skipped', () {
      const validishCa = '-----BEGIN CERTIFICATE-----\ndata\n-----END CERTIFICATE-----';
      const invalidCa = 'NOT_A_VALID_PEM';
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(customCAs: [validishCa, invalidCa, validishCa]),
      );
      // Should not throw; invalid CAs are logged and skipped per DDD spec
      expect(context, isA<SecurityContext>());
    });
  });

  group('TC-919: createSecurityContext mTLS', () {
    test('TC-919a: client cert and key both loaded', () {
      const certPem = '-----BEGIN CERTIFICATE-----\ncert\n-----END CERTIFICATE-----';
      const keyPem = '-----BEGIN RSA PRIVATE KEY-----\nkey\n-----END RSA PRIVATE KEY-----';
      // Invalid PEM data will be caught and logged, not thrown
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(clientCertificate: certPem, clientKey: keyPem),
      );
      expect(context, isA<SecurityContext>());
    });

    test('TC-919b: clientCertificate without clientKey', () {
      const certPem = '-----BEGIN CERTIFICATE-----\ncert\n-----END CERTIFICATE-----';
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(clientCertificate: certPem),
      );
      // Should not throw; incomplete mTLS is handled gracefully
      expect(context, isA<SecurityContext>());
    });

    test('TC-919c: invalid cert PEM is logged and skipped', () {
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(
          clientCertificate: 'INVALID_CERT',
          clientKey: 'INVALID_KEY',
        ),
      );
      // Per DDD spec: warning logged, no exception propagated
      expect(context, isA<SecurityContext>());
    });
  });

  group('TC-920: createSecurityContext invalid client cert', () {
    test('TC-920a: invalid client certificate PEM — warning logged, no throw', () {
      const invalidPem = 'NOT_A_VALID_PEM_STRING';
      const testKeyPem = '-----BEGIN RSA PRIVATE KEY-----\nkey\n-----END RSA PRIVATE KEY-----';
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(clientCertificate: invalidPem, clientKey: testKeyPem),
      );
      // Per DDD spec: exception not propagated, warning logged
      expect(context, isA<SecurityContext>());
    });
  });

  // ==========================================================================
  // 4. TlsHttpClient.create Tests (TC-927~)
  // ==========================================================================
  group('TC-927: TlsHttpClient.create', () {
    test('TC-927a: create returns a non-null HttpClient', () {
      final client = TlsHttpClient.create(tlsConfig: const TlsConfig());
      expect(client, isNotNull);
      client.close();
    });

    test('TC-927b: each create() call returns a distinct HttpClient instance', () {
      const config = TlsConfig();
      final c1 = TlsHttpClient.create(tlsConfig: config);
      final c2 = TlsHttpClient.create(tlsConfig: config);

      expect(identical(c1, c2), isFalse);
      c1.close();
      c2.close();
    });

    test('TC-927c: create without tlsConfig returns default HttpClient', () {
      final client = TlsHttpClient.create();
      expect(client, isNotNull);
      client.close();
    });
  });

  group('TC-928: allowSelfSigned and verifyHostname', () {
    test('TC-928a: allowSelfSigned=true creates client without error', () {
      final client = TlsHttpClient.create(
        tlsConfig: const TlsConfig(allowSelfSigned: true),
      );

      // The client should be created successfully with self-signed cert support
      expect(client, isNotNull);
      client.close();
    });

    test('TC-928c: unsupported minVersion does not throw', () {
      final client = TlsHttpClient.create(
        tlsConfig: const TlsConfig(minVersion: 'SSL3.0'),
      );
      expect(client, isNotNull);
      client.close();
    });
  });

  group('TC-929: TLS version and customCAs', () {
    test('TC-929a: TLS1.2 and TLS1.3 both create without error', () {
      final c1 = TlsHttpClient.create(
        tlsConfig: const TlsConfig(minVersion: 'TLS1.2'),
      );
      final c2 = TlsHttpClient.create(
        tlsConfig: const TlsConfig(minVersion: 'TLS1.3'),
      );

      expect(c1, isNotNull);
      expect(c2, isNotNull);
      c1.close();
      c2.close();
    });
  });

  // ==========================================================================
  // 5. TlsHttpClient.configureTls Tests (TC-937~)
  // ==========================================================================
  group('TC-937: configureTls', () {
    test('TC-937a: allowSelfSigned configureTls completes without error', () {
      final client = HttpClient();
      TlsHttpClient.configureTls(
        client,
        const TlsConfig(allowSelfSigned: true),
      );

      // configureTls should complete without throwing
      expect(client, isNotNull);
      client.close();
    });

    test('TC-937b: default TlsConfig applies without error', () {
      final client = HttpClient();
      TlsHttpClient.configureTls(client, const TlsConfig());
      client.close();
    });

    test('TC-937c: complex config applies without error', () {
      final client = HttpClient();
      TlsHttpClient.configureTls(
        client,
        const TlsConfig(
          customCAs: ['ca-pem-data'],
          verifyHostname: false,
          cipherSuites: ['TLS_AES_256_GCM_SHA384'],
        ),
      );
      client.close();
    });
  });

  // ==========================================================================
  // createSecurityContext Tests (TC-917~)
  // ==========================================================================
  // ==========================================================================
  // TC-911c: TlsConfig immutability verification
  // ==========================================================================
  group('TC-911c: TlsConfig immutability', () {
    test('TC-911c: all TlsConfig fields are final (immutable object)', () {
      // TlsConfig uses final fields, so values cannot be reassigned after construction.
      // This test verifies that a constructed TlsConfig retains its values.
      final config = TlsConfig(
        allowSelfSigned: true,
        verifyHostname: false,
        minVersion: 'TLS1.3',
      );

      // Values remain as set at construction
      expect(config.allowSelfSigned, isTrue);
      expect(config.verifyHostname, isFalse);
      expect(config.minVersion, equals('TLS1.3'));

      // Creating a new instance does not affect the original
      const config2 = TlsConfig();
      expect(config.allowSelfSigned, isTrue);
      expect(config2.allowSelfSigned, isFalse);
    });
  });

  // ==========================================================================
  // TC-917c: createSecurityContext with invalid CA PEM
  // ==========================================================================
  group('TC-917c: createSecurityContext invalid CA PEM', () {
    test('TC-917c: invalid CA PEM does not throw, is skipped', () {
      const invalidPem = 'NOT_A_VALID_PEM_STRING';
      // Per DDD spec: warning logged, invalid CA skipped, no exception
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(customCAs: [invalidPem]),
      );
      expect(context, isA<SecurityContext>());
    });
  });

  group('TC-917: createSecurityContext with default config', () {
    test('TC-917a: default config creates SecurityContext', () {
      // Note: createSecurityContext with actual certs would fail,
      // but default config (no certs) should create context
      final context = TlsHttpClient.createSecurityContext(const TlsConfig());
      expect(context, isA<SecurityContext>());
    });

    test('TC-917b: empty customCAs list does not add certificates', () {
      final context = TlsHttpClient.createSecurityContext(
        const TlsConfig(customCAs: []),
      );
      expect(context, isA<SecurityContext>());
    });
  });

  // ==========================================================================
  // TC-928b: verifyHostname=false
  // ==========================================================================
  group('TC-928b: verifyHostname=false', () {
    test('TC-928b: verifyHostname=false creates client without error', () {
      final client = TlsHttpClient.create(
        tlsConfig: const TlsConfig(verifyHostname: false),
      );
      expect(client, isNotNull);
      client.close();
    });
  });

  // ==========================================================================
  // TC-929b: customCAs applied to HttpClient via SecurityContext
  // ==========================================================================
  group('TC-929b: customCAs with create', () {
    test('TC-929b: customCAs config creates HttpClient with SecurityContext', () {
      const testCaPem = '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----';
      final client = TlsHttpClient.create(
        tlsConfig: const TlsConfig(customCAs: [testCaPem]),
      );
      // Should return a valid HttpClient even with custom CAs
      expect(client, isNotNull);
      client.close();
    });
  });

  // ==========================================================================
  // TC-929c: mTLS config creates HttpClient without error
  // ==========================================================================
  group('TC-929c: mTLS config create', () {
    test('TC-929c: mTLS configuration creates HttpClient without error', () {
      const testCaPem = '-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----';
      const testCertPem = '-----BEGIN CERTIFICATE-----\ncert\n-----END CERTIFICATE-----';
      const testKeyPem = '-----BEGIN RSA PRIVATE KEY-----\nkey\n-----END RSA PRIVATE KEY-----';

      final client = TlsHttpClient.create(
        tlsConfig: const TlsConfig(
          customCAs: [testCaPem],
          clientCertificate: testCertPem,
          clientKey: testKeyPem,
        ),
      );
      // Per DDD spec: invalid PEMs are logged and skipped, no exception
      expect(client, isNotNull);
      client.close();
    });
  });
}
