import 'package:test/test.dart';
import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart'
    hide FlowDefinition, TriggerType, RetryConfig, FlowError;

void main() {
  late BundleFlowReadAdapter adapter;

  setUp(() {
    adapter = BundleFlowReadAdapter();
  });

  // =========================================================================
  // Helper Factories
  // =========================================================================

  McpBundle _makeBundle({
    String id = 'com.example.flow',
    String name = 'My Flow',
    String version = '1.0.0',
    String? description = 'Test flow',
    FlowSection? flow,
    bool includeFlow = true,
  }) {
    return McpBundle(
      manifest: BundleManifest(
        id: id,
        name: name,
        version: version,
        description: description,
      ),
      flow: includeFlow ? (flow ?? const FlowSection()) : null,
    );
  }

  FlowDefinition _makeFlowDef({
    String id = 'flow_1',
    String name = 'Flow One',
    String? description,
    FlowTrigger? trigger,
    List<FlowStep> steps = const [],
    List<FlowParameter> inputs = const [],
    FlowOutput? output,
    int? timeoutMs,
    RetryConfig? retry,
  }) {
    return FlowDefinition(
      id: id,
      name: name,
      description: description,
      trigger: trigger,
      steps: steps,
      inputs: inputs,
      output: output,
      timeoutMs: timeoutMs,
      retry: retry,
    );
  }

  // =========================================================================
  // 3.1 FlowPort.toDefinition()
  // =========================================================================

  group('FlowPort.toDefinition()', () {
    test('TC-V11-001: Full bundle to Flow definition JSON', () async {
      final bundle = _makeBundle(
        flow: FlowSection(
          schemaVersion: '1.1.0',
          flows: [_makeFlowDef()],
          sharedState: {'temp': 0},
          errorHandlers: [
            ErrorHandler(
              name: 'default_handler',
              patterns: ['*'],
              action: {'type': 'log'},
              continueFlow: true,
            ),
          ],
        ),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data, isNotNull);
      expect(result.data!['id'], equals('com.example.flow'));
      expect(result.data!['name'], equals('My Flow'));
      expect(result.data!['version'], equals('1.0.0'));
      expect(result.data!['description'], equals('Test flow'));
      expect(result.data!['schemaVersion'], equals('1.1.0'));
      expect(result.data!['flows'], isList);
      expect(result.data!['sharedState'], isMap);
      expect(result.data!['errorHandlers'], isList);
    });

    test('TC-V11-002: Manifest field mapping — id, name, version, description',
        () async {
      final bundle = _makeBundle(
        id: 'com.example.specific',
        name: 'Specific Flow',
        version: '2.0.0',
        description: 'A specific test',
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!['id'], equals('com.example.specific'));
      expect(result.data!['name'], equals('Specific Flow'));
      expect(result.data!['version'], equals('2.0.0'));
      expect(result.data!['description'], equals('A specific test'));
    });

    test('TC-V11-002b: Description absent — key not present', () async {
      final bundle = _makeBundle(description: null);

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!.containsKey('description'), isFalse);
    });

    test('TC-V11-003: FlowSection → flows mapping', () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(id: 'f1', name: 'F1'),
          _makeFlowDef(id: 'f2', name: 'F2'),
          _makeFlowDef(id: 'f3', name: 'F3'),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final flows = result.data!['flows'] as List;
      expect(flows, hasLength(3));
      expect(flows[0]['id'], equals('f1'));
      expect(flows[1]['id'], equals('f2'));
      expect(flows[2]['id'], equals('f3'));
    });

    test('TC-V11-003b: Empty flows list', () async {
      final bundle = _makeBundle(flow: const FlowSection(flows: []));

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!['flows'], isEmpty);
    });

    test('TC-V11-004: FlowSection → sharedState mapping', () async {
      final bundle = _makeBundle(
        flow: FlowSection(sharedState: {'temp': 0, 'mode': 'auto'}),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!['sharedState'], equals({'temp': 0, 'mode': 'auto'}));
    });

    test('TC-V11-004b: Empty sharedState', () async {
      final bundle = _makeBundle(flow: const FlowSection(sharedState: {}));

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!.containsKey('sharedState'), isFalse);
    });

    test('TC-V11-005: FlowSection → errorHandlers mapping', () async {
      final bundle = _makeBundle(
        flow: FlowSection(errorHandlers: [
          ErrorHandler(
            name: 'handler1',
            patterns: ['timeout'],
            action: {'type': 'retry'},
            continueFlow: true,
          ),
          ErrorHandler(
            name: 'handler2',
            patterns: ['fatal'],
            action: {'type': 'abort'},
          ),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final handlers = result.data!['errorHandlers'] as List;
      expect(handlers, hasLength(2));
      expect(handlers[0]['name'], equals('handler1'));
      expect(handlers[1]['name'], equals('handler2'));
    });

    test('TC-V11-005b: Empty errorHandlers', () async {
      final bundle = _makeBundle(flow: const FlowSection(errorHandlers: []));

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!.containsKey('errorHandlers'), isFalse);
    });

    test('TC-V11-006: FlowDefinition → steps delegation to BundleStepAdapter',
        () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(
            steps: [
              FlowStep(
                  id: 's1',
                  type: StepType.action,
                  config: {'actionType': 'gpioWrite', 'params': {}}),
              FlowStep(
                  id: 's2',
                  type: StepType.condition,
                  config: {'expression': '{{temp > 80}}'}),
              FlowStep(
                  id: 's3',
                  type: StepType.setVar,
                  config: {'variable': 'x', 'value': '1'}),
              FlowStep(
                  id: 's4',
                  type: StepType.wait,
                  config: {'durationMs': 1000}),
              FlowStep(
                  id: 's5',
                  type: StepType.output,
                  config: {'expression': '{{result}}'}),
            ],
          ),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final steps = (result.data!['flows'] as List)[0]['steps'] as List;
      expect(steps, hasLength(5));
      expect(steps[0]['type'], equals('action'));
      expect(steps[1]['type'], equals('condition'));
      expect(steps[2]['type'], equals('setVar'));
      expect(steps[3]['type'], equals('wait'));
      expect(steps[4]['type'], equals('output'));
    });

    test('TC-V11-007: FlowDefinition → trigger mapping', () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(
            trigger: FlowTrigger(
              type: TriggerType.schedule,
              config: {'interval': '5s'},
            ),
          ),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final trigger = (result.data!['flows'] as List)[0]['trigger'] as Map;
      expect(trigger['type'], equals('schedule'));
      expect(trigger['config'], equals({'interval': '5s'}));
    });

    test('TC-V11-007b: Trigger is null — trigger key absent', () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [_makeFlowDef(trigger: null)]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final flowMap = (result.data!['flows'] as List)[0] as Map;
      expect(flowMap.containsKey('trigger'), isFalse);
    });

    test('TC-V11-007c: All TriggerType values mapped correctly', () async {
      final types = [
        TriggerType.manual,
        TriggerType.schedule,
        TriggerType.event,
        TriggerType.webhook,
        TriggerType.startup,
        TriggerType.onChange,
      ];

      for (final triggerType in types) {
        final bundle = _makeBundle(
          flow: FlowSection(flows: [
            _makeFlowDef(trigger: FlowTrigger(type: triggerType)),
          ]),
        );

        final result = await adapter.toDefinition(bundle);
        final trigger = (result.data!['flows'] as List)[0]['trigger'] as Map;
        expect(trigger['type'], equals(triggerType.name),
            reason: 'TriggerType.${triggerType.name} should map correctly');
      }
    });

    test('TC-V11-007d: Unknown TriggerType → warning', () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(trigger: FlowTrigger(type: TriggerType.unknown)),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final trigger = (result.data!['flows'] as List)[0]['trigger'] as Map;
      expect(trigger['type'], equals('unknown'));
      expect(result.warnings, isNotNull);
      expect(result.warnings!.any((w) => w.code == 'INVALID_TRIGGER_TYPE'),
          isTrue);
    });

    test('TC-V11-008: FlowDefinition → inputs and output mapping', () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(
            inputs: [
              FlowParameter(name: 'threshold', type: 'number', required: true),
              FlowParameter(
                  name: 'label', type: 'string', defaultValue: 'default'),
            ],
            output: FlowOutput(type: 'object', schema: {'type': 'object'}),
          ),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final flow = (result.data!['flows'] as List)[0] as Map;
      final inputs = flow['inputs'] as List;
      expect(inputs, hasLength(2));
      expect(inputs[0]['name'], equals('threshold'));
      expect(flow['output']['type'], equals('object'));
    });

    test('TC-V11-008b: Empty inputs, no output — keys absent', () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [_makeFlowDef()]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final flow = (result.data!['flows'] as List)[0] as Map;
      expect(flow.containsKey('inputs'), isFalse);
      expect(flow.containsKey('output'), isFalse);
    });

    test('TC-V11-009: FlowDefinition → retry and timeoutMs mapping',
        () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(
            timeoutMs: 30000,
            retry: RetryConfig(
              maxAttempts: 5,
              initialDelayMs: 2000,
              maxDelayMs: 60000,
              backoffMultiplier: 3.0,
              retryOn: ['TIMEOUT'],
            ),
          ),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final flow = (result.data!['flows'] as List)[0] as Map;
      expect(flow['timeoutMs'], equals(30000));
      expect(flow['retry']['maxAttempts'], equals(5));
      expect(flow['retry']['retryOn'], contains('TIMEOUT'));
    });

    test('TC-V11-009b: Retry and timeout null — keys absent', () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [_makeFlowDef()]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final flow = (result.data!['flows'] as List)[0] as Map;
      expect(flow.containsKey('timeoutMs'), isFalse);
      expect(flow.containsKey('retry'), isFalse);
    });

    test('TC-V11-010: Bundle with no FlowSection → MISSING_FLOW_SECTION',
        () async {
      final bundle = _makeBundle(includeFlow: false);

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(result.error!.code, equals('MISSING_FLOW_SECTION'));
    });

    test('TC-V11-011: Missing required manifest fields → INVALID_MANIFEST',
        () async {
      final bundle = _makeBundle(name: '', version: '1.0.0');

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isFalse);
      expect(result.error!.code, equals('INVALID_MANIFEST'));
    });

    test('TC-V11-011b: Empty version → INVALID_MANIFEST', () async {
      final bundle = _makeBundle(name: 'Test', version: '');

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isFalse);
      expect(result.error!.code, equals('INVALID_MANIFEST'));
    });

    test(
        'TC-V11-012: FlowDefinition with missing id or name → skip with warning',
        () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(id: '', name: 'Valid Name'),
          _makeFlowDef(id: 'valid_id', name: ''),
          _makeFlowDef(id: 'good', name: 'Good Flow'),
        ]),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      final flows = result.data!['flows'] as List;
      expect(flows, hasLength(1));
      expect(flows[0]['id'], equals('good'));
      expect(result.warnings, isNotNull);
      expect(result.warnings, hasLength(2));
      expect(
          result.warnings!
              .every((w) => w.code == 'INVALID_FLOW_DEFINITION'),
          isTrue);
    });

    test('TC-V11-013: schemaVersion mapping', () async {
      final bundle = _makeBundle(
        flow: FlowSection(schemaVersion: '1.1.0'),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!['schemaVersion'], equals('1.1.0'));
    });

    test('TC-V11-013b: Default schemaVersion', () async {
      final bundle = _makeBundle(flow: const FlowSection());

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!['schemaVersion'], equals('1.0.0'));
    });
  });

  // =========================================================================
  // 3.2 FlowPort.toFlowInfo()
  // =========================================================================

  group('FlowPort.toFlowInfo()', () {
    test('TC-V11-014: Full manifest to flow info', () async {
      final bundle = _makeBundle(
        flow: FlowSection(
          flows: [
            _makeFlowDef(id: 'f1', name: 'F1'),
            _makeFlowDef(id: 'f2', name: 'F2'),
            _makeFlowDef(id: 'f3', name: 'F3'),
          ],
          sharedState: {'temp': 0, 'mode': 'auto'},
        ),
      );

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isTrue);
      expect(result.data!['id'], equals('com.example.flow'));
      expect(result.data!['name'], equals('My Flow'));
      expect(result.data!['version'], equals('1.0.0'));
      expect(result.data!['description'], equals('Test flow'));
      final flows = result.data!['flows'] as List;
      expect(flows, hasLength(3));
      expect(result.data!['sharedStateKeys'], containsAll(['temp', 'mode']));
    });

    test(
        'TC-V11-015: Flow summary — id, name, description, trigger, inputCount, hasOutput',
        () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [
          _makeFlowDef(
            id: 'monitor',
            name: 'Monitor',
            description: 'Monitors temperature',
            trigger:
                FlowTrigger(type: TriggerType.schedule, config: {'interval': '5s'}),
            inputs: [
              FlowParameter(name: 'p1', type: 'number'),
              FlowParameter(name: 'p2', type: 'string'),
            ],
            output: FlowOutput(type: 'object'),
          ),
        ]),
      );

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isTrue);
      final summary = (result.data!['flows'] as List)[0] as Map;
      expect(summary['id'], equals('monitor'));
      expect(summary['name'], equals('Monitor'));
      expect(summary['description'], equals('Monitors temperature'));
      expect(summary['trigger']['type'], equals('schedule'));
      expect(summary['trigger']['config'], equals({'interval': '5s'}));
      expect(summary['inputCount'], equals(2));
      expect(summary['hasOutput'], isTrue);
    });

    test(
        'TC-V11-015b: Flow with no trigger, no inputs, no output',
        () async {
      final bundle = _makeBundle(
        flow: FlowSection(flows: [_makeFlowDef()]),
      );

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isTrue);
      final summary = (result.data!['flows'] as List)[0] as Map;
      expect(summary.containsKey('trigger'), isFalse);
      expect(summary['inputCount'], equals(0));
      expect(summary['hasOutput'], isFalse);
    });

    test('TC-V11-016: sharedStateKeys in flow info', () async {
      final bundle = _makeBundle(
        flow: FlowSection(sharedState: {'temp': 0, 'mode': 'auto'}),
      );

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isTrue);
      expect(result.data!['sharedStateKeys'], containsAll(['temp', 'mode']));
    });

    test('TC-V11-016b: Empty sharedState → sharedStateKeys absent', () async {
      final bundle = _makeBundle(flow: const FlowSection());

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isTrue);
      expect(result.data!.containsKey('sharedStateKeys'), isFalse);
    });

    test('TC-V11-017: Flow info from minimal manifest', () async {
      final bundle = _makeBundle(
        id: '',
        name: 'Minimal',
        version: '0.1.0',
        description: null,
      );

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isTrue);
      expect(result.data!.containsKey('id'), isFalse);
      expect(result.data!['name'], equals('Minimal'));
      expect(result.data!['version'], equals('0.1.0'));
      expect(result.data!['flows'], isEmpty);
    });

    test('TC-V11-018: Missing required manifest fields → INVALID_MANIFEST',
        () async {
      final bundle = _makeBundle(name: '', version: '1.0.0');

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isFalse);
      expect(result.error!.code, equals('INVALID_MANIFEST'));
    });

    test('TC-V11-018b: Missing FlowSection → MISSING_FLOW_SECTION', () async {
      final bundle = _makeBundle(includeFlow: false);

      final result = await adapter.toFlowInfo(bundle);

      expect(result.success, isFalse);
      expect(result.error!.code, equals('MISSING_FLOW_SECTION'));
    });
  });

  // =========================================================================
  // 3.3 FlowPort.fromDefinition() — Unsupported
  // =========================================================================

  group('FlowPort.fromDefinition() — Unsupported', () {
    test('TC-V11-019: fromDefinition() throws UnsupportedError', () {
      expect(
        () => adapter.fromDefinition({}),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // =========================================================================
  // 7. Interface Compliance
  // =========================================================================

  group('Interface Compliance', () {
    test('TC-V11-044: BundleFlowReadAdapter is FlowPort', () {
      expect(adapter, isA<FlowPort>());
    });
  });

  // =========================================================================
  // 6. Round-Trip (partial — read side)
  // =========================================================================

  group('Round-Trip', () {
    test('TC-V11-043: Write → Read round-trip', () async {
      final originalJson = <String, dynamic>{
        'id': 'com.example.roundtrip',
        'name': 'Round Trip Flow',
        'version': '1.0.0',
        'description': 'Round-trip test',
        'schemaVersion': '1.1.0',
        'flows': [
          {
            'id': 'main_flow',
            'name': 'Main Flow',
            'description': 'Primary flow',
            'trigger': {
              'type': 'schedule',
              'config': {'interval': '10s'},
            },
            'steps': [
              {
                'id': 'step1',
                'type': 'action',
                'config': {'actionType': 'gpioWrite', 'params': {'pin': 17}},
              },
            ],
            'inputs': [
              {'name': 'threshold', 'type': 'number', 'required': true},
            ],
            'output': {'type': 'boolean'},
            'timeoutMs': 5000,
            'retry': {
              'maxAttempts': 3,
              'initialDelayMs': 1000,
              'maxDelayMs': 30000,
              'backoffMultiplier': 2.0,
            },
          },
        ],
        'sharedState': {'counter': 0},
        'errorHandlers': [
          {
            'name': 'default',
            'patterns': ['*'],
            'action': {'type': 'log'},
            'continueFlow': true,
          },
        ],
      };

      // Write path
      final writeAdapter = BundleFlowWriteAdapter();
      final writeResult = await writeAdapter.fromDefinition(originalJson);
      expect(writeResult.success, isTrue);

      // Assemble McpBundle
      final output = writeResult.data!;
      final bundle = McpBundle(
        manifest: BundleManifest(
          id: output.manifestMetadata['id'] as String? ?? '',
          name: output.manifestMetadata['name'] as String? ?? '',
          version: output.manifestMetadata['version'] as String? ?? '',
          description: output.manifestMetadata['description'] as String?,
        ),
        flow: output.flowSection,
      );

      // Read path
      final readResult = await adapter.toDefinition(bundle);
      expect(readResult.success, isTrue);

      final roundTripped = readResult.data!;
      expect(roundTripped['id'], equals(originalJson['id']));
      expect(roundTripped['name'], equals(originalJson['name']));
      expect(roundTripped['version'], equals(originalJson['version']));
      expect(roundTripped['schemaVersion'], equals(originalJson['schemaVersion']));

      final rtFlows = roundTripped['flows'] as List;
      expect(rtFlows, hasLength(1));
      expect(rtFlows[0]['id'], equals('main_flow'));
      expect(rtFlows[0]['name'], equals('Main Flow'));
      expect(rtFlows[0]['trigger']['type'], equals('schedule'));
      expect(rtFlows[0]['steps'], hasLength(1));
      expect(roundTripped['sharedState'], equals({'counter': 0}));
      expect(roundTripped['errorHandlers'], hasLength(1));
    });
  });

  // =========================================================================
  // 8. Backward Compatibility
  // =========================================================================

  group('Backward Compatibility', () {
    test('TC-V11-047: v1.0 Flow definition loads without bundle adapter',
        () {
      // v1.0 FlowDefinition loaded via direct JSON parse — no adapter needed
      final v10Json = {
        'id': 'temp_monitor',
        'name': 'Temperature Monitor',
        'steps': [
          {
            'id': 's1',
            'type': 'action',
            'config': {'actionType': 'gpioWrite', 'params': {'pin': 17}},
          },
          {
            'id': 's2',
            'type': 'condition',
            'config': {'expression': '{{temp > 80}}'},
          },
        ],
        'inputs': [
          {'name': 'threshold', 'type': 'number'},
        ],
      };

      final flow = FlowDefinition.fromJson(v10Json);

      expect(flow.id, equals('temp_monitor'));
      expect(flow.name, equals('Temperature Monitor'));
      expect(flow.steps, hasLength(2));
      expect(flow.steps[0].type, equals(StepType.action));
      expect(flow.steps[1].type, equals(StepType.condition));
      expect(flow.inputs, hasLength(1));
      expect(flow.trigger, isNull);
      expect(flow.retry, isNull);
    });

    test('TC-V11-048: v1.0 definition through v1.1 read adapter', () async {
      final bundle = _makeBundle(
        flow: FlowSection(
          schemaVersion: '1.0.0',
          flows: [
            _makeFlowDef(
              trigger: FlowTrigger(type: TriggerType.startup),
              steps: [
                FlowStep(
                    id: 's1',
                    type: StepType.action,
                    config: {'actionType': 'gpioWrite'}),
              ],
            ),
          ],
        ),
      );

      final result = await adapter.toDefinition(bundle);

      expect(result.success, isTrue);
      expect(result.data!['schemaVersion'], equals('1.0.0'));
      final flows = result.data!['flows'] as List;
      expect(flows, hasLength(1));
      expect(flows[0]['trigger']['type'], equals('startup'));
    });
  });

  // =========================================================================
  // StubFlowPort
  // =========================================================================

  group('StubFlowPort', () {
    test('TC-V11-046: StubFlowPort returns valid responses', () async {
      final stub = StubFlowPort();
      final bundle = _makeBundle();

      final defResult = await stub.toDefinition(bundle);
      expect(defResult.success, isTrue);
      expect(defResult.data, isNotNull);
      expect(defResult.data!['name'], equals('My Flow'));

      final infoResult = await stub.toFlowInfo(bundle);
      expect(infoResult.success, isTrue);
      expect(infoResult.data, isNotNull);
      expect(infoResult.data!['name'], equals('My Flow'));

      final writeResult = await stub.fromDefinition({
        'id': 'test',
        'name': 'Test',
        'version': '1.0.0',
      });
      expect(writeResult.success, isTrue);
      expect(writeResult.data, isNotNull);
      expect(writeResult.data!.manifestMetadata['name'], equals('Test'));
    });
  });
}
