/// CompactExecutor - Executes compact bytecode directly
/// MOD-CORE-010

import 'package:event_bus/event_bus.dart';
import 'package:logging/logging.dart';

import '../errors/flow_errors.dart';
import '../hal/hal_interface.dart';
import '../types/hardware_types.dart';
import '../state/state_manager.dart';
import 'compact_types.dart';

/// Stack-based bytecode executor for [CompactFlowData].
///
/// This is an alternative execution engine to [ProcessExecutor] that
/// interprets compact bytecode directly without JSON parsing overhead.
class CompactExecutor {
  final HardwareAbstractionLayer hal;
  final StateManager stateManager;
  final EventBus eventBus;
  final Logger _log = Logger('CompactExecutor');

  // Per-process execution state
  final Map<int, dynamic> _localVars = {};
  final List<dynamic> _stack = [];
  int _pc = 0;
  bool _halted = false;

  CompactExecutor({
    required this.hal,
    required this.stateManager,
    required this.eventBus,
  });

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Execute a single process from compact flow data.
  Future<dynamic> executeProcess(
    CompactProcessEntry process,
    CompactFlowData flow,
  ) async {
    _localVars.clear();
    _stack.clear();
    _pc = 0;
    _halted = false;

    _log.info('Executing process ${flow.strings[process.nameRef]}');

    // Initialize local variables
    for (final v in process.variables) {
      _localVars[v.id] = null;
    }

    while (!_halted && _pc < process.instructions.length) {
      final inst = process.instructions[_pc];
      _pc++;
      await _dispatch(inst, process, flow);
    }

    final result = _stack.isEmpty ? null : _stack.last;
    _log.fine('Process complete, result: $result');
    return result;
  }

  // ---------------------------------------------------------------------------
  // Opcode dispatch
  // ---------------------------------------------------------------------------

