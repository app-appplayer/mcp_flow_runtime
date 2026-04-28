/// Compact Binary Format shared types for MCP Flow Runtime
/// MOD-CORE-008/009/010

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Compression type used in compact binary format
enum CompactCompressionType {
  none,   // 0x00 - raw compact format
  lz4,    // 0x01 - LZ4 fast compression
  zlib,   // 0x02 - ZLIB higher ratio
}

/// Reference type for operand encoding
enum CompactReferenceType {
  immediate,   // 0x00 - direct inline value
  state,       // 0x01 - state variable by ID
  resource,    // 0x02 - hardware resource by ID
  string,      // 0x03 - string table index
  variable,    // 0x04 - local (process-scoped) variable
  expression,  // 0x05 - compiled expression table entry
  constant,    // 0x06 - constant table entry
}

/// Compact state type encoding
enum CompactStateType {
  boolean,  // 0x01
  number,   // 0x02
  string,   // 0x03
  object,   // 0x04
  array,    // 0x05
}

/// Compact resource type encoding
enum CompactResourceType {
  gpio,    // 0x01
  i2c,     // 0x02
  pwm,     // 0x03
  adc,     // 0x04
  uart,    // 0x05
  modbus,  // 0x06
  spi,     // 0x07
  mqtt,    // 0x08
}

/// Opcode definitions for compact bytecode
enum CompactOpcode {
  // Hardware - 0x01-0x1F
  gpioConfig(0x01),
  gpioWrite(0x02),
  gpioRead(0x03),
  gpioToggle(0x04),
  pwmConfig(0x06),
  pwmSet(0x07),
  i2cWrite(0x09),
  i2cRead(0x0A),
  adcRead(0x0C),
  uartWrite(0x0E),
  uartRead(0x0F),

  // Control Flow - 0x20-0x3F
  jump(0x20),
  jumpIfTrue(0x21),
  jumpIfFalse(0x22),
  switchOp(0x23),
  loopStart(0x25),
  loopEnd(0x26),
  breakOp(0x27),
  continueOp(0x28),
  call(0x2A),
  returnOp(0x2B),

  // State Management - 0x40-0x5F
  stateGet(0x40),
  stateSet(0x41),
  stateUpdate(0x42),
  stateDelete(0x43),
  arrayGet(0x45),
  arraySet(0x46),
  arrayAppend(0x47),
  arrayLength(0x48),
  objectGet(0x4A),
  objectSet(0x4B),
  objectDelete(0x4C),

  // Process Control - 0x60-0x7F
  processStart(0x60),
  processStop(0x61),
  processRestart(0x62),
  processSignal(0x63),
  channelSend(0x65),
  channelReceive(0x66),

  // MCP Integration - 0x80-0x9F
  mcpNotify(0x80),
  mcpToolResponse(0x81),
  mcpResourceUpdate(0x82),

  // System Operations - 0xA0-0xBF
  wait(0xA0),
  waitUntil(0xA1),
  log(0xA4),
  assertOp(0xA5),
  exit(0xA7),
  systemExec(0xA8),

  // Extended - 0xFF prefix
  extended(0xFF);

  final int code;
  const CompactOpcode(this.code);

