/// CompactLoader - Deserializes .fcmp binary into CompactFlowData
/// MOD-CORE-009

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../types/flow_types.dart';
import '../errors/flow_errors.dart';
import 'compact_types.dart';

/// Loads and deserializes compact binary format (.fcmp) files.
///
/// Reconstructs [CompactFlowData] from binary, and can convert back
/// to [FlowDefinition] for compatibility with the standard runtime.
class CompactLoader {
  static const String mimeType = 'application/x-mcp-flow';
  static const List<int> magicBytes = [0x46, 0x43, 0x4D, 0x50]; // 'FCMP'

  final Logger _log = Logger('CompactLoader');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Load compact binary data into [CompactFlowData].
  Future<CompactFlowData> load(Uint8List data) async {
    if (data.length < CompactHeader.size) {
      throw FlowParseError('Compact data too short: ${data.length} bytes');
    }

    _validateMagic(data);
    final header = _parseHeader(data);
    _validateVersion(header.version);

    final compression = CompactCompressionType.values[header.flags & 0x0F];
    final body =
        compression != CompactCompressionType.none
            ? _decompress(data, compression)
            : data.sublist(CompactHeader.size);

    final sectionTable = _parseSectionTable(body);
    final strings = _parseStringTable(body, sectionTable);
    final states = _parseStateTable(body, sectionTable, strings);
    final resources = _parseResourceTable(body, sectionTable, strings);
    final expressions = _parseExpressionTable(body, sectionTable);
    final processes = _parseProcessTable(body, sectionTable, strings);

    _log.info(
      'Loaded compact flow: ${strings.length} strings, '
      '${states.length} states, ${resources.length} resources, '
      '${processes.length} processes',
    );

    return CompactFlowData(
      header: header,
      sectionTable: sectionTable,
      strings: strings,
      states: states,
      resources: resources,
      expressions: expressions,
      processes: processes,
      compression: compression,
    );
  }

