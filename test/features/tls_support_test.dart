import 'dart:convert';
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('TLS Support for Network Actions', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('httpGet with default TLS settings', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'response': {
            'type': 'object',
            'initial': {},
          },
        },
        'processes': [
          {
            'id': 'http_test',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'httpGet',
                'params': {
                  'url': 'https://api.example.com/test',
                },
                'bindTo': 'response',
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final response = runtime.getState('response') as Map;
      expect(response['status'], equals(200));
      expect(response['body'], contains('Mock response'));
    });

    test('httpGet with custom TLS configuration', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'response': {
            'type': 'object',
            'initial': {},
          },
        },
        'processes': [
          {
            'id': 'secure_http_test',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'httpGet',
                'params': {
                  'url': 'https://api.example.com/secure',
                  'tls': {
                    'allowSelfSigned': true,
                    'verifyHostname': true,
                    'minVersion': 'TLS1.3',
                  },
                },
                'bindTo': 'response',
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final response = runtime.getState('response') as Map;
      expect(response['status'], equals(200));
    });

    test('httpPost with TLS client certificate', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'response': {
            'type': 'object',
            'initial': {},
          },
        },
        'processes': [
          {
            'id': 'mutual_tls_test',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'httpPost',
                'params': {
                  'url': 'https://api.example.com/mutual-auth',
                  'body': {'data': 'test'},
                  'tls': {
                    'clientCertificate': '-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----',
                    'clientKey': '-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----',
                  },
                },
                'bindTo': 'response',
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final response = runtime.getState('response') as Map;
      expect(response['status'], equals(201));
      expect(response['body'], contains('Mock POST response'));
    });

    test('httpGet with custom CA certificates', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'response': {
            'type': 'object',
            'initial': {},
          },
        },
        'processes': [
          {
            'id': 'custom_ca_test',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'httpGet',
                'params': {
                  'url': 'https://test.local/api',
                  'tls': {
                    'customCAs': [
                      '-----BEGIN CERTIFICATE-----\nMIID...\n-----END CERTIFICATE-----',
                    ],
                  },
                },
                'bindTo': 'response',
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final response = runtime.getState('response') as Map;
      expect(response['status'], equals(200));
    });

    test('TLS configuration from flow configuration', () async {
      final flow = {
        'version': '1.0.0',
        'configuration': {
          'network': {
            'tls': {
              'defaultConfig': {
                'minVersion': 'TLS1.2',
                'verifyHostname': true,
              },
            },
          },
        },
        'state': {
          'response': {
            'type': 'object',
            'initial': {},
          },
        },
        'processes': [
          {
            'id': 'config_tls_test',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'httpGet',
                'params': {
                  'url': 'https://api.example.com/config-test',
                },
                'bindTo': 'response',
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final response = runtime.getState('response') as Map;
      expect(response['status'], equals(200));
    });

    test('httpPost with TLS and custom headers', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'response': {
            'type': 'object',
            'initial': {},
          },
        },
        'processes': [
          {
            'id': 'secure_post_test',
            'trigger': {'type': 'startup'},
            'steps': [
              {
                'action': 'httpPost',
                'params': {
                  'url': 'https://api.example.com/secure-post',
                  'headers': {
                    'Authorization': 'Bearer token123',
                    'Content-Type': 'application/json',
                  },
                  'body': {
                    'message': 'Secure data',
                  },
                  'tls': {
                    'minVersion': 'TLS1.2',
                    'cipherSuites': [
                      'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384',
                      'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256',
                    ],
                  },
                },
                'bindTo': 'response',
              },
            ],
          },
        ],
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final response = runtime.getState('response') as Map;
      expect(response['status'], equals(201));
      
      final bodyData = json.decode(response['body'] as String) as Map;
      expect(bodyData['received']['message'], equals('Secure data'));
    });
  });
}