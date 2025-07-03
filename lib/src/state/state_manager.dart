/// State management for MCP Flow Runtime

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:event_bus/event_bus.dart';

import '../types/flow_types.dart';
import '../errors/flow_errors.dart' as errors;
import 'state_store.dart';

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
  dynamic currentValue;

  StateVariableInfo({
    required this.name,
    required this.type,
    this.initial,
    this.persistent = false,
    this.constraints,
  }) : currentValue = initial;
}

/// State manager implementation
class StateManager {
  final Logger _logger = Logger('StateManager');
  final EventBus _eventBus = EventBus();
  final Map<String, StateVariableInfo> _variables = {};
  late final StateStore _store;
  
  StateManager({StateStore? store}) {
    _store = store ?? InMemoryStateStore();
  }

  /// Get event bus for state change notifications
  EventBus get eventBus => _eventBus;

  /// Initialize state manager
  Future<void> initialize() async {
    _logger.info('Initializing state manager');
    await _store.initialize();
    
    // Load persistent state
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
  }) async {
    if (_variables.containsKey(name)) {
      throw errors.StateError('Variable $name already defined', stateVariable: name);
    }

    // Validate initial value
    if (initial != null) {
      _validateValue(name, initial, type, constraints);
    }

    final variable = StateVariableInfo(
      name: name,
      type: type,
      initial: initial,
      persistent: persistent,
      constraints: constraints,
    );

    _variables[name] = variable;
    
    // Store initial value if persistent
    if (persistent && initial != null) {
      await _store.set(name, initial);
    }

    _logger.fine('Defined state variable: $name (type: ${type.name}, persistent: $persistent)');
  }

  /// Get state value
  dynamic get(String name) {
    final variable = _variables[name];
    if (variable == null) {
      throw errors.StateError('Variable $name not defined', stateVariable: name);
    }
    return variable.currentValue;
  }

  /// Set state value
  Future<void> set(String name, dynamic value) async {
    final variable = _variables[name];
    if (variable == null) {
      throw errors.StateError('Variable $name not defined', stateVariable: name);
    }

    // Validate value
    _validateValue(name, value, variable.type, variable.constraints);

    final oldValue = variable.currentValue;
    
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
        throw errors.StateError('Variable ${entry.key} not defined', stateVariable: entry.key);
      }
      _validateValue(entry.key, entry.value, variable.type, variable.constraints);
    }

    // Apply updates
    final events = <StateChangeEvent>[];
    for (final entry in updates.entries) {
      final variable = _variables[entry.key]!;
      final oldValue = variable.currentValue;
      variable.currentValue = entry.value;

      if (variable.persistent) {
        await _store.set(entry.key, entry.value);
      }

      events.add(StateChangeEvent(
        variable: entry.key,
        oldValue: oldValue,
        newValue: entry.value,
      ));
    }

    // Fire all events
    for (final event in events) {
      _eventBus.fire(event);
    }

    _logger.fine('Batch state update: ${updates.keys.join(', ')}');
  }

  /// Check if variable exists
  bool hasVariable(String name) {
    return _variables.containsKey(name);
  }

  /// Get all variable names
  List<String> get variables => _variables.keys.toList();

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

  /// Clear all state
  Future<void> clear() async {
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
    _logger.info('State cleared');
  }

  // Private methods

  void _validateValue(
    String name,
    dynamic value,
    StateType type,
    StateConstraints? constraints,
  ) {
    // Type validation
    switch (type) {
      case StateType.boolean:
        if (value is! bool) {
          throw errors.StateError(
            'Expected boolean value for $name, got ${value.runtimeType}',
            stateVariable: name,
          );
        }
        break;

      case StateType.number:
        if (value is! num) {
          throw errors.StateError(
            'Expected number value for $name, got ${value.runtimeType}',
            stateVariable: name,
          );
        }
        break;

      case StateType.string:
        if (value is! String) {
          throw errors.StateError(
            'Expected string value for $name, got ${value.runtimeType}',
            stateVariable: name,
          );
        }
        break;

      case StateType.object:
        if (value is! Map) {
          throw errors.StateError(
            'Expected object value for $name, got ${value.runtimeType}',
            stateVariable: name,
          );
        }
        // Convert to properly typed map
        if (value is! Map<String, dynamic>) {
          value = Map<String, dynamic>.from(value);
        }
        break;

      case StateType.array:
        if (value is! List) {
          throw errors.StateError(
            'Expected array value for $name, got ${value.runtimeType}',
            stateVariable: name,
          );
        }
        break;
    }

    // Constraint validation
    if (constraints != null) {
      if (type == StateType.number) {
        final numValue = value as num;
        if (constraints.min != null && numValue < constraints.min!) {
          throw errors.StateError(
            'Value $value is below minimum ${constraints.min} for $name',
            stateVariable: name,
          );
        }
        if (constraints.max != null && numValue > constraints.max!) {
          throw errors.StateError(
            'Value $value is above maximum ${constraints.max} for $name',
            stateVariable: name,
          );
        }
      }

      if (type == StateType.string) {
        final strValue = value as String;
        if (constraints.minLength != null && strValue.length < constraints.minLength!) {
          throw errors.StateError(
            'String length ${strValue.length} is below minimum ${constraints.minLength} for $name',
            stateVariable: name,
          );
        }
        if (constraints.maxLength != null && strValue.length > constraints.maxLength!) {
          throw errors.StateError(
            'String length ${strValue.length} is above maximum ${constraints.maxLength} for $name',
            stateVariable: name,
          );
        }
        if (constraints.pattern != null) {
          final regex = RegExp(constraints.pattern!);
          if (!regex.hasMatch(strValue)) {
            throw errors.StateError(
              'Value "$strValue" does not match pattern ${constraints.pattern} for $name',
              stateVariable: name,
            );
          }
        }
      }
      
      if (type == StateType.array) {
        final arrValue = value as List;
        if (constraints.minLength != null && arrValue.length < constraints.minLength!) {
          throw errors.StateError(
            'Array length ${arrValue.length} is below minimum ${constraints.minLength} for $name',
            stateVariable: name,
          );
        }
        if (constraints.maxLength != null && arrValue.length > constraints.maxLength!) {
          throw errors.StateError(
            'Array length ${arrValue.length} is above maximum ${constraints.maxLength} for $name',
            stateVariable: name,
          );
        }
      }

      if (constraints.enum$ != null) {
        if (!constraints.enum$!.contains(value)) {
          throw errors.StateError(
            'Value $value is not in allowed values ${constraints.enum$} for $name',
            stateVariable: name,
          );
        }
      }
    }
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
}