  Future<void> _dispatch(
    CompactInstruction inst,
    CompactProcessEntry process,
    CompactFlowData flow,
  ) async {
    switch (inst.opcode) {
      // Hardware - 0x01-0x1F
      case 0x01:
        await _execGpioConfig(inst, flow);
      case 0x02:
        await _execGpioWrite(inst, flow);
      case 0x03:
        await _execGpioRead(inst, process, flow);
      case 0x04:
        await _execGpioToggle(inst, flow);
      case 0x06:
        await _execPwmConfig(inst, flow);
      case 0x07:
        await _execPwmSet(inst, flow);
      case 0x09:
        await _execI2cWrite(inst, flow);
      case 0x0A:
        await _execI2cRead(inst, process, flow);
      case 0x0C:
        await _execAdcRead(inst, process, flow);
      case 0x0E:
        await _execUartWrite(inst, flow);
      case 0x0F:
        await _execUartRead(inst, process, flow);

      // Control Flow - 0x20-0x3F
      case 0x20:
        _execJump(inst);
      case 0x21:
        _execJumpIfTrue(inst, flow);
      case 0x22:
        _execJumpIfFalse(inst, flow);
      case 0x23:
        _execSwitch(inst, flow);
      case 0x25:
        _execLoopStart(inst, flow);
      case 0x26:
        _execLoopEnd(inst);
      case 0x27:
        _execBreak(inst);
      case 0x28:
        _execContinue(inst);
      case 0x2A:
        await _execCall(inst, flow);
      case 0x2B:
        _execReturn(inst, flow);

      // State Management - 0x40-0x5F
      case 0x40:
        await _execStateGet(inst, process, flow);
      case 0x41:
        await _execStateSet(inst, flow);
      case 0x42:
        await _execStateUpdate(inst, flow);
      case 0x43:
        await _execStateDelete(inst, flow);
      case 0x45:
        await _execArrayGet(inst, process, flow);
      case 0x46:
        await _execArraySet(inst, flow);
      case 0x47:
        await _execArrayAppend(inst, flow);
      case 0x48:
        await _execArrayLength(inst, process, flow);
      case 0x4A:
        await _execObjectGet(inst, process, flow);
      case 0x4B:
        await _execObjectSet(inst, flow);
      case 0x4C:
        await _execObjectDelete(inst, flow);

      // Process Control - 0x60-0x7F
      case 0x60:
        await _execProcessStart(inst, flow);
      case 0x61:
        await _execProcessStop(inst, flow);
      case 0x62:
        await _execProcessRestart(inst, flow);
      case 0x63:
        await _execProcessSignal(inst, flow);
      case 0x65:
        await _execChannelSend(inst, flow);
      case 0x66:
        await _execChannelReceive(inst, process, flow);

      // MCP Integration - 0x80-0x9F
      case 0x80:
        await _execMcpNotify(inst, flow);
      case 0x81:
        await _execMcpToolResponse(inst, flow);
      case 0x82:
        await _execMcpResourceUpdate(inst, flow);

      // System Operations - 0xA0-0xBF
      case 0xA0:
        await _execWait(inst, flow);
      case 0xA1:
        await _execWaitUntil(inst, flow);
      case 0xA4:
        _execLog(inst, flow);
      case 0xA5:
        _execAssert(inst, flow);
      case 0xA7:
        _execExit(inst);
      case 0xA8:
        await _execSystemCommand(inst, process, flow);

      // Extended - 0xFF prefix
      case 0xFF:
        await _execExtended(inst, process, flow);

      default:
        throw ProcessExecutionError(
          'Unknown opcode: 0x${inst.opcode.toRadixString(16)}',
          processId: 'compact',
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Reference resolution
  // ---------------------------------------------------------------------------

  /// Resolve a [CompactReference] to its actual runtime value.
  dynamic _resolveReference(CompactReference ref, CompactFlowData flow) {
    return switch (ref.type) {
      CompactReferenceType.immediate => ref.value,
      CompactReferenceType.state => _resolveStateRef(ref, flow),
      CompactReferenceType.string => flow.strings[ref.id],
      CompactReferenceType.variable => _localVars[ref.id],
      CompactReferenceType.expression =>
        _evaluateExpression(flow.expressions[ref.id], flow),
      CompactReferenceType.resource => flow.resources[ref.id],
      CompactReferenceType.constant => flow.strings[ref.id],
    };
  }

  dynamic _resolveStateRef(CompactReference ref, CompactFlowData flow) {
    final stateEntry = flow.states[ref.id];
    final stateName = flow.strings[stateEntry.nameRef];
    return stateManager.get(stateName);
  }

  // ---------------------------------------------------------------------------
  // Expression evaluation
  // ---------------------------------------------------------------------------

  dynamic _evaluateExpression(CompactExpression expr, CompactFlowData flow) {
    final left = _resolveReference(expr.operands[0], flow);
    final right =
        expr.operands.length > 1 ? _resolveReference(expr.operands[1], flow) : null;

    return switch (expr.type) {
      // ARITHMETIC
      1 => switch (expr.operation) {
          0 => (left as num) + (right as num),   // ADD
          1 => (left as num) - (right as num),   // SUB
          2 => (left as num) * (right as num),   // MUL
          3 => right != 0
              ? (left as num) / (right as num)
              : throw ProcessExecutionError(
                  'Division by zero', processId: 'compact'),  // DIV
          4 => (left as num) % (right as num),   // MOD
          _ => throw ProcessExecutionError(
              'Unknown arithmetic op: ${expr.operation}', processId: 'compact'),
        },
      // COMPARISON
      2 => switch (expr.operation) {
          0 => left == right,           // EQ
          1 => left != right,           // NEQ
          2 => (left as Comparable).compareTo(right) < 0,   // LT
          3 => (left as Comparable).compareTo(right) <= 0,  // LTE
          4 => (left as Comparable).compareTo(right) > 0,   // GT
          5 => (left as Comparable).compareTo(right) >= 0,  // GTE
          _ => throw ProcessExecutionError(
              'Unknown comparison op: ${expr.operation}', processId: 'compact'),
        },
      // LOGICAL
      3 => switch (expr.operation) {
          0 => (left == true) && (right == true),  // AND
          1 => (left == true) || (right == true),  // OR
          2 => !(left == true),                     // NOT
          _ => throw ProcessExecutionError(
              'Unknown logical op: ${expr.operation}', processId: 'compact'),
        },
      // ARRAY_ACCESS
      5 => () {
          final array = left;
          final index = right as int;
          if (array is List) return array[index];
          throw ProcessExecutionError(
              'Array access on non-list value', processId: 'compact');
        }(),
      // REFERENCE (passthrough) or FUNCTION
      _ => left,
    };
  }

  // ---------------------------------------------------------------------------
  // Hardware opcodes (0x01-0x1F)
  // ---------------------------------------------------------------------------

  /// Retrieve the GPIO provider from HAL.
  GpioProvider _getGpioProvider() {
    final provider = hal.getProvider<GpioProvider>(ResourceType.gpio);
    if (provider == null) {
      throw ProcessExecutionError(
        'No GPIO provider registered', processId: 'compact');
    }
    return provider;
  }

  Future<void> _execGpioConfig(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Build GpioConfig from operands and call configurePin
    _log.fine('GPIO config (stub)');
  }

  Future<void> _execGpioWrite(CompactInstruction inst, CompactFlowData flow) async {
    final gpio = _getGpioProvider();
    final pin = _resolveReference(inst.operands[0], flow) as int;
    final value = _resolveReference(inst.operands[1], flow);
    await gpio.writePin(pin, value == true || value == 1);
  }

  Future<void> _execGpioRead(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    final gpio = _getGpioProvider();
    final pin = _resolveReference(inst.operands[0], flow) as int;
    final result = await gpio.readPin(pin);
    _stack.add(result);
    if (inst.operands.length > 1 &&
        inst.operands[1].type == CompactReferenceType.variable) {
      _localVars[inst.operands[1].id] = result;
    }
  }

  Future<void> _execGpioToggle(CompactInstruction inst, CompactFlowData flow) async {
    final gpio = _getGpioProvider();
    final pin = _resolveReference(inst.operands[0], flow) as int;
    final current = await gpio.readPin(pin);
    await gpio.writePin(pin, !current);
  }

  Future<void> _execPwmConfig(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Implement PWM configuration via HAL
    _log.fine('PWM config (stub)');
  }

  Future<void> _execPwmSet(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Implement PWM set via HAL
    _log.fine('PWM set (stub)');
  }

  Future<void> _execI2cWrite(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Implement I2C write via HAL
    _log.fine('I2C write (stub)');
  }

  Future<void> _execI2cRead(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    // TODO: Implement I2C read via HAL
    _log.fine('I2C read (stub)');
  }

  Future<void> _execAdcRead(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    // TODO: Implement ADC read via HAL
    _log.fine('ADC read (stub)');
  }

  Future<void> _execUartWrite(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Implement UART write via HAL
    _log.fine('UART write (stub)');
  }

  Future<void> _execUartRead(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    // TODO: Implement UART read via HAL
    _log.fine('UART read (stub)');
  }

  // ---------------------------------------------------------------------------
  // Control flow opcodes (0x20-0x3F)
  // ---------------------------------------------------------------------------

  void _execJump(CompactInstruction inst) {
    final offset = inst.operands[0].value as int;
    _pc += offset - 1; // -1 because _pc was already incremented
  }

  void _execJumpIfTrue(CompactInstruction inst, CompactFlowData flow) {
    final condition = _resolveReference(inst.operands[0], flow);
    final offset = inst.operands[1].value as int;
    if (condition == true || condition == 1) {
      _pc += offset - 1;
    }
  }

  void _execJumpIfFalse(CompactInstruction inst, CompactFlowData flow) {
    final condition = _resolveReference(inst.operands[0], flow);
    final offset = inst.operands[1].value as int;
    if (condition == false || condition == 0 || condition == null) {
      _pc += offset - 1;
    }
  }

  void _execSwitch(CompactInstruction inst, CompactFlowData flow) {
    // TODO: Implement switch dispatch with case table lookup
    _log.fine('Switch dispatch (stub)');
  }

  void _execLoopStart(CompactInstruction inst, CompactFlowData flow) {
    // Evaluate condition if present; if false, skip to matching LOOP_END
    if (inst.operands.isNotEmpty) {
      final condition = _resolveReference(inst.operands[0], flow);
      if (condition == false || condition == 0 || condition == null) {
        // Scan forward for matching LOOP_END
        _skipToLoopEnd();
      }
    }
    // Push loop start PC onto stack for LOOP_END to jump back
    _stack.add(_pc - 1);
  }

  void _execLoopEnd(CompactInstruction inst) {
    // Pop loop start address and jump back
    if (_stack.isNotEmpty && _stack.last is int) {
      final loopStart = _stack.last as int;
      _pc = loopStart;
    }
  }

  void _execBreak(CompactInstruction inst) {
    // Remove loop start marker from stack and skip to after LOOP_END
    while (_stack.isNotEmpty && _stack.last is! int) {
      _stack.removeLast();
    }
    if (_stack.isNotEmpty) _stack.removeLast(); // remove loop start PC
    _skipToLoopEnd();
  }

  void _execContinue(CompactInstruction inst) {
    // Jump back to loop start
    if (_stack.isNotEmpty && _stack.last is int) {
      _pc = _stack.last as int;
    }
  }

  Future<void> _execCall(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Implement sub-process call with stack frame
    _log.fine('Call (stub)');
  }

  void _execReturn(CompactInstruction inst, CompactFlowData flow) {
    if (inst.operands.isNotEmpty) {
      final value = _resolveReference(inst.operands[0], flow);
      _stack.add(value);
    }
    _halted = true;
  }

  /// Scan forward to find matching LOOP_END opcode.
  void _skipToLoopEnd() {
    // TODO: Handle nested loops by tracking depth
    // For now, simple forward scan
    _log.fine('Scanning for LOOP_END from pc=$_pc');
  }

  // ---------------------------------------------------------------------------
  // State management opcodes (0x40-0x5F)
  // ---------------------------------------------------------------------------

  Future<void> _execStateGet(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    final stateEntry = flow.states[inst.operands[0].id];
    final stateName = flow.strings[stateEntry.nameRef];
    final value = stateManager.get(stateName);
    _stack.add(value);
    if (inst.operands.length > 1 &&
        inst.operands[1].type == CompactReferenceType.variable) {
      _localVars[inst.operands[1].id] = value;
    }
  }

  Future<void> _execStateSet(CompactInstruction inst, CompactFlowData flow) async {
    final stateEntry = flow.states[inst.operands[0].id];
    final stateName = flow.strings[stateEntry.nameRef];
    final value = _resolveReference(inst.operands[1], flow);
    await stateManager.set(stateName, value);
  }

  Future<void> _execStateUpdate(CompactInstruction inst, CompactFlowData flow) async {
    final stateEntry = flow.states[inst.operands[0].id];
    final stateName = flow.strings[stateEntry.nameRef];
    final value = _resolveReference(inst.operands[1], flow);
    await stateManager.set(stateName, value);
  }

  Future<void> _execStateDelete(CompactInstruction inst, CompactFlowData flow) async {
    final stateEntry = flow.states[inst.operands[0].id];
    final stateName = flow.strings[stateEntry.nameRef];
    await stateManager.set(stateName, null);
  }

  Future<void> _execArrayGet(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    final array = _resolveReference(inst.operands[0], flow);
    final index = _resolveReference(inst.operands[1], flow) as int;
    final value = (array is List) ? array[index] : null;
    _stack.add(value);
    if (inst.operands.length > 2 &&
        inst.operands[2].type == CompactReferenceType.variable) {
      _localVars[inst.operands[2].id] = value;
    }
  }

  Future<void> _execArraySet(CompactInstruction inst, CompactFlowData flow) async {
    final array = _resolveReference(inst.operands[0], flow);
    final index = _resolveReference(inst.operands[1], flow) as int;
    final value = _resolveReference(inst.operands[2], flow);
    if (array is List && index < array.length) {
      array[index] = value;
    }
  }

  Future<void> _execArrayAppend(CompactInstruction inst, CompactFlowData flow) async {
    final array = _resolveReference(inst.operands[0], flow);
    final value = _resolveReference(inst.operands[1], flow);
    if (array is List) {
      array.add(value);
    }
  }

  Future<void> _execArrayLength(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    final array = _resolveReference(inst.operands[0], flow);
    final length = (array is List) ? array.length : 0;
    _stack.add(length);
    if (inst.operands.length > 1 &&
        inst.operands[1].type == CompactReferenceType.variable) {
      _localVars[inst.operands[1].id] = length;
    }
  }

  Future<void> _execObjectGet(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    final obj = _resolveReference(inst.operands[0], flow);
    final key = _resolveReference(inst.operands[1], flow) as String;
    final value = (obj is Map) ? obj[key] : null;
    _stack.add(value);
    if (inst.operands.length > 2 &&
        inst.operands[2].type == CompactReferenceType.variable) {
      _localVars[inst.operands[2].id] = value;
    }
  }

  Future<void> _execObjectSet(CompactInstruction inst, CompactFlowData flow) async {
    final obj = _resolveReference(inst.operands[0], flow);
    final key = _resolveReference(inst.operands[1], flow) as String;
    final value = _resolveReference(inst.operands[2], flow);
    if (obj is Map) {
      obj[key] = value;
    }
  }

  Future<void> _execObjectDelete(CompactInstruction inst, CompactFlowData flow) async {
    final obj = _resolveReference(inst.operands[0], flow);
    final key = _resolveReference(inst.operands[1], flow) as String;
    if (obj is Map) {
      obj.remove(key);
    }
  }

  // ---------------------------------------------------------------------------
  // Process control opcodes (0x60-0x7F)
  // ---------------------------------------------------------------------------

  Future<void> _execProcessStart(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Delegate to runtime process manager
    _log.fine('Process start (stub)');
  }

  Future<void> _execProcessStop(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Delegate to runtime process manager
    _log.fine('Process stop (stub)');
  }

  Future<void> _execProcessRestart(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Delegate to runtime process manager
    _log.fine('Process restart (stub)');
  }

  Future<void> _execProcessSignal(CompactInstruction inst, CompactFlowData flow) async {
    final signal = _resolveReference(inst.operands[0], flow);
    eventBus.fire(signal);
  }

  Future<void> _execChannelSend(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Implement channel send via runtime channel manager
    _log.fine('Channel send (stub)');
  }

  Future<void> _execChannelReceive(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    // TODO: Implement channel receive via runtime channel manager
    _log.fine('Channel receive (stub)');
  }

  // ---------------------------------------------------------------------------
  // MCP integration opcodes (0x80-0x9F)
  // ---------------------------------------------------------------------------

  Future<void> _execMcpNotify(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Delegate to MCP notification system
    _log.fine('MCP notify (stub)');
  }

  Future<void> _execMcpToolResponse(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Delegate to MCP tool response handler
    _log.fine('MCP tool response (stub)');
  }

  Future<void> _execMcpResourceUpdate(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Delegate to MCP resource update handler
    _log.fine('MCP resource update (stub)');
  }

  // ---------------------------------------------------------------------------
  // System opcodes (0xA0-0xBF)
  // ---------------------------------------------------------------------------

  Future<void> _execWait(CompactInstruction inst, CompactFlowData flow) async {
    final ms = _resolveReference(inst.operands[0], flow) as int;
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  Future<void> _execWaitUntil(CompactInstruction inst, CompactFlowData flow) async {
    // TODO: Implement wait-until with condition polling
    _log.fine('Wait until (stub)');
  }

  void _execLog(CompactInstruction inst, CompactFlowData flow) {
    final message = _resolveReference(inst.operands[0], flow);
    _log.info('[Flow Log] $message');
  }

  void _execAssert(CompactInstruction inst, CompactFlowData flow) {
    final condition = _resolveReference(inst.operands[0], flow);
    if (condition == false || condition == 0 || condition == null) {
      final message = inst.operands.length > 1
          ? _resolveReference(inst.operands[1], flow)?.toString()
          : 'Assertion failed';
      throw ProcessExecutionError(
        message ?? 'Assertion failed',
        processId: 'compact',
      );
    }
  }

  void _execExit(CompactInstruction inst) {
    _halted = true;
  }

  Future<void> _execSystemCommand(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    // TODO: Implement system command execution with security checks
    _log.fine('System command (stub)');
  }

  // ---------------------------------------------------------------------------
  // Extended opcodes (0xFF prefix)
  // ---------------------------------------------------------------------------

  Future<void> _execExtended(
      CompactInstruction inst, CompactProcessEntry process, CompactFlowData flow) async {
    final extCode = inst.extendedOpcode;
    _log.fine('Extended opcode: $extCode (stub)');
    // TODO: Implement extended opcode dispatch for future expansion
  }
}
