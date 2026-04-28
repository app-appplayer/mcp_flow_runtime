/// State management for MCP Flow Runtime

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:event_bus/event_bus.dart';
import 'package:expressions/expressions.dart';

import '../types/flow_types.dart';
import '../errors/flow_errors.dart' as errors;
import 'state_store.dart';
import '../expression/expression_evaluator.dart';

/// State change event
class StateChangeEvent {
  final String variable;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime timestamp;

  StateChangeEvent({
    required this.variable,
    this.oldValue,
    required this.newValue,
  }) : timestamp = DateTime.now();
}

/// State variable metadata
class StateVariableInfo {
  final String name;
  final StateType type;
  final dynamic initial;
  final bool persistent;
  final StateConstraints? constraints;
  final StateSecurityConfig? security;
  dynamic currentValue;

  StateVariableInfo({
    required this.name,
    required this.type,
    this.initial,
    this.persistent = false,
    this.constraints,
    this.security,
  }) : currentValue = initial;
}

/// State manager implementation
class StateManager {
  final Logger _logger = Logger('StateManager');
  final EventBus _eventBus = EventBus();
  final Map<String, StateVariableInfo> _variables = {};
  late final StateStore _store;
  
  // Persistence configuration
  // ignore: unused_field
  String? _statePath;
  // ignore: unused_field
  Timer? _saveTimer;
  // ignore: unused_field
  bool _persistenceEnabled = false;
  
  StateManager({StateStore? store}) {
    _store = store ?? InMemoryStateStore();
  }

  /// Get event bus for state change notifications
  EventBus get eventBus => _eventBus;
  
  /// Get the underlying state store
  StateStore get store => _store;

  /// Initialize state manager
  Future<void> initialize() async {
    _logger.info('Initializing state manager');
    await _store.initialize();
    
    // Load persistent state if variables are already defined
    if (_variables.isNotEmpty) {
      await loadPersistentValues();
    }
  }
  
  /// Load persistent values for all variables
  Future<void> loadPersistentValues() async {
    for (final variable in _variables.values) {
      if (variable.persistent) {
        final value = await _store.get(variable.name);
        if (value != null) {
          variable.currentValue = value;
          _logger.fine('Loaded persistent state: ${variable.name} = $value');
        }
      }
    }
  }

  /// Dispose state manager
  Future<void> dispose() async {
    _logger.info('Disposing state manager');
    await _store.dispose();
  }

  /// Define a state variable
  Future<void> defineVariable(
    String name, {
    required StateType type,
    dynamic initial,
    bool persistent = false,
    StateConstraints? constraints,
    StateSecurityConfig? security,
  }) async {
    if (_variables.containsKey(name)) {
      throw errors.FlowStateError('Variable $name already defined', variableName: name);
    }

    // Set default initial value if not provided
    if (initial == null) {
      switch (type) {
        case StateType.boolean:
          initial = false;
          break;
        case StateType.number:
          initial = 0;
          break;
        case StateType.string:
          initial = '';
          break;
        case StateType.array:
          initial = [];
          break;
        case StateType.object:
          initial = {};
          break;
        case StateType.any:
          // any type defaults to null
          break;
      }
    }

    // Validate initial value
    if (initial != null) {
      initial = _validateValue(name, initial, type, constraints, initial);
    }

    final variable = StateVariableInfo(
      name: name,
      type: type,
      initial: initial,
      persistent: persistent,
      constraints: constraints,
      security: security,
    );

    _variables[name] = variable;
    
    // Store initial value if persistent and no value exists
    if (persistent && initial != null) {
      final existingValue = await _store.get(name);
      if (existingValue == null) {
        await _store.set(name, initial);
      }
    }

    _logger.fine('Defined state variable: $name (type: ${type.name}, persistent: $persistent)');
  }

  /// Get state value
  dynamic get(String name) {
    final variable = _variables[name];
    if (variable == null) {
      throw errors.FlowStateError('Variable $name not defined', variableName: name);
    }
    return variable.currentValue;
  }

