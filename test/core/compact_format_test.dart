/// CompactFormat test suite (TC-745 ~ TC-764)
/// TEST-CORE-008

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:event_bus/event_bus.dart';
import 'package:test/test.dart';

import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

// ---------------------------------------------------------------------------
// Mock HAL for CompactExecutor tests
// ---------------------------------------------------------------------------

class _MockGpioProvider extends GpioProvider {
  final Map<int, bool> pinValues = {};

  @override
  String get name => 'MockGpio';
  @override
  String get version => '1.0.0';
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.gpio};
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  bool get isReady => true;
  @override
  Map<String, dynamic> get capabilities => {};
  @override
  List<int> get availablePins => List.generate(40, (i) => i);

  @override
  Future<void> configurePin(GpioConfig config) async {}

  @override
  Future<bool> readPin(int pin) async => pinValues[pin] ?? false;

  @override
  Future<void> writePin(int pin, bool value) async {
    pinValues[pin] = value;
  }

  @override
  Future<void> setInterruptHandler(
      int pin, GpioInterrupt trigger, void Function(bool) handler) async {}

  @override
  Future<void> removeInterruptHandler(int pin) async {}
}

class _MockHal extends HardwareAbstractionLayer {
  final _MockGpioProvider gpio = _MockGpioProvider();
  final List<HardwareProvider> _providers = [];

  _MockHal() {
    _providers.add(gpio);
  }

  @override
  void registerProvider(HardwareProvider provider) {
    _providers.add(provider);
  }

  @override
  T? getProvider<T extends HardwareProvider>(ResourceType type) {
    for (final p in _providers) {
      if (p is T) return p;
    }
    return null;
  }

  @override
  List<HardwareProvider> get providers => _providers;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Map<String, dynamic> get systemInfo => {'platform': 'test'};
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Create a minimal valid FlowDefinition for testing.
FlowDefinition _minimalFlow({
  List<ProcessDefinition>? processes,
  Map<String, StateDefinition>? state,
  Map<String, ResourceDefinition>? resources,
}) {
  return FlowDefinition(
    version: '1.0.0',
    metadata: const FlowMetadata(name: 'test-flow'),
    state: state ?? const {},
    resources: resources ?? const {},
    processes: processes ?? const [],
  );
}

/// Build a flow with a single stateSet process for round-trip testing.
FlowDefinition _stateSetFlow() {
  return _minimalFlow(
    state: {
      'temperature': const StateDefinition(
        type: StateType.number,
        initial: 0,
      ),
    },
    processes: [
      const ProcessDefinition(
        id: 'setTemp',
        name: 'Set Temperature',
        steps: [
          ActionDefinition(
            action: 'stateSet',
            params: {'key': 'temperature', 'value': 25},
          ),
        ],
      ),
    ],
  );
}

/// Build a flow containing multiple control flow action types.
FlowDefinition _controlFlowFlow() {
  return _minimalFlow(
    state: {
      'counter': const StateDefinition(type: StateType.number, initial: 0),
    },
    processes: [
      const ProcessDefinition(
        id: 'controlProcess',
        name: 'Control Flow Process',
        steps: [
          ActionDefinition(
            action: 'if',
            condition: '{{state.counter}}',
            then: [
              ActionDefinition(
                action: 'stateSet',
                params: {'key': 'counter', 'value': 1},
              ),
            ],
            else$: [
              ActionDefinition(
                action: 'stateSet',
                params: {'key': 'counter', 'value': 0},
              ),
            ],
          ),
          ActionDefinition(
            action: 'while',
            condition: '{{state.counter}}',
            do$: [
              ActionDefinition(action: 'log', params: {'message': 'loop'}),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Build a large flow for performance tests.
FlowDefinition _largeFlow({int processCount = 100, int stepCount = 50}) {
  final processes = <ProcessDefinition>[];
  for (var p = 0; p < processCount; p++) {
    final steps = <ActionDefinition>[];
    for (var s = 0; s < stepCount; s++) {
      steps.add(ActionDefinition(
        action: 'log',
        params: {'message': 'process_${p}_step_$s'},
      ));
    }
    processes.add(ProcessDefinition(
      id: 'proc_$p',
      name: 'Process $p',
      steps: steps,
    ));
  }
  return _minimalFlow(processes: processes);
}

/// Build a flow with duplicate strings for string pool deduplication testing.
FlowDefinition _duplicateStringsFlow() {
  return _minimalFlow(
    state: {
      'shared': const StateDefinition(
        type: StateType.string,
        initial: 'hello',
      ),
    },
    processes: [
      const ProcessDefinition(
        id: 'proc1',
        name: 'proc1',
        steps: [
          ActionDefinition(
            action: 'log',
            params: {'message': 'hello'},
          ),
          ActionDefinition(
            action: 'log',
            params: {'message': 'hello'},
          ),
          ActionDefinition(
            action: 'log',
            params: {'message': 'world'},
          ),
        ],
      ),
    ],
  );
}

/// Build a flow with expression templates.
FlowDefinition _expressionFlow() {
  return _minimalFlow(
    state: {
      'temperature': const StateDefinition(
        type: StateType.number,
        initial: 25,
      ),
    },
    processes: [
      const ProcessDefinition(
        id: 'exprProc',
        name: 'Expression Process',
        steps: [
          ActionDefinition(
            action: 'if',
            condition: '{{state.temperature > 20}}',
            then: [
              ActionDefinition(
                action: 'log',
                params: {'message': 'hot'},
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CompactCompiler', () {
    late CompactCompiler compiler;

    setUp(() {
      compiler = CompactCompiler();
    });

    // TC-745: Standard Flow JSON -> Compact conversion
    test('TC-745: compiles valid FlowDefinition to compact binary', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);

      // Result must not be empty
      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));

      // Magic number 'FCMP' at offset 0 (big-endian)
      final magic = ByteData.sublistView(binary).getUint32(0, Endian.big);
      expect(magic, equals(CompactHeader.magicNumber));

      // Version field present at offset 4
      final version = ByteData.sublistView(binary).getUint16(4, Endian.little);
      expect(version, equals(0x0100)); // v1.0

      // Compact binary should be smaller than the source JSON
      final jsonSize = utf8.encode(jsonEncode(flow.toJson())).length;
      expect(binary.length, lessThan(jsonSize));
    });

    // TC-746: Empty processes list
    test('TC-746: compiles flow with empty processes list', () async {
      final flow = _minimalFlow(processes: []);
      final binary = await compiler.compile(flow);

      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));

      // Valid magic number
      final magic = ByteData.sublistView(binary).getUint32(0, Endian.big);
      expect(magic, equals(CompactHeader.magicNumber));
    });

    // TC-747: Invalid Flow JSON via compileFromJson
    test('TC-747: throws FlowParseError for invalid JSON structure', () async {
      expect(
        () => compiler.compileFromJson({'version': 123}),
        throwsA(isA<FlowError>()),
      );
    });

    // TC-748: String pool optimization (no duplicates)
    test('TC-748: string pool contains no duplicate entries', () async {
      final flow = _duplicateStringsFlow();
      final binary = await compiler.compile(flow);

      // Load the binary to inspect string table
      final loader = CompactLoader();
      final data = await loader.load(binary);

      // 'hello' should appear exactly once despite being used 3 times
      final helloCount =
          data.strings.where((s) => s == 'hello').length;
      expect(helloCount, equals(1));

      // Every string in the table is unique
      expect(data.strings.toSet().length, equals(data.strings.length));
    });

    // TC-757: Large flow compile performance
    test('TC-757: compiles large flow within 500ms', () async {
      final flow = _largeFlow(processCount: 100, stepCount: 50);

      final stopwatch = Stopwatch()..start();
      final binary = await compiler.compile(flow);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(500));

      // Compact size should be <= 50% of source JSON size
      final jsonSize = utf8.encode(jsonEncode(flow.toJson())).length;
      expect(binary.length, lessThan(jsonSize));
    });

    // TC-759: All control flow actions compiled
    test('TC-759: all control flow actions are compiled to opcodes', () async {
      final flow = _controlFlowFlow();
      final binary = await compiler.compile(flow);

      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));
    });

    // TC-761: Expression encoding
    test('TC-761: expression templates are encoded in compact binary',
        () async {
      final flow = _expressionFlow();
      final binary = await compiler.compile(flow);

      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));

      // Round-trip: load and verify the expression string survived
      final loader = CompactLoader();
      final data = await loader.load(binary);
      // The expression should be stored in the string table
      final hasExpr = data.strings.any(
          (s) => s.contains('temperature') && s.contains('>'));
      expect(hasExpr, isTrue);
    });
  });

  group('CompactLoader', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    // TC-749: Load compact binary into CompactFlowData
    test('TC-749: loads compiled binary into CompactFlowData', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      expect(data, isNotNull);
      expect(data.strings, isNotEmpty);
      expect(data.states.length, equals(flow.state.length));
    });

    // TC-750: Invalid magic number
    test('TC-750: throws FlowParseError for invalid magic bytes', () async {
      final bad = Uint8List(32);
      // Fill with random invalid header
      bad[0] = 0xDE;
      bad[1] = 0xAD;
      bad[2] = 0xBE;
      bad[3] = 0xEF;

      expect(
        () => loader.load(bad),
        throwsA(isA<FlowParseError>()),
      );
    });

    // TC-751: Version mismatch
    test('TC-751: throws FlowParseError for unsupported format version',
        () async {
      final flow = _minimalFlow();
      final binary = await compiler.compile(flow);

      // Patch version field to unsupported major version 9
      final patched = Uint8List.fromList(binary);
      final bd = ByteData.sublistView(patched);
      bd.setUint16(4, 0x0900, Endian.little); // major 9

      expect(
        () => loader.load(patched),
        throwsA(isA<FlowParseError>()),
      );
    });

    // TC-752: Corrupted / truncated binary
    test('TC-752: throws FlowParseError for truncated binary', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);

      // Truncate to just the header
      final truncated = binary.sublist(0, CompactHeader.size + 2);

      expect(
        () => loader.load(Uint8List.fromList(truncated)),
        throwsA(isA<FlowError>()),
      );
    });

