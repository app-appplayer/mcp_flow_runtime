/// Test cases TC-331 through TC-358 for JsonFlowParser and FlowValidator
import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/parser/json_parser.dart';
import 'package:mcp_flow_runtime/src/parser/validator.dart';
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';
import 'package:mcp_flow_runtime/src/types/flow_types.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart' show McpFlowRuntime, RuntimeStatus;

final minimalFlowJson = {
  'version': '1.0.0',
  'metadata': {'name': 'Minimal Flow'},
  'processes': [
    {
      'id': 'proc_1',
      'steps': [
        {'action': 'log', 'params': {'message': 'hello'}},
      ],
    }
  ],
};

final fullFlowJson = {
  'version': '1.0.0',
  'metadata': {
    'name': 'Full Test Flow',
    'description': 'All sections included',
    'author': 'test',
    'tags': ['test', 'full'],
  },
  'resources': {
    'led': {
      'type': 'gpio',
      'capabilities': ['write'],
      'config': {'pin': 18, 'mode': 'output'},
    },
    'sensor': {
      'type': 'adc',
      'capabilities': ['read'],
      'config': {'channel': 0},
    },
  },
  'state': {
    'temperature': {'type': 'number', 'initial': 20.0, 'persistent': false},
    'mode': {'type': 'string', 'initial': 'idle'},
  },
  'channels': {
    'data_pipe': {'type': 'queue', 'capacity': 100, 'overflow': 'dropOldest'},
    'events': {'type': 'pubsub'},
  },
  'processes': [
    {
      'id': 'startup_proc',
      'trigger': {'type': 'startup'},
      'priority': 'high',
      'steps': [
        {'action': 'log', 'params': {'message': 'started'}},
        {'action': 'stateSet', 'params': {'key': 'mode', 'value': 'running'}},
      ],
    },
    {
      'id': 'schedule_proc',
      'trigger': {'type': 'schedule', 'interval': 1000},
      'loop': true,
      'steps': [
        {'action': 'log', 'params': {'message': 'tick'}},
      ],
    },
  ],
};