  /// Set state value
  Future<void> set(String name, dynamic value) async {
    final variable = _variables[name];
    if (variable == null) {
      throw errors.FlowStateError('Variable $name not defined', variableName: name);
    }

    final oldValue = variable.currentValue;
    
    // Validate value
    value = _validateValue(name, value, variable.type, variable.constraints, oldValue);
    
    // Check if value actually changed
    if (_areEqual(oldValue, value)) {
      return; // No change, don't fire event
    }
    
    variable.currentValue = value;

    // Store if persistent
    if (variable.persistent) {
      await _store.set(name, value);
    }

    // Fire change event
    _eventBus.fire(StateChangeEvent(
      variable: name,
      oldValue: oldValue,
      newValue: value,
    ));

    _logger.fine('State updated: $name = $value');
  }

  /// Update multiple values atomically
  Future<void> update(Map<String, dynamic> updates) async {
    // Validate all updates first
    for (final entry in updates.entries) {
      final variable = _variables[entry.key];
      if (variable == null) {
        throw errors.FlowStateError('Variable ${entry.key} not defined', variableName: entry.key);
      }
      updates[entry.key] = _validateValue(entry.key, entry.value, variable.type, variable.constraints, variable.currentValue);
    }

    // Apply updates with rollback on store failure
    final events = <StateChangeEvent>[];
    final previousValues = <String, dynamic>{};

    try {
      for (final entry in updates.entries) {
        final variable = _variables[entry.key]!;
        final oldValue = variable.currentValue;
        previousValues[entry.key] = oldValue;
        variable.currentValue = entry.value;

        if (variable.persistent) {
          await _store.set(entry.key, entry.value);
        }

        // Only fire event if value actually changed
        if (!_areEqual(oldValue, entry.value)) {
          events.add(StateChangeEvent(
            variable: entry.key,
            oldValue: oldValue,
            newValue: entry.value,
          ));
        }
      }
    } catch (e) {
      // Rollback all applied changes to previous values
      for (final rollbackEntry in previousValues.entries) {
        final variable = _variables[rollbackEntry.key];
        if (variable != null) {
          variable.currentValue = rollbackEntry.value;
          if (variable.persistent) {
            try {
              await _store.set(rollbackEntry.key, rollbackEntry.value);
            } catch (_) {
              // Best-effort rollback for store
            }
          }
        }
      }
      rethrow;
    }

    // Fire all events after successful persistence
    for (final event in events) {
      _eventBus.fire(event);
    }

    _logger.fine('Batch state update: ${updates.keys.join(', ')}');
  }

  /// Check if variable exists
  bool hasVariable(String name) {
    return _variables.containsKey(name);
  }

  /// Get all variable definitions
  Map<String, StateVariableInfo> get variables => Map.unmodifiable(_variables);

  /// Get variable info
  StateVariableInfo? getVariableInfo(String name) {
    return _variables[name];
  }

  /// Get all state as map
  Map<String, dynamic> toMap() {
    return Map.fromEntries(
      _variables.entries.map((e) => MapEntry(e.key, e.value.currentValue)),
    );
  }
  
  /// Get all state variables (alias for toMap for MCP integration)
  Map<String, dynamic> getAll() => toMap();

  /// Clear all state
  Future<void> clear() async {
    // Collect defined variable names for orphan detection
    final definedNames = _variables.keys.toSet();

    for (final variable in _variables.values) {
      variable.currentValue = variable.initial;
      if (variable.persistent) {
        if (variable.initial != null) {
          await _store.set(variable.name, variable.initial);
        } else {
          await _store.remove(variable.name);
        }
      }
    }

    // Remove any orphaned keys in the store that are not in variable definitions
    final allStored = await _store.loadAll();
    for (final key in allStored.keys) {
      if (!definedNames.contains(key)) {
        await _store.remove(key);
      }
    }

    _logger.info('State cleared');
  }

  // Private methods