  /// Lookup opcode by numeric code
  static CompactOpcode? fromCode(int code) {
    for (final op in values) {
      if (op.code == code) return op;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A typed reference to a value (operand)
class CompactReference {
  final CompactReferenceType type;
  final int id;         // table index; ignored for immediate
  final dynamic value;  // inline value when type == immediate
  final int flags;      // optional modifier bits (default 0)

  const CompactReference({
    required this.type,
    this.id = 0,
    this.value,
    this.flags = 0,
  });

  @override
  String toString() => 'CompactReference($type, id=$id, value=$value)';
}

/// State entry in the compact state table
class CompactStateEntry {
  final int id;                  // 2-byte state ID
  final int nameRef;             // string table index
  final CompactStateType type;
  final int flags;               // PERSISTENT=0x01, SECURE=0x02, READONLY=0x04
  final dynamic initialValue;    // decoded initial value

  const CompactStateEntry({
    required this.id,
    required this.nameRef,
    required this.type,
    this.flags = 0,
    this.initialValue,
  });

  bool get isPersistent => (flags & 0x01) != 0;
  bool get isSecure => (flags & 0x02) != 0;
  bool get isReadOnly => (flags & 0x04) != 0;
}

/// MCP binding metadata for resources and processes
class CompactMcpBinding {
  final bool expose;
  final int? toolNameRef;       // string table index
  final int? descriptionRef;
  final int? schemaRef;
  final int? uriRef;
  final int? mimeTypeRef;

  const CompactMcpBinding({
    this.expose = false,
    this.toolNameRef,
    this.descriptionRef,
    this.schemaRef,
    this.uriRef,
    this.mimeTypeRef,
  });
}

/// Resource entry in the compact resource table
class CompactResourceEntry {
  final int id;
  final int nameRef;
  final CompactResourceType type;
  final Uint8List configData;         // raw encoded config bytes
  final CompactMcpBinding? mcpBinding;

  const CompactResourceEntry({
    required this.id,
    required this.nameRef,
    required this.type,
    required this.configData,
    this.mcpBinding,
  });
}

/// Compiled expression entry
class CompactExpression {
  final int id;
  final int type;        // REFERENCE=0, ARITHMETIC=1, COMPARISON=2, LOGICAL=3, FUNCTION=4, ARRAY_ACCESS=5
  final int operation;   // operation code within type (ADD, GT, AND, etc.)
  final List<CompactReference> operands;

  const CompactExpression({
    required this.id,
    required this.type,
    required this.operation,
    required this.operands,
  });
}

/// Single bytecode instruction
class CompactInstruction {
  final int opcode;               // 1-byte opcode (0x01-0xFF)
  final List<CompactReference> operands;
  final int? extendedOpcode;     // present when opcode == 0xFF

  const CompactInstruction({
    required this.opcode,
    this.operands = const [],
    this.extendedOpcode,
  });

  @override
  String toString() =>
      'CompactInstruction(0x${opcode.toRadixString(16)}, operands=${operands.length})';
}

/// Process-scoped local variable
class CompactLocalVariable {
  final int id;           // process-scoped variable ID
  final String name;      // original bindTo name (for debug)
  final CompactStateType type;

  const CompactLocalVariable({
    required this.id,
    required this.name,
    required this.type,
  });
}

/// Process entry containing bytecode
class CompactProcessEntry {
  final int id;
  final int nameRef;
  final int triggerType;          // MANUAL=0, SCHEDULE=1, EVENT=2, CRON=3, STATE_CHANGE=4
  final Uint8List triggerData;    // encoded trigger parameters
  final List<CompactInstruction> instructions;
  final List<CompactLocalVariable> variables; // bindTo allocations
  final CompactMcpBinding? mcpBinding;

  const CompactProcessEntry({
    required this.id,
    required this.nameRef,
    required this.triggerType,
    required this.triggerData,
    required this.instructions,
    this.variables = const [],
    this.mcpBinding,
  });
}

/// 16-byte binary file header
class CompactHeader {
  static const int magicNumber = 0x46434D50; // 'FCMP'
  static const int size = 16;                // bytes

  final int version;          // 2 bytes: Major(high) + Minor(low)
  final int flags;            // 2 bytes: compression in low 4 bits
  final int originalHash;     // 4 bytes: first 4 bytes of SHA-256 of source JSON
  final int totalSize;        // 4 bytes: total compact data size

  const CompactHeader({
    required this.version,
    required this.flags,
    required this.originalHash,
    required this.totalSize,
  });

  CompactCompressionType get compression =>
      CompactCompressionType.values[flags & 0x0F];
}

/// Section table describing offsets and counts
class CompactSectionTable {
  /// 6 count fields x 2 bytes + 2 offset fields x 4 bytes = 20 bytes
  static const int size = 20;

  final int stringCount;
  final int stateCount;
  final int resourceCount;
  final int processCount;
  final int eventCount;
  final int instructionCount;
  final int stringTableOffset;   // byte offset from file start
  final int dataSectionOffset;   // byte offset from file start

  const CompactSectionTable({
    required this.stringCount,
    required this.stateCount,
    required this.resourceCount,
    required this.processCount,
    required this.eventCount,
    required this.instructionCount,
    required this.stringTableOffset,
    required this.dataSectionOffset,
  });
}

/// Top-level deserialized compact flow data
class CompactFlowData {
  final CompactHeader header;
  final CompactSectionTable sectionTable;
  final List<String> strings;                    // decoded string table
  final List<CompactStateEntry> states;
  final List<CompactResourceEntry> resources;
  final List<CompactExpression> expressions;
  final List<CompactProcessEntry> processes;
  final CompactCompressionType compression;

  const CompactFlowData({
    required this.header,
    required this.sectionTable,
    required this.strings,
    required this.states,
    required this.resources,
    required this.expressions,
    required this.processes,
    required this.compression,
  });
}