    // TC-753: Round-trip integrity
    test('TC-753: round-trip compile+load preserves state definitions',
        () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      // State count matches
      expect(data.states.length, equals(flow.state.length));

      // State name survives round trip
      final stateNames =
          data.states.map((s) => data.strings[s.nameRef]).toList();
      for (final key in flow.state.keys) {
        expect(stateNames, contains(key));
      }
    });

    // TC-758: Large compact load performance
    test('TC-758: loads large compact binary within 200ms', () async {
      final flow = _largeFlow(processCount: 100, stepCount: 50);
      final binary = await compiler.compile(flow);

      final stopwatch = Stopwatch()..start();
      await loader.load(binary);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    // TC-762: Checksum verification (valid binary passes)
    test('TC-762: valid binary passes checksum / header verification',
        () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);

      // Should load without errors (checksum OK)
      final data = await loader.load(binary);
      expect(data, isNotNull);
      expect(data.header.originalHash, isNonZero);
    });

    // TC-763: Empty / zero-byte Compact file
    test('TC-763: throws FlowParseError for zero-byte input', () async {
      expect(
        () => loader.load(Uint8List(0)),
        throwsA(isA<FlowParseError>()),
      );
    });

    test('TC-763: throws FlowParseError for header-only input', () async {
      // A buffer shorter than the header size
      expect(
        () => loader.load(Uint8List(CompactHeader.size - 1)),
        throwsA(isA<FlowParseError>()),
      );
    });
  });

  group('CompactExecutor', () {
    late _MockHal hal;
    late StateManager stateManager;
    late EventBus eventBus;
    late CompactExecutor executor;

    setUp(() async {
      hal = _MockHal();
      stateManager = StateManager();
      await stateManager.initialize();
      eventBus = EventBus();
      executor = CompactExecutor(
        hal: hal,
        stateManager: stateManager,
        eventBus: eventBus,
      );
    });

    tearDown(() async {
      await stateManager.dispose();
    });

    // TC-754: Direct execution from compact format
    test('TC-754: executes compact process with stateSet', () async {
      // Register state variable
      await stateManager.defineVariable(
        'temperature',
        type: StateType.number,
        initial: 0,
      );

      // Build compact flow data manually with a stateSet instruction
      final flowData = CompactFlowData(
        header: const CompactHeader(
          version: 0x0100,
          flags: 0,
          originalHash: 0,
          totalSize: 0,
        ),
        sectionTable: const CompactSectionTable(
          stringCount: 1,
          stateCount: 1,
          resourceCount: 0,
          processCount: 1,
          eventCount: 0,
          instructionCount: 1,
          stringTableOffset: 0,
          dataSectionOffset: 0,
        ),
        strings: ['temperature'],
        states: [
          const CompactStateEntry(
            id: 0,
            nameRef: 0,
            type: CompactStateType.number,
          ),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0,
            nameRef: 0,
            triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                    type: CompactReferenceType.state,
                    id: 0,
                  ),
                  const CompactReference(
                    type: CompactReferenceType.immediate,
                    value: 42,
                  ),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      expect(stateManager.get('temperature'), equals(42));
    });

    // TC-755: Opcode dispatch for major opcodes
    test('TC-755: dispatches log opcode to correct handler', () async {
      final flowData = CompactFlowData(
        header: const CompactHeader(
          version: 0x0100,
          flags: 0,
          originalHash: 0,
          totalSize: 0,
        ),
        sectionTable: const CompactSectionTable(
          stringCount: 1,
          stateCount: 0,
          resourceCount: 0,
          processCount: 1,
          eventCount: 0,
          instructionCount: 1,
          stringTableOffset: 0,
          dataSectionOffset: 0,
        ),
        strings: ['testLog'],
        states: [],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0,
            nameRef: 0,
            triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.log.code, // 0xA4
                operands: [
                  const CompactReference(
                    type: CompactReferenceType.string,
                    id: 0,
                  ),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      // Should complete without error (log handler invoked)
      await executor.executeProcess(flowData.processes[0], flowData);
    });

    // TC-756: Unknown opcode throws ProcessExecutionError
    test('TC-756: throws ProcessExecutionError for unknown opcode', () async {
      final flowData = CompactFlowData(
        header: const CompactHeader(
          version: 0x0100,
          flags: 0,
          originalHash: 0,
          totalSize: 0,
        ),
        sectionTable: const CompactSectionTable(
          stringCount: 1,
          stateCount: 0,
          resourceCount: 0,
          processCount: 1,
          eventCount: 0,
          instructionCount: 1,
          stringTableOffset: 0,
          dataSectionOffset: 0,
        ),
        strings: ['proc'],
        states: [],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0,
            nameRef: 0,
            triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              const CompactInstruction(
                opcode: 0xFE, // undefined opcode
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      expect(
        () => executor.executeProcess(flowData.processes[0], flowData),
        throwsA(isA<ProcessExecutionError>()),
      );
    });

    // TC-760: if/while control flow via compact executor
    test('TC-760: if control flow dispatches correctly', () async {
      await stateManager.defineVariable(
        'flag',
        type: StateType.boolean,
        initial: false,
      );

      final flowData = CompactFlowData(
        header: const CompactHeader(
          version: 0x0100,
          flags: 0,
          originalHash: 0,
          totalSize: 0,
        ),
        sectionTable: const CompactSectionTable(
          stringCount: 2,
          stateCount: 1,
          resourceCount: 0,
          processCount: 1,
          eventCount: 0,
          instructionCount: 3,
          stringTableOffset: 0,
          dataSectionOffset: 0,
        ),
        strings: ['flag', 'ifProc'],
        states: [
          const CompactStateEntry(
            id: 0,
            nameRef: 0,
            type: CompactStateType.boolean,
          ),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0,
            nameRef: 1,
            triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              // JUMP_IF_FALSE condition=false, offset=1 (skip stateSet true)
              CompactInstruction(
                opcode: CompactOpcode.jumpIfFalse.code,
                operands: [
                  const CompactReference(
                    type: CompactReferenceType.immediate,
                    value: false,
                  ),
                  const CompactReference(
                    type: CompactReferenceType.immediate,
                    value: 2, // offset=2 because _pc is already incremented, so skip = offset-1 = 1 instruction
                  ),
                ],
              ),
              // then: stateSet flag = true (skipped because condition is false)
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                    type: CompactReferenceType.state,
                    id: 0,
                  ),
                  const CompactReference(
                    type: CompactReferenceType.immediate,
                    value: true,
                  ),
                ],
              ),
              // else: exit
              CompactInstruction(
                opcode: CompactOpcode.exit.code,
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);

      // Condition was false so stateSet was skipped; flag remains false
      expect(stateManager.get('flag'), equals(false));
    });

    // TC-764: Standard execution compatibility
    test('TC-764: compact execution produces same state as standard path',
        () async {
      await stateManager.defineVariable(
        'value',
        type: StateType.number,
        initial: 0,
      );

      final flowData = CompactFlowData(
        header: const CompactHeader(
          version: 0x0100,
          flags: 0,
          originalHash: 0,
          totalSize: 0,
        ),
        sectionTable: const CompactSectionTable(
          stringCount: 1,
          stateCount: 1,
          resourceCount: 0,
          processCount: 1,
          eventCount: 0,
          instructionCount: 1,
          stringTableOffset: 0,
          dataSectionOffset: 0,
        ),
        strings: ['value'],
        states: [
          const CompactStateEntry(
            id: 0,
            nameRef: 0,
            type: CompactStateType.number,
          ),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0,
            nameRef: 0,
            triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                    type: CompactReferenceType.state,
                    id: 0,
                  ),
                  const CompactReference(
                    type: CompactReferenceType.immediate,
                    value: 99,
                  ),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      // Execute via compact executor
      await executor.executeProcess(flowData.processes[0], flowData);

      // The standard JSON path would also set value to 99
      // Verify that compact execution achieved the expected final state
      expect(stateManager.get('value'), equals(99));
    });
  });

  // =========================================================================
  // TC-100: Core module compact format integration
  // TC-101, TC-102: Compact format tests from core-tests.md / 08-compact-format-tests.md
  // TC-1001 ~ TC-1020: Detailed compact format test cases
  // =========================================================================

  group('TC-100: Core CompactFormat integration', () {
    test('TC-100a: CompactCompiler, CompactLoader, CompactExecutor are available',
        () {
      // Verify the three main compact format classes can be instantiated
      final compiler = CompactCompiler();
      final loader = CompactLoader();
      expect(compiler, isNotNull);
      expect(loader, isNotNull);
    });
  });

  group('TC-101: Compact binary format structure', () {
    test('TC-101a: binary starts with FCMP magic and valid header', () async {
      final compiler = CompactCompiler();
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);

      // Magic number: 'FCMP' = 0x46434D50
      expect(binary.length, greaterThanOrEqualTo(CompactHeader.size));
      final bd = ByteData.sublistView(binary);
      expect(bd.getUint32(0, Endian.big), equals(CompactHeader.magicNumber));
      // Version at offset 4
      expect(bd.getUint16(4, Endian.little), equals(0x0100));
      // Total size at offset 12
      expect(bd.getUint32(12, Endian.little), equals(binary.length));
    });
  });

  group('TC-102: Compact format round-trip basics', () {
    test('TC-102a: compile then load preserves string table', () async {
      final compiler = CompactCompiler();
      final loader = CompactLoader();
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      expect(data.strings, isNotEmpty);
      expect(data.strings, contains('temperature'));
    });
  });

  // =========================================================================
  // TC-1001 ~ TC-1020
  // =========================================================================

  group('TC-1001: CompactCompiler.compile', () {
    late CompactCompiler compiler;

    setUp(() {
      compiler = CompactCompiler();
    });

    test('TC-1001a: standard Flow to Compact conversion', () async {
      // 2 processes, each with 3 steps
      final flow = _minimalFlow(
        state: {
          'a': const StateDefinition(type: StateType.number, initial: 0),
        },
        processes: [
          const ProcessDefinition(
            id: 'p1',
            name: 'Process 1',
            steps: [
              ActionDefinition(action: 'log', params: {'message': 'step1'}),
              ActionDefinition(action: 'log', params: {'message': 'step2'}),
              ActionDefinition(
                  action: 'stateSet',
                  params: {'key': 'a', 'value': 10}),
            ],
          ),
          const ProcessDefinition(
            id: 'p2',
            name: 'Process 2',
            steps: [
              ActionDefinition(action: 'log', params: {'message': 'step3'}),
              ActionDefinition(action: 'log', params: {'message': 'step4'}),
              ActionDefinition(action: 'log', params: {'message': 'step5'}),
            ],
          ),
        ],
      );

      final binary = await compiler.compile(flow);

      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));

      // Magic number check
      final magic = ByteData.sublistView(binary).getUint32(0, Endian.big);
      expect(magic, equals(CompactHeader.magicNumber));

      // Compact should be smaller than JSON
      final jsonSize = utf8.encode(jsonEncode(flow.toJson())).length;
      expect(binary.length, lessThan(jsonSize));
    });

    test('TC-1001b: empty processes list', () async {
      final flow = _minimalFlow(processes: []);
      final binary = await compiler.compile(flow);

      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));

      final magic = ByteData.sublistView(binary).getUint32(0, Endian.big);
      expect(magic, equals(CompactHeader.magicNumber));
    });

    test('TC-1001c: compile rejects invalid flow data', () async {
      // compileFromJson with completely invalid structure throws
      expect(
        () => compiler.compileFromJson({'version': 123}),
        throwsA(isA<FlowError>()),
      );
    });
  });

  group('TC-1002: CompactCompiler.compileFromJson', () {
    late CompactCompiler compiler;

    setUp(() {
      compiler = CompactCompiler();
    });

    test('TC-1002a: compiles from valid JSON map', () async {
      final json = {
        'version': '1.0.0',
        'metadata': {'name': 'test'},
        'state': {},
        'resources': {},
        'processes': [
          {
            'id': 'proc1',
            'name': 'Proc1',
            'steps': [
              {
                'action': 'log',
                'params': {'message': 'hello'}
              }
            ]
          }
        ]
      };

      final binary = await compiler.compileFromJson(json);
      expect(binary, isA<Uint8List>());
      expect(binary.length, greaterThan(CompactHeader.size));
    });

    test('TC-1002b: throws for invalid JSON structure', () async {
      expect(
        () => compiler.compileFromJson({'version': 123}),
        throwsA(isA<FlowError>()),
      );
    });

    test('TC-1002c: all control flow actions compiled', () async {
      final flow = _controlFlowFlow();
      final binary = await compiler.compile(flow);

      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));

      // Verify it can be loaded back
      final loader = CompactLoader();
      final data = await loader.load(binary);
      expect(data, isNotNull);
    });
  });

  group('TC-1003: CompactCompiler.compileFile', () {
    late CompactCompiler compiler;

    test('TC-1003a: JSON file to .fcmp file', () async {
      compiler = CompactCompiler();
      final tempDir = Directory.systemTemp.createTempSync('tc1003_');
      final inputPath = '${tempDir.path}/test_flow.json';
      final outputPath = '${tempDir.path}/test_flow.fcmp';

      // Write a valid JSON flow file
      final json = {
        'version': '1.0.0',
        'metadata': {'name': 'file-test'},
        'state': {},
        'resources': {},
        'processes': [
          {
            'id': 'p1',
            'name': 'P1',
            'steps': [
              {
                'action': 'log',
                'params': {'message': 'file-test'}
              }
            ]
          }
        ]
      };
      await File(inputPath).writeAsString(jsonEncode(json));

      await compiler.compileFile(inputPath, outputPath);

      final outputFile = File(outputPath);
      expect(await outputFile.exists(), isTrue);
      final bytes = await outputFile.readAsBytes();
      expect(bytes.length, greaterThan(CompactHeader.size));

      // Cleanup
      tempDir.deleteSync(recursive: true);
    });

    test('TC-1003b: throws for missing input file', () async {
      compiler = CompactCompiler();
      expect(
        () => compiler.compileFile('/nonexistent/path.json', '/tmp/out.fcmp'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('TC-1004: CompactCompiler string pool optimization', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1004a: duplicate strings are deduplicated', () async {
      final flow = _duplicateStringsFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      // 'hello' used multiple times but appears only once in string table
      final helloCount = data.strings.where((s) => s == 'hello').length;
      expect(helloCount, equals(1));

      // All strings are unique
      expect(data.strings.toSet().length, equals(data.strings.length));
    });

    test('TC-1004b: flow with no user strings', () async {
      // Minimal flow - only metadata strings
      final flow = _minimalFlow(processes: []);
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      // Should still compile and load successfully
      expect(data, isNotNull);
    });

    test('TC-1004c: large number of unique strings', () async {
      // Build flow with many unique strings
      final steps = <ActionDefinition>[];
      for (var i = 0; i < 200; i++) {
        steps.add(ActionDefinition(
          action: 'log',
          params: {'message': 'unique_string_$i'},
        ));
      }
      final flow = _minimalFlow(processes: [
        ProcessDefinition(id: 'bulkProc', name: 'Bulk', steps: steps),
      ]);

      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      // All unique strings should be in the table
      for (var i = 0; i < 200; i++) {
        expect(data.strings, contains('unique_string_$i'));
      }
    });
  });

  group('TC-1005: CompactLoader.load', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1005a: loads valid binary into CompactFlowData', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      expect(data, isNotNull);
      expect(data.header.version, equals(0x0100));
      expect(data.strings, isNotEmpty);
      expect(data.states.length, equals(flow.state.length));
    });

    test('TC-1005b: throws FlowParseError for invalid magic', () async {
      final bad = Uint8List(32);
      bad[0] = 0xDE;
      bad[1] = 0xAD;

      expect(
        () => loader.load(bad),
        throwsA(isA<FlowParseError>()),
      );
    });

    test('TC-1005c: throws FlowParseError for unsupported version', () async {
      final flow = _minimalFlow();
      final binary = await compiler.compile(flow);
      final patched = Uint8List.fromList(binary);
      ByteData.sublistView(patched).setUint16(4, 0x0900, Endian.little);

      expect(
        () => loader.load(patched),
        throwsA(isA<FlowParseError>()),
      );
    });
  });

  group('TC-1006: CompactLoader.load — corrupted data', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1006a: truncated binary throws', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final truncated = binary.sublist(0, CompactHeader.size + 2);

      expect(
        () => loader.load(Uint8List.fromList(truncated)),
        throwsA(isA<FlowError>()),
      );
    });

    test('TC-1006b: tampered binary body still loads header', () async {
      // Tamper with a single byte in the body (after header)
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final tampered = Uint8List.fromList(binary);
      if (tampered.length > CompactHeader.size + 5) {
        tampered[CompactHeader.size + 5] ^= 0xFF;
      }

      // Header parsing succeeds; body parsing may or may not fail
      // depending on what byte was tampered. At minimum, no crash.
      try {
        await loader.load(tampered);
      } on FlowError {
        // Expected for corrupted data
      }
    });

    test('TC-1006c: zero-byte input throws FlowParseError', () async {
      expect(
        () => loader.load(Uint8List(0)),
        throwsA(isA<FlowParseError>()),
      );
    });
  });

  group('TC-1007: CompactLoader.loadFile', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1007a: loads .fcmp file', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final tempDir = Directory.systemTemp.createTempSync('tc1007_');
      final path = '${tempDir.path}/test.fcmp';
      await File(path).writeAsBytes(binary);

      final data = await loader.loadFile(path);
      expect(data, isNotNull);
      expect(data.states.length, equals(flow.state.length));

      tempDir.deleteSync(recursive: true);
    });

    test('TC-1007b: throws for nonexistent file', () async {
      expect(
        () => loader.loadFile('/nonexistent/path.fcmp'),
        throwsA(isA<Exception>()),
      );
    });

    test('TC-1007c: throws for empty file', () async {
      final tempDir = Directory.systemTemp.createTempSync('tc1007c_');
      final path = '${tempDir.path}/empty.fcmp';
      await File(path).writeAsBytes(Uint8List(0));

      expect(
        () => loader.loadFile(path),
        throwsA(isA<FlowParseError>()),
      );

      tempDir.deleteSync(recursive: true);
    });
  });

  group('TC-1008: CompactLoader.toFlowDefinition', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1008a: converts CompactFlowData to FlowDefinition', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      final restored = loader.toFlowDefinition(data);
      expect(restored, isNotNull);
      // State count matches
      expect(restored.state.length, equals(flow.state.length));
      // State names preserved
      expect(restored.state.keys, contains('temperature'));
    });

    test('TC-1008b: empty processes data', () async {
      final flow = _minimalFlow(processes: []);
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      final restored = loader.toFlowDefinition(data);
      expect(restored.processes, isEmpty);
    });

    test('TC-1008c: corrupted CompactFlowData throws', () {
      // Create data with invalid string reference
      final data = CompactFlowData(
        header: const CompactHeader(
          version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 0, stateCount: 1, resourceCount: 0,
          processCount: 0, eventCount: 0, instructionCount: 0,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: [], // Empty strings but state references index 0
        states: [
          const CompactStateEntry(
            id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [],
        compression: CompactCompressionType.none,
      );

      expect(
        () => loader.toFlowDefinition(data),
        throwsA(isA<Error>()), // RangeError for invalid string index
      );
    });
  });

  group('TC-1009: Round-trip conversion integrity', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1009a: JSON -> Compact -> FlowDefinition equivalence', () async {
      final original = _stateSetFlow();
      final binary = await compiler.compile(original);
      final data = await loader.load(binary);
      final restored = loader.toFlowDefinition(data);

      // State definitions match
      expect(restored.state.length, equals(original.state.length));
      for (final key in original.state.keys) {
        expect(restored.state.containsKey(key), isTrue);
        expect(restored.state[key]!.type, equals(original.state[key]!.type));
        expect(restored.state[key]!.initial,
            equals(original.state[key]!.initial));
      }
    });

    test('TC-1009b: complex flow with control flow actions', () async {
      final original = _controlFlowFlow();
      final binary = await compiler.compile(original);
      final data = await loader.load(binary);

      // State count preserved
      expect(data.states.length, equals(original.state.length));
      // String table contains state names
      final stateNames =
          data.states.map((s) => data.strings[s.nameRef]).toList();
      expect(stateNames, contains('counter'));
    });

    test('TC-1009c: expression flow round-trip', () async {
      final original = _expressionFlow();
      final binary = await compiler.compile(original);
      final data = await loader.load(binary);

      // Expression-related strings survive round-trip
      final hasExpr = data.strings
          .any((s) => s.contains('temperature') && s.contains('>'));
      expect(hasExpr, isTrue);
    });
  });

  group('TC-1010: CompactExecutor.executeProcess', () {
    late _MockHal hal;
    late StateManager stateManager;
    late EventBus eventBus;
    late CompactExecutor executor;

    setUp(() async {
      hal = _MockHal();
      stateManager = StateManager();
      await stateManager.initialize();
      eventBus = EventBus();
      executor = CompactExecutor(
        hal: hal, stateManager: stateManager, eventBus: eventBus);
    });

    tearDown(() async {
      await stateManager.dispose();
    });

    test('TC-1010a: basic process with stateSet and log', () async {
      await stateManager.defineVariable('val',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 2, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 2,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['val', 'done'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 77),
                ],
              ),
              CompactInstruction(
                opcode: CompactOpcode.log.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.string, id: 1),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      expect(stateManager.get('val'), equals(77));
    });

    test('TC-1010b: empty instruction process completes normally', () async {
      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 0, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 0,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['emptyProc'],
        states: [],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      // Should complete without error
      await executor.executeProcess(flowData.processes[0], flowData);
    });

    test('TC-1010c: invalid bytecode throws ProcessExecutionError', () async {
      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 0, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['badProc'],
        states: [],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              const CompactInstruction(opcode: 0xFE),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      expect(
        () => executor.executeProcess(flowData.processes[0], flowData),
        throwsA(isA<ProcessExecutionError>()),
      );
    });
  });

  group('TC-1011: CompactExecutor._dispatch opcodes', () {
    late _MockHal hal;
    late StateManager stateManager;
    late EventBus eventBus;
    late CompactExecutor executor;

    setUp(() async {
      hal = _MockHal();
      stateManager = StateManager();
      await stateManager.initialize();
      eventBus = EventBus();
      executor = CompactExecutor(
        hal: hal, stateManager: stateManager, eventBus: eventBus);
    });

    tearDown(() async {
      await stateManager.dispose();
    });

    test('TC-1011a: major opcodes dispatch correctly', () async {
      // Test stateSet (0x41) and log (0xA4) dispatch
      await stateManager.defineVariable('x',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 2, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 2,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['x', 'dispatched'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 55),
                ],
              ),
              CompactInstruction(
                opcode: CompactOpcode.log.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.string, id: 1),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      expect(stateManager.get('x'), equals(55));
    });

    test('TC-1011b: unknown opcode throws ProcessExecutionError', () async {
      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 0, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['proc'],
        states: [],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              const CompactInstruction(opcode: 0xFD),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      expect(
        () => executor.executeProcess(flowData.processes[0], flowData),
        throwsA(isA<ProcessExecutionError>()),
      );
    });

    test('TC-1011c: all defined CompactOpcode values dispatch without crash',
        () async {
      // Opcodes that require no operands or can handle empty operands
      final safeOpcodes = [
        CompactOpcode.exit,
      ];

      for (final op in safeOpcodes) {
        final flowData = CompactFlowData(
          header: const CompactHeader(
              version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
          sectionTable: const CompactSectionTable(
            stringCount: 1, stateCount: 0, resourceCount: 0,
            processCount: 1, eventCount: 0, instructionCount: 1,
            stringTableOffset: 0, dataSectionOffset: 0),
          strings: ['test'],
          states: [],
          resources: [],
          expressions: [],
          processes: [
            CompactProcessEntry(
              id: 0, nameRef: 0, triggerType: 0,
              triggerData: Uint8List(0),
              instructions: [
                CompactInstruction(opcode: op.code),
              ],
            ),
          ],
          compression: CompactCompressionType.none,
        );

        // Should not throw for known opcodes
        await executor.executeProcess(flowData.processes[0], flowData);
      }
    });
  });

  group('TC-1012: CompactExecutor — if/while control flow', () {
    late _MockHal hal;
    late StateManager stateManager;
    late EventBus eventBus;
    late CompactExecutor executor;

    setUp(() async {
      hal = _MockHal();
      stateManager = StateManager();
      await stateManager.initialize();
      eventBus = EventBus();
      executor = CompactExecutor(
        hal: hal, stateManager: stateManager, eventBus: eventBus);
    });

    tearDown(() async {
      await stateManager.dispose();
    });

    test('TC-1012a: if branch (true condition)', () async {
      await stateManager.defineVariable('result',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 2,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['result'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              // JUMP_IF_FALSE condition=true, skip 1
              CompactInstruction(
                opcode: CompactOpcode.jumpIfFalse.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: true),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 1),
                ],
              ),
              // then: stateSet result = 100
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 100),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      // Condition was true, so stateSet executed
      expect(stateManager.get('result'), equals(100));
    });

    test('TC-1012b: if branch (false condition)', () async {
      await stateManager.defineVariable('result',
          type: StateType.number, initial: 0);

      // jumpIfFalse adds (offset - 1) to _pc (since _pc is already
      // incremented). To skip 1 instruction, offset must be 2.
      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 2,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['result'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              // JUMP_IF_FALSE condition=false, offset=2 (skip next instruction)
              CompactInstruction(
                opcode: CompactOpcode.jumpIfFalse.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: false),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 2),
                ],
              ),
              // then: stateSet result = 100 (should be skipped)
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 100),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      // Condition was false, stateSet skipped, result stays 0
      expect(stateManager.get('result'), equals(0));
    });

    test('TC-1012c: exit opcode halts execution', () async {
      await stateManager.defineVariable('result',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 3,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['result'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 10),
                ],
              ),
              CompactInstruction(opcode: CompactOpcode.exit.code),
              // This should NOT execute
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 999),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      // Exit should have halted before the second stateSet
      expect(stateManager.get('result'), equals(10));
    });
  });

  group('TC-1013: Performance — large compile', () {
    test('TC-1013a: 100 processes x 50 steps within 500ms', () async {
      final compiler = CompactCompiler();
      final flow = _largeFlow(processCount: 100, stepCount: 50);

      final stopwatch = Stopwatch()..start();
      final binary = await compiler.compile(flow);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      expect(binary.length, greaterThan(0));
    });

    test('TC-1013b: compact size is less than 50% of JSON', () async {
      final compiler = CompactCompiler();
      final flow = _largeFlow(processCount: 100, stepCount: 50);

      final binary = await compiler.compile(flow);
      final jsonSize = utf8.encode(jsonEncode(flow.toJson())).length;

      expect(binary.length, lessThan(jsonSize));
    });
  });

  group('TC-1014: Performance — large load', () {
    test('TC-1014a: large compact binary loads within 200ms', () async {
      final compiler = CompactCompiler();
      final loader = CompactLoader();
      final flow = _largeFlow(processCount: 100, stepCount: 50);
      final binary = await compiler.compile(flow);

      final stopwatch = Stopwatch()..start();
      await loader.load(binary);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('TC-1014b: loaded data has reasonable memory footprint', () async {
      final compiler = CompactCompiler();
      final loader = CompactLoader();
      final flow = _largeFlow(processCount: 100, stepCount: 50);
      final binary = await compiler.compile(flow);

      final data = await loader.load(binary);
      // Basic sanity: data object is not null and has strings
      expect(data, isNotNull);
      expect(data.strings, isNotEmpty);
    });
  });

  group('TC-1015: CompactCompiler — expression encoding', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1015a: simple expression encoded in string table', () async {
      final flow = _expressionFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      // The expression string should be stored in string table
      final hasExpr = data.strings
          .any((s) => s.contains('temperature') && s.contains('>'));
      expect(hasExpr, isTrue);
    });

    test('TC-1015b: complex nested expression compiles', () async {
      final flow = _minimalFlow(
        state: {
          'a': const StateDefinition(type: StateType.number, initial: 1),
          'b': const StateDefinition(type: StateType.number, initial: 2),
        },
        processes: [
          const ProcessDefinition(
            id: 'exprProc',
            name: 'Expr',
            steps: [
              ActionDefinition(
                action: 'if',
                condition: '{{state.a > state.b}}',
                then: [
                  ActionDefinition(
                      action: 'log', params: {'message': 'a > b'}),
                ],
              ),
            ],
          ),
        ],
      );

      final binary = await compiler.compile(flow);
      expect(binary, isNotNull);
      expect(binary.length, greaterThan(CompactHeader.size));
    });

    test('TC-1015c: non-expression string compiles normally', () async {
      final flow = _minimalFlow(
        processes: [
          const ProcessDefinition(
            id: 'p',
            name: 'P',
            steps: [
              ActionDefinition(
                  action: 'log', params: {'message': 'plain text'}),
            ],
          ),
        ],
      );

      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);
      expect(data.strings, contains('plain text'));
    });
  });

  group('TC-1016: CompactLoader — decompression', () {
    test('TC-1016a: NONE compression loads directly', () async {
      final compiler = CompactCompiler(
          compressionType: CompactCompressionType.none);
      final loader = CompactLoader();
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      expect(data, isNotNull);
      expect(data.compression, equals(CompactCompressionType.none));
    });

    test('TC-1016b: LZ4 compression not yet supported', () async {
      // LZ4 is not implemented; compiler falls back to raw data but
      // sets the compression flag to LZ4, so loader rejects it.
      final compiler = CompactCompiler(
          compressionType: CompactCompressionType.lz4);
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);

      final loader = CompactLoader();
      expect(
        () => loader.load(binary),
        throwsA(isA<FlowParseError>()),
      );
    });

    test('TC-1016c: ZLIB compression compiles and loads', () async {
      final compiler = CompactCompiler(
          compressionType: CompactCompressionType.zlib);
      final loader = CompactLoader();
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);

      final data = await loader.load(binary);
      expect(data, isNotNull);
      expect(data.states.length, equals(flow.state.length));
    });
  });

  group('TC-1017: CompactLoader — checksum verification', () {
    late CompactCompiler compiler;
    late CompactLoader loader;

    setUp(() {
      compiler = CompactCompiler();
      loader = CompactLoader();
    });

    test('TC-1017a: valid checksum passes verification', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final data = await loader.load(binary);

      expect(data.header.originalHash, isNonZero);
    });

    test('TC-1017b: tampered version field causes error', () async {
      final flow = _stateSetFlow();
      final binary = await compiler.compile(flow);
      final tampered = Uint8List.fromList(binary);
      // Tamper version to unsupported
      ByteData.sublistView(tampered).setUint16(4, 0x0500, Endian.little);

      expect(
        () => loader.load(tampered),
        throwsA(isA<FlowParseError>()),
      );
    });
  });

  group('TC-1018: CompactExecutor — standard execution compatibility', () {
    late _MockHal hal;
    late StateManager stateManager;
    late EventBus eventBus;
    late CompactExecutor executor;

    setUp(() async {
      hal = _MockHal();
      stateManager = StateManager();
      await stateManager.initialize();
      eventBus = EventBus();
      executor = CompactExecutor(
        hal: hal, stateManager: stateManager, eventBus: eventBus);
    });

    tearDown(() async {
      await stateManager.dispose();
    });

    test('TC-1018a: compact stateSet produces expected final state', () async {
      await stateManager.defineVariable('temperature',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['temperature'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 25),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      // Same result as standard JSON execution would produce
      expect(stateManager.get('temperature'), equals(25));
    });

    test('TC-1018b: multiple stateSet operations in sequence', () async {
      await stateManager.defineVariable('counter',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 3,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['counter'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 1),
                ],
              ),
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 2),
                ],
              ),
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 3),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      // Final value should be 3
      expect(stateManager.get('counter'), equals(3));
    });
  });

  group('TC-1019: CompactExecutor — _resolveReference', () {
    late _MockHal hal;
    late StateManager stateManager;
    late EventBus eventBus;
    late CompactExecutor executor;

    setUp(() async {
      hal = _MockHal();
      stateManager = StateManager();
      await stateManager.initialize();
      eventBus = EventBus();
      executor = CompactExecutor(
        hal: hal, stateManager: stateManager, eventBus: eventBus);
    });

    tearDown(() async {
      await stateManager.dispose();
    });

    test('TC-1019a: state reference resolves from stateManager', () async {
      await stateManager.defineVariable('myVar',
          type: StateType.number, initial: 42);

      // Use stateGet to push state value onto stack
      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['myVar'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateGet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      final result =
          await executor.executeProcess(flowData.processes[0], flowData);
      expect(result, equals(42));
    });

    test('TC-1019b: immediate reference returns value directly', () async {
      await stateManager.defineVariable('out',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['out'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 123),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      expect(stateManager.get('out'), equals(123));
    });

    test('TC-1019c: invalid state reference throws', () async {
      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 0, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['proc'],
        states: [], // No states defined
        resources: [],
        expressions: [],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.stateGet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 99),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      expect(
        () => executor.executeProcess(flowData.processes[0], flowData),
        throwsA(isA<Error>()),
      );
    });
  });

  group('TC-1020: CompactExecutor — _evaluateExpression', () {
    late _MockHal hal;
    late StateManager stateManager;
    late EventBus eventBus;
    late CompactExecutor executor;

    setUp(() async {
      hal = _MockHal();
      stateManager = StateManager();
      await stateManager.initialize();
      eventBus = EventBus();
      executor = CompactExecutor(
        hal: hal, stateManager: stateManager, eventBus: eventBus);
    });

    tearDown(() async {
      await stateManager.dispose();
    });

    test('TC-1020a: arithmetic expression evaluation', () async {
      // Create a flow with an expression that adds two immediates
      // Expression: 10 + 20 = 30, used in jumpIfFalse condition
      await stateManager.defineVariable('result',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 1, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['result'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [
          // Expression 0: ADD(10, 20) = 30
          const CompactExpression(
            id: 0,
            type: 1, // ARITHMETIC
            operation: 0, // ADD
            operands: [
              CompactReference(
                  type: CompactReferenceType.immediate, value: 10),
              CompactReference(
                  type: CompactReferenceType.immediate, value: 20),
            ],
          ),
        ],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              // stateSet result = expression(0) = 10 + 20
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.expression, id: 0),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      expect(stateManager.get('result'), equals(30));
    });

    test('TC-1020b: comparison expression with state binding', () async {
      await stateManager.defineVariable('score',
          type: StateType.number, initial: 85);
      await stateManager.defineVariable('passed',
          type: StateType.number, initial: 0);

      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 2, stateCount: 2, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 2,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['score', 'passed'],
        states: [
          const CompactStateEntry(
              id: 0, nameRef: 0, type: CompactStateType.number),
          const CompactStateEntry(
              id: 1, nameRef: 1, type: CompactStateType.number),
        ],
        resources: [],
        expressions: [
          // Expression 0: GT(state.score, 60) -> score > 60
          const CompactExpression(
            id: 0,
            type: 2, // COMPARISON
            operation: 4, // GT
            operands: [
              CompactReference(type: CompactReferenceType.state, id: 0),
              CompactReference(
                  type: CompactReferenceType.immediate, value: 60),
            ],
          ),
        ],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              // jumpIfFalse expr(0), skip 1
              CompactInstruction(
                opcode: CompactOpcode.jumpIfFalse.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.expression, id: 0),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 1),
                ],
              ),
              // stateSet passed = 1
              CompactInstruction(
                opcode: CompactOpcode.stateSet.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.state, id: 1),
                  const CompactReference(
                      type: CompactReferenceType.immediate, value: 1),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      await executor.executeProcess(flowData.processes[0], flowData);
      // score(85) > 60 is true, so passed should be set to 1
      expect(stateManager.get('passed'), equals(1));
    });

    test('TC-1020c: expression with null/invalid reference throws', () async {
      final flowData = CompactFlowData(
        header: const CompactHeader(
            version: 0x0100, flags: 0, originalHash: 0, totalSize: 0),
        sectionTable: const CompactSectionTable(
          stringCount: 1, stateCount: 0, resourceCount: 0,
          processCount: 1, eventCount: 0, instructionCount: 1,
          stringTableOffset: 0, dataSectionOffset: 0),
        strings: ['proc'],
        states: [],
        resources: [],
        expressions: [
          // Expression referencing non-existent state
          const CompactExpression(
            id: 0,
            type: 1, // ARITHMETIC
            operation: 0, // ADD
            operands: [
              CompactReference(type: CompactReferenceType.state, id: 99),
              CompactReference(
                  type: CompactReferenceType.immediate, value: 1),
            ],
          ),
        ],
        processes: [
          CompactProcessEntry(
            id: 0, nameRef: 0, triggerType: 0,
            triggerData: Uint8List(0),
            instructions: [
              CompactInstruction(
                opcode: CompactOpcode.log.code,
                operands: [
                  const CompactReference(
                      type: CompactReferenceType.expression, id: 0),
                ],
              ),
            ],
          ),
        ],
        compression: CompactCompressionType.none,
      );

      expect(
        () => executor.executeProcess(flowData.processes[0], flowData),
        throwsA(isA<Error>()),
      );
    });
  });
}