  dynamic _validateValue(
    String name,
    dynamic value,
    StateType type,
    StateConstraints? constraints,
    dynamic existingValue,
  ) {
    // Handle null values - use initial value or default
    if (value == null) {
      // For null values, use the initial value if available
      final variable = _variables[name];
      if (variable != null && variable.initial != null) {
        value = variable.initial;
      } else {
        // Use type-appropriate defaults
        switch (type) {
          case StateType.boolean:
            value = false;
            break;
          case StateType.number:
            value = 0;
            break;
          case StateType.string:
            value = '';
            break;
          case StateType.object:
            value = <String, dynamic>{};
            break;
          case StateType.array:
            value = [];
            break;
          case StateType.any:
            // null is valid for 'any' type
            break;
        }
      }
    }
    
    // Type validation
    switch (type) {
      case StateType.boolean:
        if (value != null && value is! bool) {
          throw errors.FlowStateError(
            'Expected boolean value for $name, got ${value.runtimeType}',
            variableName: name,
          );
        }
        break;

      case StateType.number:
        if (value != null && value is! num) {
          throw errors.FlowStateError(
            'Expected number value for $name, got ${value.runtimeType}',
            variableName: name,
          );
        }
        break;

      case StateType.string:
        if (value != null && value is! String) {
          throw errors.FlowStateError(
            'Expected string value for $name, got ${value.runtimeType}',
            variableName: name,
          );
        }
        break;

      case StateType.object:
        if (value is! Map) {
          throw errors.FlowStateError(
            'Expected object value for $name, got ${value.runtimeType}',
            variableName: name,
          );
        }
        // Convert to properly typed map
        if (value is! Map<String, dynamic>) {
          value = Map<String, dynamic>.from(value);
        }
        break;

      case StateType.array:
        if (value is! List) {
          // Try to convert Map.values to List for array types
          if (value is Map) {
            value = value.values.toList();
          } else {
            throw errors.FlowStateError(
              'Expected array value for $name, got ${value.runtimeType}',
              variableName: name,
            );
          }
        }
        break;
        
      case StateType.any:
        // Any type accepts all values
        break;
    }

    // Constraint validation and clamping
    if (constraints != null) {
      if (type == StateType.number) {
        var numValue = value as num;
        // Clamp numeric values to min/max constraints
        if (constraints.min != null && numValue < constraints.min!) {
          _logger.warning('Clamping value $numValue to minimum ${constraints.min} for $name');
          value = constraints.min!;
        }
        if (constraints.max != null && numValue > constraints.max!) {
          _logger.warning('Clamping value $numValue to maximum ${constraints.max} for $name');
          value = constraints.max!;
        }
      }

      if (type == StateType.string) {
        var strValue = value as String;
        if (constraints.minLength != null && strValue.length < constraints.minLength!) {
          throw errors.FlowStateError(
            'String length ${strValue.length} is below minimum ${constraints.minLength} for $name',
            variableName: name,
          );
        }
        if (constraints.maxLength != null && strValue.length > constraints.maxLength!) {
          throw errors.FlowStateError(
            'String length ${strValue.length} exceeds maximum ${constraints.maxLength} for $name',
            variableName: name,
          );
        }
        if (constraints.pattern != null) {
          final regex = RegExp(constraints.pattern!);
          if (!regex.hasMatch(strValue)) {
            throw errors.FlowStateError(
              'Value "$strValue" does not match pattern ${constraints.pattern} for $name',
              variableName: name,
            );
          }
        }
      }

      if (type == StateType.array) {
        var arrValue = value as List;
        if (constraints.minItems != null && arrValue.length < constraints.minItems!) {
          throw errors.FlowStateError(
            'Array length ${arrValue.length} is below minimum ${constraints.minItems} for $name',
            variableName: name,
          );
        }
        if (constraints.maxItems != null && arrValue.length > constraints.maxItems!) {
          throw errors.FlowStateError(
            'Array length ${arrValue.length} exceeds maximum ${constraints.maxItems} for $name',
            variableName: name,
          );
        }
      }
      
      // Enum constraint validation (applies to any type)
      if (constraints.enum$ != null && constraints.enum$!.isNotEmpty) {
        if (!constraints.enum$!.contains(value)) {
          throw errors.FlowStateError(
            'Value "$value" is not in allowed enum values ${constraints.enum$} for $name',
            variableName: name,
          );
        }
      }
      
      // Custom validation expression
      if (constraints.validate != null) {
        try {
          // Create evaluation context with the value
          final context = <String, dynamic>{
            'value': value,
          };
          
          // Parse and evaluate the validation expression  
          final expr = Expression.parse(constraints.validate!);
          final evaluator = FlowExpressionEvaluator();
          final result = evaluator.eval(expr, context);
          
          // Check if validation passed (truthy result)
          final isValid = result == true || 
                          (result is num && result != 0) ||
                          (result is String && result.isNotEmpty);
          
          if (!isValid) {
            throw errors.FlowStateError(
              'Custom validation failed for $name: ${constraints.validate}',
              variableName: name,
            );
          }
        } catch (e) {
          if (e is errors.FlowStateError) {
            rethrow;
          }
          // If validation expression itself fails, log and continue
          _logger.warning('Failed to evaluate custom validation for $name: $e');
        }
      }
      
    }
    
    return value;
  }
  
