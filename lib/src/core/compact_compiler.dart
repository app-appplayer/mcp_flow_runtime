/// CompactCompiler - Compiles FlowDefinition to compact binary format (.fcmp)
/// MOD-CORE-008

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import '../types/flow_types.dart';
import '../errors/flow_errors.dart';
import '../parser/json_parser.dart';
import '../parser/validator.dart';
import 'compact_types.dart';

/// Compiles JSON Flow DSL into Compact Binary Format (.fcmp).
///
/// Pipeline: parse -> optimize -> emit -> package
class CompactCompiler {
  final CompactCompressionType compressionType;
  final bool enableOptimizations;
  final bool includeDebugInfo;

  final Logger _log = Logger('CompactCompiler');

  // Build-time tables populated during compilation
  final List<String> _stringTable = [];
  final Map<String, int> _stringIndex = {};
  final Map<String, int> _stateIds = {};
  final Map<String, int> _resourceIds = {};
  final Map<String, int> _processIds = {};
  final List<CompactExpression> _expressionTable = [];

  CompactCompiler({
    this.compressionType = CompactCompressionType.none,
    this.enableOptimizations = true,
    this.includeDebugInfo = false,
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Compile a FlowDefinition into .fcmp binary bytes.
  Future<Uint8List> compile(FlowDefinition flow) async {
    _log.info('Starting compact compilation');
    _reset();

    // Stage 1 - Parse: build symbol tables
    _extractStrings(flow);
    _buildStateSymbols(flow.state);
    _buildResourceSymbols(flow.resources);
    _buildProcessSymbols(flow.processes);

    // Stage 2 - Optimize
    if (enableOptimizations) {
      _eliminateDeadCode(flow);
      _foldConstants();
    }

    // Stage 3 - Emit
    final states = _compileStates(flow.state);
    final resources = _compileResources(flow.resources);
    final expressions = List<CompactExpression>.from(_expressionTable);
    final processes = _compileProcesses(flow.processes);

    // Stage 4 - Package
    final rawBytes = _serializeAll(states, resources, expressions, processes);
    final compressedBytes = _compress(rawBytes);
    final originalHash = _computeSourceHash(flow);
    final header = _buildHeader(compressedBytes.length, originalHash);
    final result = _assembleFile(header, compressedBytes);

    _log.info('Compilation complete: ${result.length} bytes');
    return result;
  }

  /// Compile from raw JSON map.
  Future<Uint8List> compileFromJson(Map<String, dynamic> json) async {
    final flow = JsonFlowParser().parse(json);
    final validationErrors = FlowValidator().validate(flow);
    final errors = validationErrors
        .where((e) => e.severity == ValidationSeverity.error)
        .toList();
    if (errors.isNotEmpty) {
      throw FlowValidationError(
        'Validation failed with ${errors.length} error(s)',
        errors: validationErrors,
      );
    }
    return compile(flow);
  }

  /// Compile a JSON file to a .fcmp file.
  Future<void> compileFile(String inputJsonPath, String outputFcmpPath) async {
    final content = await File(inputJsonPath).readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final bytes = await compileFromJson(json);
    await File(outputFcmpPath).writeAsBytes(bytes);
    _log.info('Written $outputFcmpPath (${bytes.length} bytes)');
  }

  // ---------------------------------------------------------------------------
  // Stage 1 - Parse / Symbol tables
  // ---------------------------------------------------------------------------

  void _reset() {
    _stringTable.clear();
    _stringIndex.clear();
    _stateIds.clear();
    _resourceIds.clear();
    _processIds.clear();
    _expressionTable.clear();
  }

  /// Collect all strings from the flow and build a frequency-sorted string table.
  void _extractStrings(FlowDefinition flow) {
    final frequency = <String, int>{};

    void addStr(String? s) {
      if (s == null) return;
      frequency[s] = (frequency[s] ?? 0) + 1;
    }

    // Metadata
    addStr(flow.metadata?.name);
    addStr(flow.metadata?.description);
    addStr(flow.version);

    // States
    for (final entry in flow.state.entries) {
      addStr(entry.key);
      if (entry.value.initial is String) addStr(entry.value.initial as String);
    }

    // Resources
    for (final entry in flow.resources.entries) {
      addStr(entry.key);
      addStr(entry.value.type);
    }

    // Processes
    for (final proc in flow.processes) {
      addStr(proc.id);
      addStr(proc.name);
      addStr(proc.description);
      _extractStringsFromSteps(proc.steps, addStr);
    }

    // Sort by frequency descending for optimal encoding
    final sorted = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sorted) {
      _addString(entry.key);
    }
  }

  void _extractStringsFromSteps(
      List<ActionDefinition> steps, void Function(String?) addStr) {
    for (final step in steps) {
      addStr(step.action);
      addStr(step.bindTo);
      step.params?.forEach((key, value) {
        addStr(key);
        if (value is String) addStr(value);
      });
      if (step.then != null) _extractStringsFromSteps(step.then!, addStr);
      if (step.else$ != null) _extractStringsFromSteps(step.else$!, addStr);
      if (step.do$ != null) _extractStringsFromSteps(step.do$!, addStr);
    }
  }

  int _addString(String s) {
    if (_stringIndex.containsKey(s)) return _stringIndex[s]!;
    final idx = _stringTable.length;
    _stringTable.add(s);
    _stringIndex[s] = idx;
    return idx;
  }

  void _buildStateSymbols(Map<String, StateDefinition> states) {
    var id = 0;
    for (final name in states.keys) {
      _stateIds[name] = id++;
    }
  }

  void _buildResourceSymbols(Map<String, ResourceDefinition> resources) {
    var id = 0;
    for (final name in resources.keys) {
      _resourceIds[name] = id++;
    }
  }

  void _buildProcessSymbols(List<ProcessDefinition> processes) {
    var id = 0;
    for (final proc in processes) {
      _processIds[proc.id] = id++;
    }
  }

  // ---------------------------------------------------------------------------
  // Stage 2 - Optimize
  // ---------------------------------------------------------------------------

  void _eliminateDeadCode(FlowDefinition flow) {
    // TODO: Remove unreachable processes/states that are never referenced
    _log.fine('Dead code elimination pass (stub)');
  }

  void _foldConstants() {
    // TODO: Pre-evaluate constant expressions and replace with IMMEDIATE refs
    _log.fine('Constant folding pass (stub)');
  }

  // ---------------------------------------------------------------------------
  // Stage 3 - Emit
  // ---------------------------------------------------------------------------

  List<CompactStateEntry> _compileStates(Map<String, StateDefinition> states) {
    final entries = <CompactStateEntry>[];
    for (final entry in states.entries) {
      final name = entry.key;
      final def = entry.value;
      var flags = 0;
      if (def.persistent) flags |= 0x01;
      // READONLY flag: no direct field in StateSecurityConfig; reserved for future use

      entries.add(CompactStateEntry(
        id: _stateIds[name]!,
        nameRef: _stringIndex[name]!,
        type: _mapStateType(def.type),
        flags: flags,
        initialValue: def.initial,
      ));
    }
    return entries;
  }

  List<CompactResourceEntry> _compileResources(
      Map<String, ResourceDefinition> resources) {
    final entries = <CompactResourceEntry>[];
    for (final entry in resources.entries) {
      final name = entry.key;
      final def = entry.value;
      entries.add(CompactResourceEntry(
        id: _resourceIds[name]!,
        nameRef: _stringIndex[name]!,
        type: _mapResourceType(def.type),
        configData: _encodeConfig(def.config),
        mcpBinding: _compileMcpBinding(def.mcp),
      ));
    }
    return entries;
  }

  List<CompactProcessEntry> _compileProcesses(
      List<ProcessDefinition> processes) {
    final entries = <CompactProcessEntry>[];
    for (final proc in processes) {
      final instructions = <CompactInstruction>[];
      final variables = <CompactLocalVariable>[];
      var varId = 0;

      for (final step in proc.steps) {
        final compiled = _compileStep(step, variables, varId);
        instructions.addAll(compiled.instructions);
        varId = compiled.nextVarId;
      }

      entries.add(CompactProcessEntry(
        id: _processIds[proc.id]!,
        nameRef: _stringIndex[proc.id]!,
        triggerType: _mapTriggerType(proc.trigger?.type),
        triggerData: _encodeTrigger(proc.trigger),
        instructions: instructions,
        variables: variables,
        mcpBinding: null, // TD-012: mcp removed from ProcessDefinition
      ));
    }
    return entries;
  }

  /// Compile a single action step into bytecode instructions.
  _CompileResult _compileStep(
    ActionDefinition step,
    List<CompactLocalVariable> variables,
    int nextVarId,
  ) {
    final instructions = <CompactInstruction>[];
    final action = step.action;

    // Map action to opcode
    final opcode = _actionToOpcode(action);

    // Handle control flow actions specially
    switch (action) {
      case 'if':
        return _compileIf(step, variables, nextVarId);
      case 'while' || 'for':
        return _compileLoop(step, variables, nextVarId);
      case 'switch':
        return _compileSwitch(step, variables, nextVarId);
      default:
        break;
    }

    // Compile operands from params
    final operands = <CompactReference>[];
    step.params?.forEach((key, value) {
      operands.add(_compileValue(value));
    });

    instructions.add(CompactInstruction(
      opcode: opcode,
      operands: operands,
    ));

    // Handle bindTo: allocate a local variable
    if (step.bindTo != null) {
      final varEntry = CompactLocalVariable(
        id: nextVarId,
        name: step.bindTo!,
        type: CompactStateType.object, // default; refined at runtime
      );
      variables.add(varEntry);
      nextVarId++;
    }

    return _CompileResult(instructions, nextVarId);
  }

  _CompileResult _compileIf(
    ActionDefinition step,
    List<CompactLocalVariable> variables,
    int nextVarId,
  ) {
    final instructions = <CompactInstruction>[];

    // Condition reference
    final condRef = step.condition != null
        ? _compileExpression(step.condition!)
        : const CompactReference(
            type: CompactReferenceType.immediate, value: true);

    // Compile then block
    final thenInstructions = <CompactInstruction>[];
    for (final s in (step.then ?? <ActionDefinition>[])) {
      final r = _compileStep(s, variables, nextVarId);
      thenInstructions.addAll(r.instructions);
      nextVarId = r.nextVarId;
    }

    // Compile else block
    final elseInstructions = <CompactInstruction>[];
    for (final s in (step.else$ ?? <ActionDefinition>[])) {
      final r = _compileStep(s, variables, nextVarId);
      elseInstructions.addAll(r.instructions);
      nextVarId = r.nextVarId;
    }

    // Emit: JUMP_IF_FALSE <condition> <offset-to-else>
    final elseOffset = thenInstructions.length + (elseInstructions.isEmpty ? 0 : 1);
    instructions.add(CompactInstruction(
      opcode: CompactOpcode.jumpIfFalse.code,
      operands: [
        condRef,
        CompactReference(
            type: CompactReferenceType.immediate, value: elseOffset),
      ],
    ));

    instructions.addAll(thenInstructions);

    if (elseInstructions.isNotEmpty) {
      // JUMP past else block
      instructions.add(CompactInstruction(
        opcode: CompactOpcode.jump.code,
        operands: [
          CompactReference(
              type: CompactReferenceType.immediate,
              value: elseInstructions.length),
        ],
      ));
      instructions.addAll(elseInstructions);
    }

    return _CompileResult(instructions, nextVarId);
  }

  _CompileResult _compileLoop(
    ActionDefinition step,
    List<CompactLocalVariable> variables,
    int nextVarId,
  ) {
    final instructions = <CompactInstruction>[];

    // LOOP_START
    instructions.add(CompactInstruction(
      opcode: CompactOpcode.loopStart.code,
      operands: step.condition != null
          ? [_compileExpression(step.condition!)]
          : [],
    ));

    // Body
    for (final s in (step.do$ ?? <ActionDefinition>[])) {
      final r = _compileStep(s, variables, nextVarId);
      instructions.addAll(r.instructions);
      nextVarId = r.nextVarId;
    }

    // LOOP_END
    instructions.add(CompactInstruction(
      opcode: CompactOpcode.loopEnd.code,
    ));

    return _CompileResult(instructions, nextVarId);
  }

  _CompileResult _compileSwitch(
    ActionDefinition step,
    List<CompactLocalVariable> variables,
    int nextVarId,
  ) {
    final instructions = <CompactInstruction>[];

    final valueRef = step.value != null
        ? _compileValue(step.value)
        : const CompactReference(
            type: CompactReferenceType.immediate, value: null);

    // SWITCH instruction with case count
    instructions.add(CompactInstruction(
      opcode: CompactOpcode.switchOp.code,
      operands: [valueRef],
    ));

    // TODO: Emit case table and case bodies
    _log.fine('Switch compilation stub - cases not fully emitted');

    return _CompileResult(instructions, nextVarId);
  }

  // ---------------------------------------------------------------------------
  // Stage 4 - Package / Serialize
  // ---------------------------------------------------------------------------

  Uint8List _serializeAll(
    List<CompactStateEntry> states,
    List<CompactResourceEntry> resources,
    List<CompactExpression> expressions,
    List<CompactProcessEntry> processes,
  ) {
    final builder = BytesBuilder();

    // Section table placeholder (filled after measuring offsets)
    // 6 count fields x 2 bytes + 2 offset fields x 4 bytes = 20 bytes
    final sectionTableSize = 20;
    final sectionTableBytes = Uint8List(sectionTableSize);
    builder.add(sectionTableBytes);

    // String table
    final stringTableOffset = builder.length;
    for (final s in _stringTable) {
      final encoded = utf8.encode(s);
      if (encoded.length > 255) {
        _log.warning('String truncated to 255 bytes: $s');
      }
      builder.addByte(encoded.length.clamp(0, 255));
      builder.add(encoded.length > 255 ? encoded.sublist(0, 255) : encoded);
    }

    // Data section
    final dataSectionOffset = builder.length;

    // States
    for (final state in states) {
      _serializeStateEntry(builder, state);
    }

    // Resources
    for (final res in resources) {
      _serializeResourceEntry(builder, res);
    }

    // Expressions
    for (final expr in expressions) {
      _serializeExpression(builder, expr);
    }

    // Processes (instructions)
    var totalInstructions = 0;
    for (final proc in processes) {
      _serializeProcessEntry(builder, proc);
      totalInstructions += proc.instructions.length;
    }

    // Patch section table
    final sectionData = ByteData(sectionTableSize);
    // Count fields: uint16 (2 bytes each)
    sectionData.setUint16(0, _stringTable.length, Endian.little);
    sectionData.setUint16(2, states.length, Endian.little);
    sectionData.setUint16(4, resources.length, Endian.little);
    sectionData.setUint16(6, processes.length, Endian.little);
    sectionData.setUint16(8, 0, Endian.little); // eventCount
    sectionData.setUint16(10, totalInstructions, Endian.little);
    // Offset fields: uint32 (4 bytes each)
    sectionData.setUint32(12, stringTableOffset, Endian.little);
    sectionData.setUint32(16, dataSectionOffset, Endian.little);

    final result = builder.toBytes();
    final mutable = Uint8List.fromList(result);
    mutable.setRange(0, sectionTableSize, sectionData.buffer.asUint8List());
    return mutable;
  }

  void _serializeStateEntry(BytesBuilder builder, CompactStateEntry entry) {
    final bd = ByteData(8);
    bd.setUint16(0, entry.id, Endian.little);
    bd.setUint16(2, entry.nameRef, Endian.little);
    bd.setUint8(4, entry.type.index + 1);
    bd.setUint8(5, entry.flags);
    // 2 bytes reserved
    builder.add(bd.buffer.asUint8List());
    // Encode initial value as JSON bytes
    final initialBytes = utf8.encode(jsonEncode(entry.initialValue));
    builder.addByte(initialBytes.length.clamp(0, 255));
    builder.add(initialBytes.length > 255
        ? initialBytes.sublist(0, 255)
        : initialBytes);
  }

  void _serializeResourceEntry(
      BytesBuilder builder, CompactResourceEntry entry) {
    final bd = ByteData(6);
    bd.setUint16(0, entry.id, Endian.little);
    bd.setUint16(2, entry.nameRef, Endian.little);
    bd.setUint8(4, entry.type.index + 1);
    bd.setUint8(5, 0); // reserved
    builder.add(bd.buffer.asUint8List());
    // Config data with length prefix
    final len = entry.configData.length.clamp(0, 0xFFFF);
    final lenBd = ByteData(2);
    lenBd.setUint16(0, len, Endian.little);
    builder.add(lenBd.buffer.asUint8List());
    builder.add(entry.configData.sublist(0, len));
  }

  void _serializeExpression(BytesBuilder builder, CompactExpression expr) {
    builder.addByte(expr.type);
    builder.addByte(expr.operation);
    builder.addByte(expr.operands.length);
    for (final op in expr.operands) {
      _serializeReference(builder, op);
    }
  }

  void _serializeProcessEntry(
      BytesBuilder builder, CompactProcessEntry entry) {
    final bd = ByteData(6);
    bd.setUint16(0, entry.id, Endian.little);
    bd.setUint16(2, entry.nameRef, Endian.little);
    bd.setUint8(4, entry.triggerType);
    bd.setUint8(5, entry.triggerData.length.clamp(0, 255));
    builder.add(bd.buffer.asUint8List());
    builder.add(entry.triggerData);

    // Instructions
    final instCountBd = ByteData(2);
    instCountBd.setUint16(0, entry.instructions.length, Endian.little);
    builder.add(instCountBd.buffer.asUint8List());

    for (final inst in entry.instructions) {
      builder.addByte(inst.opcode);
      if (inst.opcode == 0xFF && inst.extendedOpcode != null) {
        final extBd = ByteData(2);
        extBd.setUint16(0, inst.extendedOpcode!, Endian.little);
        builder.add(extBd.buffer.asUint8List());
      }
      builder.addByte(inst.operands.length);
      for (final op in inst.operands) {
        _serializeReference(builder, op);
      }
    }
  }

  void _serializeReference(BytesBuilder builder, CompactReference ref) {
    builder.addByte(ref.type.index);
    final bd = ByteData(4);
    if (ref.type == CompactReferenceType.immediate) {
      // Encode immediate value as 4-byte representation
      if (ref.value is int) {
        bd.setInt32(0, ref.value as int, Endian.little);
      } else if (ref.value is bool) {
        bd.setInt32(0, (ref.value as bool) ? 1 : 0, Endian.little);
      } else if (ref.value is double) {
        // Store as float32 approximation
        bd.setFloat32(0, (ref.value as double), Endian.little);
      } else {
        bd.setInt32(0, 0, Endian.little);
      }
    } else {
      bd.setUint32(0, ref.id, Endian.little);
    }
    builder.add(bd.buffer.asUint8List());
    builder.addByte(ref.flags);
  }

  Uint8List _compress(Uint8List data) {
    switch (compressionType) {
      case CompactCompressionType.none:
        return data;
      case CompactCompressionType.zlib:
        return Uint8List.fromList(zlib.encode(data));
      case CompactCompressionType.lz4:
        // TODO: LZ4 compression requires external package
        _log.warning('LZ4 compression not available, using raw');
        return data;
    }
  }

  int _computeSourceHash(FlowDefinition flow) {
    final jsonStr = jsonEncode(flow.toJson());
    final digest = sha256.convert(utf8.encode(jsonStr));
    // First 4 bytes of SHA-256
    return (digest.bytes[0] << 24) |
        (digest.bytes[1] << 16) |
        (digest.bytes[2] << 8) |
        digest.bytes[3];
  }

  Uint8List _buildHeader(int bodySize, int originalHash) {
    final bd = ByteData(CompactHeader.size);
    bd.setUint32(0, CompactHeader.magicNumber, Endian.big);
    bd.setUint16(4, 0x0100, Endian.little); // version 1.0
    bd.setUint16(6, compressionType.index, Endian.little); // flags
    bd.setUint32(8, originalHash, Endian.little);
    bd.setUint32(12, CompactHeader.size + bodySize, Endian.little);
    return bd.buffer.asUint8List();
  }

  Uint8List _assembleFile(Uint8List header, Uint8List body) {
    final builder = BytesBuilder();
    builder.add(header);
    builder.add(body);
    return builder.toBytes();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Map action string to opcode value.
  int _actionToOpcode(String action) {
    return switch (action) {
      'gpioConfigure' => 0x01,
      'gpioWrite' => 0x02,
      'gpioRead' => 0x03,
      'gpioToggle' => 0x04,
      'pwmConfig' => 0x06,
      'pwmSet' => 0x07,
      'i2cWrite' => 0x09,
      'i2cRead' => 0x0A,
      'adcRead' => 0x0C,
      'uartWrite' => 0x0E,
      'uartRead' => 0x0F,
      'if' => 0x22,
      'while' || 'for' => 0x25,
      'switch' => 0x23,
      'return' => 0x2B,
      'stateGet' => 0x40,
      'stateSet' => 0x41,
      'stateUpdate' => 0x42,
      'processStart' => 0x60,
      'processStop' => 0x61,
      'processRestart' => 0x62,
      'processSignal' => 0x63,
      'channelSend' => 0x65,
      'channelReceive' => 0x66,
      'mcpNotify' => 0x80,
      'wait' => 0xA0,
      'log' => 0xA4,
      'assert' => 0xA5,
      'exit' => 0xA7,
      'systemExec' => 0xA8,
      _ => throw FlowParseError('Unknown action: $action'),
    };
  }

  /// Compile an expression string (e.g. "{{state.temperature > 30}}") to a reference.
  CompactReference _compileExpression(String expr) {
    final templatePattern = RegExp(r'^\{\{(.+)\}\}$');
    final match = templatePattern.firstMatch(expr.trim());

    if (match != null) {
      final inner = match.group(1)!.trim();

      // Simple state reference: "state.name"
      final stateRefPattern = RegExp(r'^state\.(\w+)$');
      final stateMatch = stateRefPattern.firstMatch(inner);
      if (stateMatch != null) {
        final name = stateMatch.group(1)!;
        final id = _stateIds[name];
        if (id != null) {
          return CompactReference(type: CompactReferenceType.state, id: id);
        }
      }

      // Complex expression: parse and add to expression table
      final exprEntry = _parseAndEmitExpression(inner);
      return CompactReference(
          type: CompactReferenceType.expression, id: exprEntry.id);
    }

    // Literal string
    final idx = _addString(expr);
    return CompactReference(type: CompactReferenceType.string, id: idx);
  }

  /// Parse a complex expression and emit into the expression table.
  CompactExpression _parseAndEmitExpression(String expr) {
    // TODO: Full AST parsing for arithmetic, comparison, logical expressions.
    // For now, emit a placeholder REFERENCE expression.
    final id = _expressionTable.length;
    final entry = CompactExpression(
      id: id,
      type: 0, // REFERENCE
      operation: 0,
      operands: [
        CompactReference(
          type: CompactReferenceType.string,
          id: _addString(expr),
        ),
      ],
    );
    _expressionTable.add(entry);
    return entry;
  }

  CompactReference _compileValue(dynamic value) {
    if (value is int) {
      return CompactReference(
          type: CompactReferenceType.immediate, value: value);
    }
    if (value is double) {
      return CompactReference(
          type: CompactReferenceType.immediate, value: value);
    }
    if (value is bool) {
      return CompactReference(
          type: CompactReferenceType.immediate, value: value);
    }
    if (value is String) {
      // Check if expression template
      if (value.startsWith('{{') && value.endsWith('}}')) {
        return _compileExpression(value);
      }
      // Check if state reference
      if (_stateIds.containsKey(value)) {
        return CompactReference(
            type: CompactReferenceType.state, id: _stateIds[value]!);
      }
      // Check if resource reference
      if (_resourceIds.containsKey(value)) {
        return CompactReference(
            type: CompactReferenceType.resource, id: _resourceIds[value]!);
      }
      // String literal
      return CompactReference(
          type: CompactReferenceType.string, id: _addString(value));
    }
    // Fallback: encode as immediate null
    return const CompactReference(
        type: CompactReferenceType.immediate, value: null);
  }

  CompactStateType _mapStateType(StateType type) {
    return switch (type) {
      StateType.boolean => CompactStateType.boolean,
      StateType.number => CompactStateType.number,
      StateType.string => CompactStateType.string,
      StateType.object => CompactStateType.object,
      StateType.array => CompactStateType.array,
      StateType.any => CompactStateType.object,
    };
  }

  CompactResourceType _mapResourceType(String type) {
    return switch (type.toLowerCase()) {
      'gpio' => CompactResourceType.gpio,
      'i2c' => CompactResourceType.i2c,
      'pwm' => CompactResourceType.pwm,
      'adc' => CompactResourceType.adc,
      'uart' => CompactResourceType.uart,
      'modbus' => CompactResourceType.modbus,
      'spi' => CompactResourceType.spi,
      'mqtt' => CompactResourceType.mqtt,
      _ => CompactResourceType.gpio, // fallback
    };
  }

  int _mapTriggerType(TriggerType? type) {
    if (type == null) return 0; // MANUAL
    return switch (type) {
      TriggerType.manual => 0,
      TriggerType.schedule => 1,
      TriggerType.event => 2,
      TriggerType.stateChange => 4,
      _ => 0,
    };
  }

  Uint8List _encodeTrigger(TriggerDefinition? trigger) {
    if (trigger == null) return Uint8List(0);
    // Encode trigger config as compact JSON
    final bytes = utf8.encode(jsonEncode(trigger.toJson()));
    return Uint8List.fromList(bytes);
  }

  Uint8List _encodeConfig(Map<String, dynamic> config) {
    final bytes = utf8.encode(jsonEncode(config));
    return Uint8List.fromList(bytes);
  }

  CompactMcpBinding? _compileMcpBinding(dynamic mcp) {
    if (mcp == null) return null;
    // Handle both McpResourceBinding and McpProcessBinding
    // TODO: Extract fields from the typed MCP binding objects
    return const CompactMcpBinding(expose: true);
  }
}

/// Internal result type for step compilation
class _CompileResult {
  final List<CompactInstruction> instructions;
  final int nextVarId;

  const _CompileResult(this.instructions, this.nextVarId);
}
