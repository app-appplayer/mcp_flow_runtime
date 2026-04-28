import 'package:test/test.dart';
import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart'
    hide FlowDefinition, TriggerType, RetryConfig, FlowError;

void main() {
  // =========================================================================
  // Helper
  // =========================================================================

  FlowStep _makeStep({
    String id = 'step_1',
    required StepType type,
    Map<String, dynamic> config = const {},
    String? name,
    String? condition,
    List<String> next = const [],
    String? onError,
    int? timeoutMs,
    RetryConfig? retry,
  }) {
    return FlowStep(
      id: id,
      type: type,
      config: config,
      name: name,
      condition: condition,
      next: next,
      onError: onError,
      timeoutMs: timeoutMs,
      retry: retry,
    );
  }

  // =========================================================================
  // 4. BundleStepAdapter Tests
  // =========================================================================

  group('BundleStepAdapter — Step Type Tests', () {
    test('TC-V11-020: Step type — action', () {
      final step = _makeStep(
        type: StepType.action,
        config: {'actionType': 'gpioWrite', 'params': {'pin': 17}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('action'));
      expect(result.step['config']['actionType'], equals('gpioWrite'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-020b: action missing actionType → warning', () {
      final step = _makeStep(
        type: StepType.action,
        config: {'params': {'pin': 17}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('action'));
      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-021: Step type — skill', () {
      final step = _makeStep(
        type: StepType.skill,
        config: {'skillId': 'analyze', 'inputs': {'data': '{{raw}}'}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('skill'));
      expect(result.step['config']['skillId'], equals('analyze'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-021b: skill missing skillId → warning', () {
      final step = _makeStep(
        type: StepType.skill,
        config: {'inputs': {}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-022: Step type — flow', () {
      final step = _makeStep(
        type: StepType.flow,
        config: {'flowId': 'sub_flow', 'inputs': {}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('flow'));
      expect(result.step['config']['flowId'], equals('sub_flow'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-022b: flow missing flowId → warning', () {
      final step = _makeStep(
        type: StepType.flow,
        config: {'inputs': {}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
    });

    test('TC-V11-023: Step type — condition', () {
      final step = _makeStep(
        type: StepType.condition,
        config: {
          'expression': '{{temp > 80}}',
          'then': [
            {'id': 's2', 'type': 'action'}
          ],
          'else': [
            {'id': 's3', 'type': 'action'}
          ],
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('condition'));
      expect(result.step['config']['expression'], equals('{{temp > 80}}'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-023b: condition missing expression → warning', () {
      final step = _makeStep(
        type: StepType.condition,
        config: {
          'then': [],
          'else': [],
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
    });

    test('TC-V11-024: Step type — switchCase', () {
      final step = _makeStep(
        type: StepType.switchCase,
        config: {
          'expression': '{{mode}}',
          'cases': {
            'auto': [
              {'id': 'sa', 'type': 'action'}
            ],
          },
          'default': [
            {'id': 'sd', 'type': 'action'}
          ],
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('switchCase'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-024b: switchCase missing expression → warning', () {
      final step = _makeStep(
        type: StepType.switchCase,
        config: {
          'cases': {
            'auto': [
              {'id': 'sa', 'type': 'action'}
            ],
          },
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-025: Step type — parallel', () {
      final step = _makeStep(
        type: StepType.parallel,
        config: {
          'branches': [
            [
              {'id': 'b1s1', 'type': 'action'}
            ],
            [
              {'id': 'b2s1', 'type': 'action'}
            ],
          ],
          'joinMode': 'all',
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('parallel'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-025b: parallel missing branches → warning', () {
      final step = _makeStep(
        type: StepType.parallel,
        config: {'joinMode': 'all'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
    });

    test('TC-V11-026: Step type — loop', () {
      final step = _makeStep(
        type: StepType.loop,
        config: {
          'expression': '{{i < 10}}',
          'maxIterations': 100,
          'body': [
            {'id': 'ls1', 'type': 'action'}
          ],
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('loop'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-026b: loop — neither expression nor maxIterations → warning',
        () {
      final step = _makeStep(
        type: StepType.loop,
        config: {
          'body': [
            {'id': 'ls1', 'type': 'action'}
          ],
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
    });

    test('TC-V11-027: Step type — wait (durationMs)', () {
      final step = _makeStep(
        type: StepType.wait,
        config: {'durationMs': 5000},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('wait'));
      expect(result.step['config']['durationMs'], equals(5000));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-027b: wait — neither durationMs nor condition → warning', () {
      final step = _makeStep(
        type: StepType.wait,
        config: {'someOther': 'value'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-027c: Step type — wait (condition)', () {
      final step = _makeStep(
        type: StepType.wait,
        config: {'condition': '{{ready}}'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('wait'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-028: Step type — setVar', () {
      final step = _makeStep(
        type: StepType.setVar,
        config: {'variable': 'count', 'value': '{{count + 1}}'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('setVar'));
      expect(result.step['config']['variable'], equals('count'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-028b: setVar missing variable → warning', () {
      final step = _makeStep(
        type: StepType.setVar,
        config: {'value': '{{count + 1}}'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-029: Step type — transform', () {
      final step = _makeStep(
        type: StepType.transform,
        config: {
          'input': '{{raw}}',
          'expression': '{{raw * 0.01}}',
          'output': 'result',
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('transform'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-029b: transform missing input → warning', () {
      final step = _makeStep(
        type: StepType.transform,
        config: {'expression': '{{raw * 0.01}}', 'output': 'result'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-030: Step type — api', () {
      final step = _makeStep(
        type: StepType.api,
        config: {
          'url': 'https://api.example.com',
          'method': 'POST',
          'headers': {'Content-Type': 'application/json'},
          'body': {'key': 'value'},
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('api'));
      expect(result.step['config']['url'], equals('https://api.example.com'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-030b: api missing url → warning', () {
      final step = _makeStep(
        type: StepType.api,
        config: {'method': 'POST', 'body': {'key': 'value'}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-031: Step type — llm', () {
      final step = _makeStep(
        type: StepType.llm,
        config: {
          'provider': 'anthropic',
          'model': 'claude-sonnet-4-6',
          'prompt': 'analyze this data',
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('llm'));
      expect(result.step['config']['provider'], equals('anthropic'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-031b: llm missing provider → warning', () {
      final step = _makeStep(
        type: StepType.llm,
        config: {'model': 'claude-sonnet-4-6', 'prompt': 'analyze'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-032: Step type — output', () {
      final step = _makeStep(
        type: StepType.output,
        config: {
          'expression': '{{result}}',
          'schema': {'type': 'object'},
        },
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('output'));
      expect(result.step['config']['expression'], equals('{{result}}'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-032b: output missing expression → warning', () {
      final step = _makeStep(
        type: StepType.output,
        config: {'schema': {'type': 'object'}},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_CONFIG'));
    });

    test('TC-V11-033: Step type — unknown', () {
      final step = _makeStep(
        type: StepType.unknown,
        config: {'foo': 'bar'},
      );
      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['type'], equals('unknown'));
      expect(result.warnings, hasLength(1));
      expect(result.warnings[0].code, equals('INVALID_STEP_TYPE'));
    });
  });

  group('BundleStepAdapter — toStepList()', () {
    test('TC-V11-034: Multiple steps with mixed types', () {
      final steps = [
        _makeStep(
            id: 's1',
            type: StepType.action,
            config: {'actionType': 'gpioWrite'}),
        _makeStep(
            id: 's2',
            type: StepType.condition,
            config: {'expression': '{{x > 0}}'}),
        _makeStep(
            id: 's3',
            type: StepType.setVar,
            config: {'variable': 'x', 'value': '1'}),
        _makeStep(
            id: 's4', type: StepType.wait, config: {'durationMs': 100}),
        _makeStep(
            id: 's5',
            type: StepType.output,
            config: {'expression': '{{done}}'}),
      ];

      final result = BundleStepAdapter.toStepList(steps);

      expect(result.steps, hasLength(5));
      expect(result.steps[0]['id'], equals('s1'));
      expect(result.steps[1]['type'], equals('condition'));
      expect(result.steps[4]['type'], equals('output'));
      expect(result.warnings, isEmpty);
    });

    test('TC-V11-034b: Empty list → returns empty list', () {
      final result = BundleStepAdapter.toStepList([]);

      expect(result.steps, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });

  group('BundleStepAdapter — Common fields', () {
    test('TC-V11-035: condition, next, onError, timeoutMs, retry all mapped',
        () {
      final step = _makeStep(
        type: StepType.action,
        config: {'actionType': 'gpioWrite'},
        condition: '{{enabled}}',
        next: ['step2', 'step3'],
        onError: 'error_handler',
        timeoutMs: 5000,
        retry: RetryConfig(maxAttempts: 3, initialDelayMs: 500),
      );

      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step['condition'], equals('{{enabled}}'));
      expect(result.step['next'], equals(['step2', 'step3']));
      expect(result.step['onError'], equals('error_handler'));
      expect(result.step['timeoutMs'], equals(5000));
      expect(result.step['retry']['maxAttempts'], equals(3));
    });

    test('TC-V11-035b: All optional fields null → keys absent', () {
      final step = _makeStep(
        type: StepType.action,
        config: {'actionType': 'gpioWrite'},
      );

      final result = BundleStepAdapter.toStepMap(step);

      expect(result.step.containsKey('condition'), isFalse);
      expect(result.step.containsKey('next'), isFalse);
      expect(result.step.containsKey('onError'), isFalse);
      expect(result.step.containsKey('timeoutMs'), isFalse);
      expect(result.step.containsKey('retry'), isFalse);
    });
  });
}
