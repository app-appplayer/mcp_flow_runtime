import 'package:test/test.dart';
import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart'
    hide FlowDefinition, TriggerType, RetryConfig, FlowError;

void main() {
  late BundleFlowWriteAdapter adapter;

  setUp(() {
    adapter = BundleFlowWriteAdapter();
  });

  // =========================================================================
  // Helper
  // =========================================================================

  Map<String, dynamic> _makeDefinitionJson({
    String? id = 'com.example.flow',
    String? name = 'My Flow',
    String? version = '1.0.0',
    String? description = 'Test',
    String? schemaVersion = '1.1.0',
    List<Map<String, dynamic>>? flows,
    Map<String, dynamic>? sharedState,
    List<Map<String, dynamic>>? errorHandlers,
  }) {
    return <String, dynamic>{
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (version != null) 'version': version,
      if (description != null) 'description': description,
      if (schemaVersion != null) 'schemaVersion': schemaVersion,
      if (flows != null) 'flows': flows,
      if (sharedState != null) 'sharedState': sharedState,
      if (errorHandlers != null) 'errorHandlers': errorHandlers,
    };
  }

  // =========================================================================
  // 5.1 FlowPort.fromDefinition()
  // =========================================================================

  group('FlowPort.fromDefinition()', () {
    test('TC-V11-036: Full definition to FlowWriteOutput', () async {
      final json = _makeDefinitionJson(
        flows: [
          {
            'id': 'f1',
            'name': 'Flow One',
            'steps': [
              {
                'id': 's1',
                'type': 'action',
                'config': {'actionType': 'gpioWrite'},
              },
            ],
          },
        ],
        sharedState: {'temp': 0},
        errorHandlers: [
          {
            'name': 'default',
            'patterns': ['*'],
            'action': {'type': 'log'},
            'continueFlow': true,
          },
        ],
      );

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(result.data, isNotNull);

      final output = result.data!;
      expect(output.flowSection.flows, hasLength(1));
      expect(output.flowSection.flows[0].id, equals('f1'));
      expect(output.flowSection.sharedState, equals({'temp': 0}));
      expect(output.flowSection.errorHandlers, hasLength(1));
      expect(output.manifestMetadata['id'], equals('com.example.flow'));
      expect(output.manifestMetadata['name'], equals('My Flow'));
      expect(output.manifestMetadata['version'], equals('1.0.0'));
      expect(output.manifestMetadata['description'], equals('Test'));
    });

    test('TC-V11-037: Metadata extraction — id, name, version, description',
        () async {
      final json = _makeDefinitionJson(
        id: 'com.example.specific',
        name: 'Specific',
        version: '2.0.0',
        description: 'Detailed',
      );

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(
          result.data!.manifestMetadata['id'], equals('com.example.specific'));
      expect(result.data!.manifestMetadata['name'], equals('Specific'));
      expect(result.data!.manifestMetadata['version'], equals('2.0.0'));
      expect(result.data!.manifestMetadata['description'], equals('Detailed'));
    });

    test('TC-V11-037b: Description absent → key not in manifestMetadata',
        () async {
      final json = _makeDefinitionJson(description: null);

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(
          result.data!.manifestMetadata.containsKey('description'), isFalse);
    });

    test('TC-V11-038: FlowSection extraction — flows', () async {
      final json = _makeDefinitionJson(
        flows: [
          {'id': 'f1', 'name': 'F1'},
          {'id': 'f2', 'name': 'F2'},
          {'id': 'f3', 'name': 'F3'},
        ],
      );

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(result.data!.flowSection.flows, hasLength(3));
      expect(result.data!.flowSection.flows[0].id, equals('f1'));
      expect(result.data!.flowSection.flows[1].id, equals('f2'));
      expect(result.data!.flowSection.flows[2].id, equals('f3'));
    });

    test('TC-V11-038b: Empty flows → flowSection.flows is empty', () async {
      final json = _makeDefinitionJson(flows: []);

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(result.data!.flowSection.flows, isEmpty);
    });

    test(
        'TC-V11-039: FlowSection extraction — sharedState and errorHandlers',
        () async {
      final json = _makeDefinitionJson(
        sharedState: {'temp': 25, 'mode': 'auto'},
        errorHandlers: [
          {
            'name': 'h1',
            'patterns': ['timeout'],
            'action': {'type': 'retry'},
          },
          {
            'name': 'h2',
            'patterns': ['fatal'],
            'action': {'type': 'abort'},
          },
        ],
      );

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(result.data!.flowSection.sharedState,
          equals({'temp': 25, 'mode': 'auto'}));
      expect(result.data!.flowSection.errorHandlers, hasLength(2));
      expect(result.data!.flowSection.errorHandlers[0].name, equals('h1'));
    });

    test('TC-V11-039b: Both absent → defaults', () async {
      final json = _makeDefinitionJson();

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(result.data!.flowSection.sharedState, isEmpty);
      expect(result.data!.flowSection.errorHandlers, isEmpty);
    });

    test('TC-V11-040: schemaVersion extraction', () async {
      final json = _makeDefinitionJson(schemaVersion: '1.1.0');

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(result.data!.flowSection.schemaVersion, equals('1.1.0'));
    });

    test('TC-V11-040b: schemaVersion absent → default "1.0.0"', () async {
      final json = _makeDefinitionJson(schemaVersion: null);

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      expect(result.data!.flowSection.schemaVersion, equals('1.0.0'));
    });
  });

  // =========================================================================
  // 5.2 Unsupported Methods
  // =========================================================================

  group('Unsupported Methods', () {
    test('TC-V11-041: toDefinition() throws UnsupportedError', () {
      final bundle = McpBundle(
        manifest: BundleManifest(
            id: 'test', name: 'Test', version: '1.0.0'),
      );

      expect(
        () => adapter.toDefinition(bundle),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('TC-V11-042: toFlowInfo() throws UnsupportedError', () {
      final bundle = McpBundle(
        manifest: BundleManifest(
            id: 'test', name: 'Test', version: '1.0.0'),
      );

      expect(
        () => adapter.toFlowInfo(bundle),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // =========================================================================
  // Interface Compliance
  // =========================================================================

  group('Interface Compliance', () {
    test('TC-V11-045: BundleFlowWriteAdapter is FlowPort', () {
      expect(adapter, isA<FlowPort>());
    });
  });

  // =========================================================================
  // Conversion Error Handling
  // =========================================================================

  group('Error Handling', () {
    test('fromDefinition with valid empty JSON succeeds', () async {
      final result = await adapter.fromDefinition({});

      expect(result.success, isTrue);
      expect(result.data!.flowSection.flows, isEmpty);
      expect(result.data!.manifestMetadata, isEmpty);
    });

    test('fromDefinition with complete flow definition', () async {
      final json = {
        'id': 'com.example.full',
        'name': 'Full Flow',
        'version': '1.0.0',
        'flows': [
          {
            'id': 'main',
            'name': 'Main',
            'trigger': {
              'type': 'schedule',
              'config': {'interval': '5s'},
            },
            'steps': [
              {
                'id': 's1',
                'type': 'action',
                'config': {'actionType': 'gpioWrite'},
              },
              {
                'id': 's2',
                'type': 'condition',
                'config': {'expression': '{{temp > 80}}'},
              },
            ],
            'inputs': [
              {'name': 'threshold', 'type': 'number', 'required': true},
            ],
            'output': {'type': 'boolean'},
            'timeoutMs': 5000,
            'retry': {'maxAttempts': 3},
          },
        ],
      };

      final result = await adapter.fromDefinition(json);

      expect(result.success, isTrue);
      final flow = result.data!.flowSection.flows[0];
      expect(flow.id, equals('main'));
      expect(flow.trigger, isNotNull);
      expect(flow.trigger!.type, equals(TriggerType.schedule));
      expect(flow.steps, hasLength(2));
      expect(flow.inputs, hasLength(1));
      expect(flow.output, isNotNull);
      expect(flow.timeoutMs, equals(5000));
      expect(flow.retry, isNotNull);
      expect(flow.retry!.maxAttempts, equals(3));
    });
  });
}