  /// Check if two values are equal
  bool _areEqual(dynamic a, dynamic b) {
    if (a == b) return true;
    
    // Deep equality for collections
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_areEqual(a[i], b[i])) return false;
      }
      return true;
    }
    
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_areEqual(a[key], b[key])) return false;
      }
      return true;
    }
    
    return false;
  }

  /// Get all current state variables and their values
  Map<String, dynamic> getAllStates() {
    final result = <String, dynamic>{};
    for (final entry in _variables.entries) {
      result[entry.key] = entry.value.currentValue;
    }
    return result;
  }

  /// Delete a state variable
  Future<void> deleteState(String name) async {
    if (_variables.containsKey(name)) {
      final variable = _variables[name]!;

      // Remove from persistent storage if it was persistent
      if (variable.persistent) {
        await _store.remove(name);
      }

      // Remove from memory
      _variables.remove(name);

      _logger.fine('Deleted state variable: $name');
    }
  }

  /// Get state variable metadata
  StateVariableInfo? getStateInfo(String name) {
    return _variables[name];
  }

  /// Get all state variable names
  List<String> getStateNames() {
    return _variables.keys.toList();
  }

  /// Check if a state variable exists
  bool hasState(String name) {
    return _variables.containsKey(name);
  }

  /// Clear all non-persistent state variables
  Future<void> clearNonPersistentStates() async {
    for (final variable in _variables.values) {
      if (!variable.persistent) {
        final oldValue = variable.currentValue;
        if (oldValue != variable.initial) {
          variable.currentValue = variable.initial;
          _eventBus.fire(StateChangeEvent(
            variable: variable.name,
            oldValue: oldValue,
            newValue: variable.initial,
          ));
        }
      }
    }
    _logger.info('Reset non-persistent state variables');
  }
  
  /// Clear all variable definitions (for flow reload)
  void clearVariableDefinitions() {
    _variables.clear();
    _logger.info('Cleared all variable definitions');
  }
  
  /// Reset non-persistent variables to initial values
  Future<void> resetNonPersistent() async {
    for (final variable in _variables.values) {
      if (!variable.persistent) {
        final oldValue = variable.currentValue;
        variable.currentValue = variable.initial;

        // Only fire event if value actually changed
        if (!_areEqual(oldValue, variable.initial)) {
          _eventBus.fire(StateChangeEvent(
            variable: variable.name,
            oldValue: oldValue,
            newValue: variable.initial,
          ));
        }
      }
    }
    _logger.info('Reset non-persistent state variables to initial values');
  }

  /// Get memory usage of state manager
  int getMemoryUsage() {
    // Rough estimation of memory usage
    int totalSize = 0;
    for (final variable in _variables.values) {
      totalSize += _estimateSize(variable.currentValue);
    }
    return totalSize;
  }

  int _estimateSize(dynamic value) {
    if (value == null) return 4;
    if (value is bool) return 1;
    if (value is int) return 8;
    if (value is double) return 8;
    if (value is String) return value.length * 2; // UTF-16
    if (value is List) {
      return value.fold(16, (sum, item) => sum + _estimateSize(item));
    }
    if (value is Map) {
      return value.entries.fold(16, (sum, entry) => 
        sum + _estimateSize(entry.key) + _estimateSize(entry.value));
    }
    return 16; // Default object overhead
  }
}