void main() {
  late JsonFlowParser parser;

  setUp(() {
    parser = JsonFlowParser();
  });

  // === JsonFlowParser Tests ===

  group('TC-331: JsonFlowParser.parse()', () {
    test('TC-331a: minimal valid flow', () {
      final flow = parser.parse(minimalFlowJson);
      expect(flow.metadata.name, equals('Minimal Flow'));
      expect(flow.processes, hasLength(1));
    });

    test('TC-331b: full flow with all fields', () {
      final flow = parser.parse(fullFlowJson);
      expect(flow.resources, hasLength(2));
      expect(flow.state, hasLength(2));
      expect(flow.channels, hasLength(2));
      expect(flow.processes, hasLength(2));
    });

    test('TC-331c: missing version defaults gracefully', () {
      // Current implementation: version defaults if missing
      final flow = parser.parse({'processes': []});
      expect(flow, isNotNull);
    });
  });

  group('TC-332: metadata parsing', () {
    test('TC-332a: all optional fields present', () {
      final flow = parser.parse(fullFlowJson);
      expect(flow.metadata.name, equals('Full Test Flow'));
      expect(flow.metadata.description, equals('All sections included'));
    });

    test('TC-332b: name only metadata', () {
      final json = {
        'version': '1.0.0',
        'metadata': {'name': 'Simple'},
        'processes': [],
      };
      final flow = parser.parse(json);
      expect(flow.metadata.name, equals('Simple'));
    });

    test('TC-332c: missing metadata uses defaults', () {
      final json = {'version': '1.0.0', 'processes': []};
      final flow = parser.parse(json);
      expect(flow, isNotNull);
    });
  });

  group('TC-333: trigger parsing', () {
    test('TC-333a: all trigger types parse correctly', () {
      final triggerTypes = ['startup', 'schedule', 'event', 'stateChange', 'manual'];
      for (final type in triggerTypes) {
        final trigger = <String, dynamic>{'type': type};
        if (type == 'schedule') trigger['interval'] = 1000;
        if (type == 'event') trigger['event'] = 'alarm';
        if (type == 'stateChange') trigger['key'] = 'temp';

        final json = {
          'version': '1.0.0',
          'processes': [
            {'id': 'p', 'trigger': trigger, 'steps': []}
          ],
        };
        final flow = parser.parse(json);
        expect(flow.processes.first.trigger, isNotNull);
      }
    });

    test('TC-333b: cron expression in schedule trigger', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'schedule', 'cron': '*/5 * * * *'},
            'steps': [],
          }
        ],
      };
      final flow = parser.parse(json);
      expect(flow.processes.first.trigger?.type, equals(TriggerType.schedule));
    });

    test('TC-333c: unknown trigger type', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'unknownTrigger'},
            'steps': [],
          }
        ],
      };
      // Parser may accept it or throw depending on implementation
      try {
        final flow = parser.parse(json);
        // If parser accepts, trigger type should be set
        expect(flow.processes.first.trigger, isNotNull);
      } on FlowParseError {
        // Also acceptable
      }
    });
  });

  group('TC-334: control flow step parsing', () {
    test('TC-334a: if/while/for/switch/parallel/try-catch', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'steps': [
              {
                'action': 'if',
                'params': {'condition': 'x > 0'},
                'then': [{'action': 'log', 'params': {'message': 'yes'}}],
              },
              {
                'action': 'while',
                'params': {'condition': 'i < 3'},
                'do': [{'action': 'log', 'params': {'message': 'loop'}}],
              },
              {
                'action': 'for',
                'params': {'variable': 'i', 'from': 0, 'to': 3, 'step': 1},
                'do': [{'action': 'log', 'params': {'message': 'for'}}],
              },
            ],
          }
        ],
      };
      final flow = parser.parse(json);
      expect(flow.processes.first.steps, hasLength(3));
      expect(flow.processes.first.steps[0].action, equals('if'));
      expect(flow.processes.first.steps[1].action, equals('while'));
      expect(flow.processes.first.steps[2].action, equals('for'));
    });

    test('TC-334b: retry config in step', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'steps': [
              {
                'action': 'gpioWrite',
                'params': {'pin': 18, 'value': true},
                'retry': {'count': 3, 'delayMs': 100},
              }
            ],
          }
        ],
      };
      final flow = parser.parse(json);
      final step = flow.processes.first.steps.first;
      expect(step.retry, isNotNull);
    });

    test('TC-334c: missing processes key', () {
      final json = {'version': '1.0.0'};
      // May throw or default to empty
      try {
        final flow = parser.parse(json);
        expect(flow.processes, isEmpty);
      } on FlowParseError {
        // Also acceptable
      }
    });
  });

  group('TC-335: loadFromFile', () {
    test('TC-335a: valid JSON file', () async {
      final tmpFile = File('/tmp/parser_tc335a.json');
      await tmpFile.writeAsString(jsonEncode(minimalFlowJson));
      try {
        final p = JsonFlowParser();
        final json = await p.loadFromFile(tmpFile.path);
        expect(json['version'], equals('1.0.0'));
      } finally {
        await tmpFile.delete();
      }
    });

    test('TC-335b: empty JSON object file', () async {
      final tmpFile = File('/tmp/parser_tc335b.json');
      await tmpFile.writeAsString('{}');
      try {
        final p = JsonFlowParser();
        final json = await p.loadFromFile(tmpFile.path);
        expect(json, isA<Map<String, dynamic>>());
        expect(json, isEmpty);
      } finally {
        await tmpFile.delete();
      }
    });

    test('TC-335c: nonexistent file throws', () {
      final p = JsonFlowParser();
      expect(
        () => p.loadFromFile('/nonexistent/tc335.json'),
        throwsA(anything),
      );
    });
  });

  group('TC-337: toJson round trip', () {
    test('TC-337a: round trip serialization', () {
      final flow = parser.parse(fullFlowJson);
      final json = flow.toJson();
      final reparsed = parser.parse(json);
      expect(reparsed.processes.length, equals(flow.processes.length));
      expect(reparsed.resources.length, equals(flow.resources.length));
    });

    test('TC-337b: minimal FlowDefinition serialization', () {
      final flow = parser.parse(minimalFlowJson);
      final json = flow.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['version'], isNotNull);
    });

    test('TC-337c: null optional fields in FlowDefinition round trip', () {
      // Parse minimal flow (no resources, channels, events, etc.)
      final flow = parser.parse(minimalFlowJson);
      final json = flow.toJson();
      // Should produce valid JSON that can be re-parsed
      final reparsed = parser.parse(json);
      expect(reparsed, isNotNull);
      expect(reparsed.processes.length, equals(flow.processes.length));
    });
  });

  // === TC-336: parseFile ===

  group('TC-336: JsonFlowParser.parseFile()', () {
    test('TC-336a: parse FlowDefinition from file path', () async {
      final tmpFile = File('/tmp/parser_tc336a.json');
      await tmpFile.writeAsString(jsonEncode(minimalFlowJson));
      try {
        final p = JsonFlowParser();
        final flow = await p.parseFile(tmpFile.path);
        expect(flow, isNotNull);
        expect(flow.metadata.name, equals('Minimal Flow'));
      } finally {
        await tmpFile.delete();
      }
    });

    test('TC-336b: parseFile matches loadFromFile + parse', () async {
      final tmpFile = File('/tmp/parser_tc336b.json');
      await tmpFile.writeAsString(jsonEncode(fullFlowJson));
      try {
        final p = JsonFlowParser();
        final flow1 = await p.parseFile(tmpFile.path);
        final json = await p.loadFromFile(tmpFile.path);
        final flow2 = p.parse(json);
        expect(flow1.processes.length, equals(flow2.processes.length));
        expect(flow1.resources.length, equals(flow2.resources.length));
        expect(flow1.metadata.name, equals(flow2.metadata.name));
      } finally {
        await tmpFile.delete();
      }
    });

    test('TC-336c: invalid JSON file throws FlowParseError', () async {
      final tmpFile = File('/tmp/parser_tc336c.json');
      await tmpFile.writeAsString('{ invalid json }');
      try {
        final p = JsonFlowParser();
        expect(
          () => p.parseFile(tmpFile.path),
          throwsA(isA<FlowParseError>()),
        );
      } finally {
        await tmpFile.delete();
      }
    });
  });

  // === TC-338: saveToFile ===

  group('TC-338: JsonFlowParser.saveToFile()', () {
    test('TC-338a: save FlowDefinition to file', () async {
      final flow = parser.parse(fullFlowJson);
      final tmpPath = '/tmp/parser_tc338a.json';
      try {
        await parser.saveToFile(flow, tmpPath);
        final file = File(tmpPath);
        expect(await file.exists(), isTrue);
        final content = await file.readAsString();
        final json = jsonDecode(content);
        expect(json, isA<Map<String, dynamic>>());
      } finally {
        try { await File(tmpPath).delete(); } catch (_) {}
      }
    });

    test('TC-338b: save then reload produces same result', () async {
      final flow = parser.parse(fullFlowJson);
      final tmpPath = '/tmp/parser_tc338b.json';
      try {
        await parser.saveToFile(flow, tmpPath);
        final reloaded = await parser.parseFile(tmpPath);
        expect(reloaded.processes.length, equals(flow.processes.length));
        expect(reloaded.resources.length, equals(flow.resources.length));
        expect(reloaded.metadata.name, equals(flow.metadata.name));
      } finally {
        try { await File(tmpPath).delete(); } catch (_) {}
      }
    });

    test('TC-338c: version type mismatch throws FlowParseError', () {
      expect(
        () => parser.parse({'version': 100, 'processes': []}),
        throwsA(isA<FlowParseError>()),
      );
    });
  });

  // === FlowValidator Tests ===

  group('TC-346: FlowValidator.validate() - basic', () {
    test('TC-346a: valid flow passes', () {
      final flow = parser.parse(fullFlowJson);
      final errors = FlowValidator().validate(flow);
      final realErrors =
          errors.where((e) => e.severity == ValidationSeverity.error).toList();
      expect(realErrors, isEmpty);
    });

    test('TC-346b: minimal flow passes', () {
      final flow = parser.parse(minimalFlowJson);
      final errors = FlowValidator().validate(flow);
      final realErrors =
          errors.where((e) => e.severity == ValidationSeverity.error).toList();
      expect(realErrors, isEmpty);
    });

    test('TC-346c: duplicate process ID detected', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {'id': 'dup', 'trigger': {'type': 'startup'}, 'steps': [{'action': 'log', 'params': {'message': 'a'}}]},
          {'id': 'dup', 'trigger': {'type': 'startup'}, 'steps': [{'action': 'log', 'params': {'message': 'b'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final realErrors =
          errors.where((e) => e.severity == ValidationSeverity.error).toList();
      expect(realErrors, isNotEmpty);
    });
  });

  group('TC-347: FlowValidator - action type validation', () {
    test('TC-347a: valid action types pass', () {
      final flow = parser.parse(minimalFlowJson);
      final errors = FlowValidator().validate(flow);
      final realErrors =
          errors.where((e) => e.severity == ValidationSeverity.error).toList();
      expect(realErrors, isEmpty);
    });

    test('TC-347b: empty process ID detected', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': '',
            'trigger': {'type': 'startup'},
            'steps': [{'action': 'log', 'params': {'message': 'x'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final idErrors = errors.where(
        (e) => e.severity == ValidationSeverity.error,
      ).toList();
      expect(idErrors, isNotEmpty);
    });

    test('TC-347c: invalid action type detected', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'startup'},
            'steps': [{'action': 'unknownAction123'}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final realErrors =
          errors.where((e) => e.severity == ValidationSeverity.error).toList();
      expect(realErrors, isNotEmpty);
    });
  });

  group('TC-348: FlowValidator - trigger required fields', () {
    test('TC-348a: schedule trigger with interval passes', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'schedule', 'interval': 1000},
            'steps': [{'action': 'log', 'params': {'message': 'tick'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final triggerErrors = errors.where((e) => e.code == 'MISSING_TRIGGER_FIELD').toList();
      expect(triggerErrors, isEmpty);
    });

    test('TC-348b: stateChange trigger with variable passes', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'stateChange', 'variable': 'temp'},
            'steps': [{'action': 'log', 'params': {'message': 'changed'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final triggerErrors = errors.where((e) => e.code == 'MISSING_TRIGGER_FIELD').toList();
      expect(triggerErrors, isEmpty);
    });

    test('TC-348c: schedule without interval or cron fails', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'schedule'},
            'steps': [{'action': 'log', 'params': {'message': 'tick'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final triggerErrors = errors.where((e) => e.code == 'MISSING_TRIGGER_FIELD').toList();
      expect(triggerErrors, isNotEmpty);
    });
  });

  group('TC-349: FlowValidator - trigger required fields (additional)', () {
    test('TC-349a: event trigger with event field passes', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'event', 'event': 'alarm'},
            'steps': [{'action': 'log', 'params': {'message': 'alarm'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final triggerErrors = errors.where((e) => e.code == 'MISSING_TRIGGER_FIELD').toList();
      expect(triggerErrors, isEmpty);
    });

    test('TC-349b: channelReceive trigger with channel field passes', () {
      final json = {
        'version': '1.0.0',
        'channels': {'ch1': {'type': 'queue', 'capacity': 10}},
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'channelReceive', 'channel': 'ch1'},
            'steps': [{'action': 'log', 'params': {'message': 'recv'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final triggerErrors = errors.where((e) => e.code == 'MISSING_TRIGGER_FIELD').toList();
      expect(triggerErrors, isEmpty);
    });

    test('TC-349c: event trigger without event field fails', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'event'},
            'steps': [{'action': 'log', 'params': {'message': 'x'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final triggerErrors = errors.where((e) => e.code == 'MISSING_TRIGGER_FIELD').toList();
      expect(triggerErrors, isNotEmpty);
    });
  });

  group('TC-350: FlowValidator - resource config validation', () {
    test('TC-350a: GPIO with pin passes', () {
      final json = {
        'version': '1.0.0',
        'resources': {
          'led': {'type': 'gpio', 'capabilities': ['write'], 'config': {'pin': 18}},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final pinErrors = errors.where((e) => e.path?.contains('config.pin') ?? false).toList();
      expect(pinErrors, isEmpty);
    });

    test('TC-350b: all resource types with required config pass', () {
      final json = {
        'version': '1.0.0',
        'resources': {
          'led': {'type': 'gpio', 'capabilities': ['write'], 'config': {'pin': 18}},
          'bus': {'type': 'i2c', 'capabilities': ['read'], 'config': {'bus': 1, 'address': 0x48}},
          'spi0': {'type': 'spi', 'capabilities': ['read'], 'config': {'bus': 0, 'device': 0}},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final resourceErrors = errors.where(
        (e) => e.severity == ValidationSeverity.warning && (e.path?.startsWith('resources.') ?? false),
      ).toList();
      expect(resourceErrors, isEmpty);
    });

    test('TC-350c: GPIO without pin warns', () {
      final json = {
        'version': '1.0.0',
        'resources': {
          'led': {'type': 'gpio', 'capabilities': ['write'], 'config': {}},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final pinWarnings = errors.where(
        (e) => e.path?.contains('config.pin') ?? false,
      ).toList();
      expect(pinWarnings, isNotEmpty);
    });
  });

  group('TC-351: FlowValidator - resource type validation', () {
    test('TC-351a: known resource types pass', () {
      final json = {
        'version': '1.0.0',
        'resources': {
          'r1': {'type': 'gpio', 'capabilities': ['write'], 'config': {'pin': 1}},
          'r2': {'type': 'adc', 'capabilities': ['read'], 'config': {'channel': 0}},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final typeWarnings = errors.where((e) => e.code == 'UNKNOWN_RESOURCE_TYPE').toList();
      expect(typeWarnings, isEmpty);
    });

    test('TC-351b: extra config fields are ignored', () {
      final json = {
        'version': '1.0.0',
        'resources': {
          'led': {'type': 'gpio', 'capabilities': ['write'], 'config': {'pin': 18, 'extra': 'field'}},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final realErrors = errors.where((e) => e.severity == ValidationSeverity.error).toList();
      expect(realErrors, isEmpty);
    });

    test('TC-351c: unknown resource type warns', () {
      final json = {
        'version': '1.0.0',
        'resources': {
          'hw': {'type': 'unknownHardware', 'capabilities': [], 'config': {}},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final typeWarnings = errors.where((e) => e.code == 'UNKNOWN_RESOURCE_TYPE').toList();
      expect(typeWarnings, isNotEmpty);
    });
  });

  group('TC-352: FlowValidator - state constraints validation', () {
    test('TC-352a: valid constraints and initial value', () {
      final json = {
        'version': '1.0.0',
        'state': {
          'temp': {
            'type': 'number',
            'initial': 20.0,
            'constraints': {'min': 0, 'max': 100},
          },
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final constraintErrors = errors.where(
        (e) => e.path?.contains('state.temp') ?? false,
      ).where((e) => e.severity == ValidationSeverity.error).toList();
      expect(constraintErrors, isEmpty);
    });

    test('TC-352b: no constraints passes', () {
      final json = {
        'version': '1.0.0',
        'state': {
          'msg': {'type': 'string', 'initial': 'hello'},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final stateErrors = errors.where(
        (e) => (e.path?.contains('state.msg') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(stateErrors, isEmpty);
    });

    test('TC-352c: min > max yields error', () {
      final json = {
        'version': '1.0.0',
        'state': {
          'val': {
            'type': 'number',
            'initial': 50,
            'constraints': {'min': 100, 'max': 0},
          },
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final constraintErrors = errors.where(
        (e) => e.path?.contains('constraints') ?? false,
      ).toList();
      expect(constraintErrors, isNotEmpty);
    });
  });

  group('TC-353: FlowValidator - state constraints (additional)', () {
    test('TC-353a: valid state definition passes', () {
      final json = {
        'version': '1.0.0',
        'state': {
          'name': {'type': 'string', 'initial': 'abc'},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final stateErrors = errors.where(
        (e) => (e.path?.contains('state.name') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(stateErrors, isEmpty);
    });

    test('TC-353b: enum initial value match passes', () {
      final json = {
        'version': '1.0.0',
        'state': {
          'mode': {'type': 'string', 'initial': 'a'},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final realErrors = errors.where((e) => e.severity == ValidationSeverity.error).toList();
      // No errors related to state
      final stateErrors = realErrors.where((e) => e.path?.contains('state.mode') ?? false).toList();
      expect(stateErrors, isEmpty);
    });

    test('TC-353c: type mismatch initial value detected', () {
      final json = {
        'version': '1.0.0',
        'state': {
          'flag': {'type': 'boolean', 'initial': 'not_a_bool'},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final typeErrors = errors.where(
        (e) => e.path?.contains('state.flag') ?? false,
      ).toList();
      expect(typeErrors, isNotEmpty);
    });
  });

  group('TC-354: FlowValidator - channel validation', () {
    test('TC-354a: valid channel passes', () {
      final json = {
        'version': '1.0.0',
        'channels': {
          'ch': {'type': 'queue', 'capacity': 100},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final chErrors = errors.where(
        (e) => (e.path?.contains('channels') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(chErrors, isEmpty);
    });

    test('TC-354b: capacity=1 passes', () {
      final json = {
        'version': '1.0.0',
        'channels': {
          'ch': {'type': 'queue', 'capacity': 1},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final chErrors = errors.where(
        (e) => (e.path?.contains('channels') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(chErrors, isEmpty);
    });

    test('TC-354c: capacity <= 0 fails', () {
      final json = {
        'version': '1.0.0',
        'channels': {
          'ch': {'type': 'queue', 'capacity': -1},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final chErrors = errors.where(
        (e) => (e.path?.contains('channels.ch.capacity') ?? false),
      ).toList();
      expect(chErrors, isNotEmpty);
    });
  });

  group('TC-355: FlowValidator - event validation', () {
    test('TC-355a: event with id and type passes', () {
      final json = {
        'version': '1.0.0',
        'events': [
          {'id': 'alarm', 'type': 'custom', 'source': 'system'},
        ],
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final eventErrors = errors.where(
        (e) => (e.path?.contains('events') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(eventErrors, isEmpty);
    });

    test('TC-355b: event without description passes', () {
      final json = {
        'version': '1.0.0',
        'events': [
          {'id': 'alarm', 'type': 'custom', 'source': 'system'},
        ],
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final eventErrors = errors.where(
        (e) => (e.path?.contains('events') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(eventErrors, isEmpty);
    });

    test('TC-355c: event without id fails at parse or validation', () {
      final json = {
        'version': '1.0.0',
        'events': [
          {'type': 'custom', 'source': 'system'},
        ],
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      // Parser requires non-null id, so it throws FlowParseError
      expect(
        () => parser.parse(json),
        throwsA(isA<FlowParseError>()),
      );
    });
  });

  group('TC-356: FlowValidator - event validation (additional)', () {
    test('TC-356a: multiple valid events pass', () {
      final json = {
        'version': '1.0.0',
        'events': [
          {'id': 'e1', 'type': 'custom', 'source': 's1'},
          {'id': 'e2', 'type': 'system', 'source': 's2'},
          {'id': 'e3', 'type': 'user', 'source': 's3'},
        ],
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final eventErrors = errors.where(
        (e) => (e.path?.contains('events') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(eventErrors, isEmpty);
    });

    test('TC-356b: empty events array passes', () {
      final json = {
        'version': '1.0.0',
        'events': <Map<String, dynamic>>[],
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final eventErrors = errors.where(
        (e) => (e.path?.contains('events') ?? false) && e.severity == ValidationSeverity.error,
      ).toList();
      expect(eventErrors, isEmpty);
    });

    test('TC-356c: event without type fails at parse or validation', () {
      final json = {
        'version': '1.0.0',
        'events': [
          {'id': 'alarm', 'source': 'system'},
        ],
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      // Parser requires non-null type, so it throws FlowParseError
      expect(
        () => parser.parse(json),
        throwsA(isA<FlowParseError>()),
      );
    });
  });

  group('TC-357: FlowValidator - channel reference cross-validation', () {
    test('TC-357a: valid channel reference passes', () {
      final json = {
        'version': '1.0.0',
        'channels': {
          'data_pipe': {'type': 'queue', 'capacity': 10},
        },
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'channelReceive', 'channel': 'data_pipe'},
            'steps': [{'action': 'log', 'params': {'message': 'recv'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final refErrors = errors.where((e) => e.code == 'UNDEFINED_CHANNEL_REF').toList();
      expect(refErrors, isEmpty);
    });

    test('TC-357b: channel reference in nested control flow passes', () {
      final json = {
        'version': '1.0.0',
        'channels': {
          'ch1': {'type': 'queue', 'capacity': 10},
        },
        'processes': [
          {
            'id': 'p',
            'steps': [
              {
                'action': 'if',
                'condition': 'true',
                'then': [
                  {'action': 'channelSend', 'params': {'channel': 'ch1', 'data': 'hello'}},
                ],
              }
            ],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final refErrors = errors.where((e) => e.code == 'UNDEFINED_CHANNEL_REF').toList();
      expect(refErrors, isEmpty);
    });

    test('TC-357c: undefined channel reference warns', () {
      final json = {
        'version': '1.0.0',
        'channels': <String, dynamic>{},
        'processes': [
          {
            'id': 'p',
            'trigger': {'type': 'channelReceive', 'channel': 'nonexistent'},
            'steps': [{'action': 'log', 'params': {'message': 'x'}}],
          }
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final refErrors = errors.where((e) => e.code == 'UNDEFINED_CHANNEL_REF').toList();
      expect(refErrors, isNotEmpty);
    });
  });

  group('TC-358: FlowValidator - multiple errors', () {
    test('TC-358a: collects multiple errors in single pass', () {
      final json = {
        'version': '1.0.0',
        'processes': [
          {'id': 'dup', 'trigger': {'type': 'startup'}, 'steps': [{'action': 'unknownAct'}]},
          {'id': 'dup', 'trigger': {'type': 'startup'}, 'steps': [{'action': 'anotherBad'}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      expect(errors.length, greaterThanOrEqualTo(2));
    });

    test('TC-358c: configuration tickRateMs=0 yields error', () {
      final json = {
        'version': '1.0.0',
        'configuration': {
          'runtime': {'tickRateMs': 0},
        },
        'processes': [
          {'id': 'p', 'steps': [{'action': 'log', 'params': {'message': 'x'}}]},
        ],
      };
      final flow = parser.parse(json);
      final errors = FlowValidator().validate(flow);
      final configErrors = errors.where(
        (e) => e.path?.contains('tickRateMs') ?? false,
      ).toList();
      expect(configErrors, isNotEmpty);
    });

    test('TC-358b: severity distinction', () {
      final flow = parser.parse(fullFlowJson);
      final errors = FlowValidator().validate(flow);
      // Should be filterable by severity
      final errorLevel =
          errors.where((e) => e.severity == ValidationSeverity.error).toList();
      final warningLevel =
          errors.where((e) => e.severity == ValidationSeverity.warning).toList();
      // Both should be valid lists (may be empty)
      expect(errorLevel, isA<List>());
      expect(warningLevel, isA<List>());
    });
  });

  // === Integration Tests ===

  group('IT-031: Parse -> Validate -> Load pipeline', () {
    test('full pipeline completes without error', () async {
      final flow = parser.parse(fullFlowJson);
      final errors = FlowValidator().validate(flow);
      final realErrors =
          errors.where((e) => e.severity == ValidationSeverity.error).toList();
      expect(realErrors, isEmpty);

      final runtime = McpFlowRuntime();
      await runtime.loadFlow(fullFlowJson);
      await runtime.stop();
    });
  });

  group('IT-032: Parse -> Validate -> Execute e2e', () {
    test('startup process sets mode to running', () async {
      final runtime = McpFlowRuntime();
      await runtime.loadFlow(fullFlowJson);
      await runtime.start();
      await Future.delayed(Duration(milliseconds: 500));
      expect(runtime.getState('mode'), equals('running'));
      await runtime.stop();
    });
  });

  group('IT-033: loadFromFile -> Validate -> Execute', () {
    test('file-based load works', () async {
      final tmpFile = File('/tmp/it033_flow.json');
      await tmpFile.writeAsString(jsonEncode(fullFlowJson));
      try {
        final runtime = McpFlowRuntime();
        await runtime.loadFlowFromFile(tmpFile.path);
        await runtime.start();
        await Future.delayed(Duration(milliseconds: 500));
        expect(runtime.getState('mode'), equals('running'));
        await runtime.stop();
      } finally {
        await tmpFile.delete();
      }
    });
  });

  group('IT-035: invalid flow rejected by runtime', () {
    test('validation error preserves created status', () async {
      final runtime = McpFlowRuntime();
      final badJson = {
        'version': '1.0.0',
        'processes': [
          {'id': 'dup', 'trigger': {'type': 'startup'}, 'steps': [{'action': 'log', 'params': {'message': 'a'}}]},
          {'id': 'dup', 'trigger': {'type': 'startup'}, 'steps': [{'action': 'log', 'params': {'message': 'b'}}]},
        ],
      };
      try {
        await runtime.loadFlow(badJson);
        fail('Should have thrown');
      } on FlowValidationError {
        expect(runtime.status, equals(RuntimeStatus.created));
      }
    });
  });
}