  /// Load a .fcmp file from disk.
  Future<CompactFlowData> loadFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return load(bytes);
  }

  /// Convert [CompactFlowData] back to a [FlowDefinition].
  FlowDefinition toFlowDefinition(CompactFlowData data) {
    // Reconstruct state definitions
    final stateMap = <String, StateDefinition>{};
    for (final entry in data.states) {
      final name = data.strings[entry.nameRef];
      stateMap[name] = StateDefinition(
        type: _reverseStateType(entry.type),
        initial: entry.initialValue,
        persistent: entry.isPersistent,
      );
    }

    // Reconstruct resource definitions
    final resourceMap = <String, ResourceDefinition>{};
    for (final entry in data.resources) {
      final name = data.strings[entry.nameRef];
      final configJson = _decodeConfig(entry.configData);
      resourceMap[name] = ResourceDefinition(
        type: entry.type.name,
        config: configJson,
      );
    }

    // Reconstruct process definitions
    final processes = <ProcessDefinition>[];
    for (final entry in data.processes) {
      final name = data.strings[entry.nameRef];
      // Reconstruct steps from bytecode instructions
      final steps = _reconstructSteps(entry.instructions, data);
      processes.add(ProcessDefinition(
        id: name,
        name: name,
        trigger: _reconstructTrigger(entry),
        steps: steps,
      ));
    }

    // Determine version from header
    final majorVersion = (data.header.version >> 8) & 0xFF;
    final minorVersion = data.header.version & 0xFF;

    return FlowDefinition(
      version: '$majorVersion.$minorVersion',
      metadata: FlowMetadata(name: 'compact-flow'),
      state: stateMap,
      resources: resourceMap,
      processes: processes,
    );
  }

  // ---------------------------------------------------------------------------
  // Header parsing
  // ---------------------------------------------------------------------------

  void _validateMagic(Uint8List data) {
    for (var i = 0; i < 4; i++) {
      if (data[i] != magicBytes[i]) {
        throw FlowParseError(
          'Invalid magic bytes: expected FCMP, got '
          '${data.sublist(0, 4).map((b) => b.toRadixString(16)).join(' ')}',
        );
      }
    }
  }

  CompactHeader _parseHeader(Uint8List data) {
    final bd = ByteData.sublistView(data);
    return CompactHeader(
      version: bd.getUint16(4, Endian.little),
      flags: bd.getUint16(6, Endian.little),
      originalHash: bd.getUint32(8, Endian.little),
      totalSize: bd.getUint32(12, Endian.little),
    );
  }

  void _validateVersion(int version) {
    final major = (version >> 8) & 0xFF;
    if (major > 1) {
      throw FlowParseError(
        'Unsupported compact format version: $major.${version & 0xFF}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Section / table parsing
  // ---------------------------------------------------------------------------

  CompactSectionTable _parseSectionTable(Uint8List body) {
    // Section table: 6 count fields x 2 bytes + 2 offset fields x 4 bytes = 20 bytes
    if (body.length < CompactSectionTable.size) {
      throw FlowParseError('Section table too short');
    }
    final bd = ByteData.sublistView(body);
    return CompactSectionTable(
      // Count fields: uint16 (2 bytes each)
      stringCount: bd.getUint16(0, Endian.little),
      stateCount: bd.getUint16(2, Endian.little),
      resourceCount: bd.getUint16(4, Endian.little),
      processCount: bd.getUint16(6, Endian.little),
      eventCount: bd.getUint16(8, Endian.little),
      instructionCount: bd.getUint16(10, Endian.little),
      // Offset fields: uint32 (4 bytes each)
      stringTableOffset: bd.getUint32(12, Endian.little),
      dataSectionOffset: bd.getUint32(16, Endian.little),
    );
  }

  List<String> _parseStringTable(
      Uint8List data, CompactSectionTable section) {
    var offset = section.stringTableOffset;
    final strings = <String>[];
    for (var i = 0; i < section.stringCount; i++) {
      if (offset >= data.length) break;
      final length = data[offset];
      offset += 1;
      if (offset + length > data.length) {
        throw FlowParseError('String table overflow at index $i');
      }
      strings.add(utf8.decode(data.sublist(offset, offset + length)));
      offset += length;
    }
    return strings;
  }

  List<CompactStateEntry> _parseStateTable(
    Uint8List data,
    CompactSectionTable section,
    List<String> strings,
  ) {
    var offset = section.dataSectionOffset;
    final states = <CompactStateEntry>[];

    for (var i = 0; i < section.stateCount; i++) {
      if (offset + 8 > data.length) break;
      final bd = ByteData.sublistView(data, offset);
      final id = bd.getUint16(0, Endian.little);
      final nameRef = bd.getUint16(2, Endian.little);
      final typeVal = bd.getUint8(4);
      final flags = bd.getUint8(5);
      offset += 8;

      // Parse initial value (length-prefixed JSON)
      dynamic initialValue;
      if (offset < data.length) {
        final ivLen = data[offset];
        offset += 1;
        if (offset + ivLen <= data.length) {
          final ivStr = utf8.decode(data.sublist(offset, offset + ivLen));
          try {
            initialValue = jsonDecode(ivStr);
          } on FormatException {
            initialValue = ivStr;
          }
          offset += ivLen;
        }
      }

      states.add(CompactStateEntry(
        id: id,
        nameRef: nameRef,
        type: CompactStateType.values[(typeVal - 1).clamp(0, 4)],
        flags: flags,
        initialValue: initialValue,
      ));
    }
    return states;
  }

  List<CompactResourceEntry> _parseResourceTable(
    Uint8List data,
    CompactSectionTable section,
    List<String> strings,
  ) {
    // Resources follow states in the data section.
    // We need to skip past states first; for simplicity track offset via
    // sequential parsing. This is a simplified approach.
    // TODO: Use precise offset tracking by calculating state section size
    final resources = <CompactResourceEntry>[];
    _log.fine('Resource table parsing (${section.resourceCount} entries)');

    // Stub: In production, we would track the exact offset after parsing states.
    // For now return empty if we cannot determine offset reliably.
    if (section.resourceCount == 0) return resources;

    // TODO: Implement full resource table deserialization with proper offset tracking
    return resources;
  }

  List<CompactExpression> _parseExpressionTable(
    Uint8List data,
    CompactSectionTable section,
  ) {
    // TODO: Implement expression table deserialization
    _log.fine('Expression table parsing (stub)');
    return [];
  }

  List<CompactProcessEntry> _parseProcessTable(
    Uint8List data,
    CompactSectionTable section,
    List<String> strings,
  ) {
    // TODO: Implement full process/instruction deserialization with proper offset tracking
    _log.fine('Process table parsing (${section.processCount} entries)');
    return [];
  }

  // ---------------------------------------------------------------------------
  // Decompression
  // ---------------------------------------------------------------------------

  Uint8List _decompress(Uint8List data, CompactCompressionType type) {
    final body = data.sublist(CompactHeader.size);
    try {
      return switch (type) {
        CompactCompressionType.zlib =>
          Uint8List.fromList(zlib.decode(body)),
        CompactCompressionType.lz4 =>
          // TODO: LZ4 decompression requires external package
          throw FlowParseError('LZ4 decompression not yet supported'),
        CompactCompressionType.none => body,
      };
    } catch (e) {
      if (e is FlowParseError) rethrow;
      throw FlowParseError('Decompression failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Reverse mapping helpers (for toFlowDefinition)
  // ---------------------------------------------------------------------------

  StateType _reverseStateType(CompactStateType type) {
    return switch (type) {
      CompactStateType.boolean => StateType.boolean,
      CompactStateType.number => StateType.number,
      CompactStateType.string => StateType.string,
      CompactStateType.object => StateType.object,
      CompactStateType.array => StateType.array,
    };
  }

  Map<String, dynamic> _decodeConfig(Uint8List configData) {
    if (configData.isEmpty) return {};
    try {
      final str = utf8.decode(configData);
      final decoded = jsonDecode(str);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'value': decoded};
    } catch (_) {
      return {};
    }
  }

  TriggerDefinition? _reconstructTrigger(CompactProcessEntry entry) {
    if (entry.triggerData.isEmpty) return null;
    try {
      final json =
          jsonDecode(utf8.decode(entry.triggerData)) as Map<String, dynamic>;
      return TriggerDefinition.fromJson(json);
    } catch (_) {
      // Fallback: return manual trigger
      final type = switch (entry.triggerType) {
        0 => TriggerType.manual,
        1 => TriggerType.schedule,
        2 => TriggerType.event,
        4 => TriggerType.stateChange,
        _ => TriggerType.manual,
      };
      return TriggerDefinition(type: type);
    }
  }

  /// Reconstruct ActionDefinition steps from bytecode instructions.
  List<ActionDefinition> _reconstructSteps(
    List<CompactInstruction> instructions,
    CompactFlowData flow,
  ) {
    // TODO: Full bytecode-to-action reverse mapping
    // This is the inverse of CompactCompiler._compileStep
    final steps = <ActionDefinition>[];
    for (final inst in instructions) {
      final action = _opcodeToAction(inst.opcode);
      if (action != null) {
        steps.add(ActionDefinition(action: action));
      }
    }
    return steps;
  }

  String? _opcodeToAction(int opcode) {
    return switch (opcode) {
      0x01 => 'gpioConfigure',
      0x02 => 'gpioWrite',
      0x03 => 'gpioRead',
      0x04 => 'gpioToggle',
      0x06 => 'pwmConfig',
      0x07 => 'pwmSet',
      0x09 => 'i2cWrite',
      0x0A => 'i2cRead',
      0x0C => 'adcRead',
      0x0E => 'uartWrite',
      0x0F => 'uartRead',
      0x40 => 'stateGet',
      0x41 => 'stateSet',
      0x42 => 'stateUpdate',
      0x60 => 'processStart',
      0x61 => 'processStop',
      0x62 => 'processRestart',
      0x63 => 'processSignal',
      0x65 => 'channelSend',
      0x66 => 'channelReceive',
      0x80 => 'mcpNotify',
      0xA0 => 'wait',
      0xA4 => 'log',
      0xA5 => 'assert',
      0xA7 => 'exit',
      0xA8 => 'systemExec',
      _ => null, // control flow opcodes handled separately
    };
  }
}
