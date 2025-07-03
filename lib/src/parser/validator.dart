/// Flow definition validator

import '../types/flow_types.dart';

/// Validation error details
class ValidationError {
  final String field;
  final String message;
  final dynamic value;

  ValidationError({
    required this.field,
    required this.message,
    this.value,
  });

  @override
  String toString() => '$field: $message';
}

/// Flow validator
class FlowValidator {
  /// Validate flow definition
  List<ValidationError> validate(FlowDefinition flow) {
    final errors = <ValidationError>[];

    // Validate version
    if (flow.version.isEmpty) {
      errors.add(ValidationError(
        field: 'version',
        message: 'Version is required',
      ));
    }

    // Validate processes
    if (flow.processes.isEmpty) {
      errors.add(ValidationError(
        field: 'processes',
        message: 'At least one process is required',
      ));
    }

    // Validate each process
    for (int i = 0; i < flow.processes.length; i++) {
      errors.addAll(_validateProcess(flow.processes[i], 'processes[$i]'));
    }

    // Validate resources
    flow.resources.forEach((name, resource) {
      errors.addAll(_validateResource(resource, 'resources.$name'));
    });

    // Validate state
    flow.state.forEach((name, state) {
      errors.addAll(_validateState(state, 'state.$name'));
    });

    // Validate channels
    flow.channels?.forEach((name, channel) {
      errors.addAll(_validateChannel(channel, 'channels.$name'));
    });

    // Validate events
    if (flow.events != null) {
      for (int i = 0; i < flow.events!.length; i++) {
        errors.addAll(_validateEvent(flow.events![i], 'events[$i]'));
      }
    }

    // Cross-validation
    errors.addAll(_crossValidate(flow));

    return errors;
  }

  List<ValidationError> _validateProcess(ProcessDefinition process, String path) {
    final errors = <ValidationError>[];

    // Validate ID
    if (process.id.isEmpty) {
      errors.add(ValidationError(
        field: '$path.id',
        message: 'Process ID is required',
      ));
    }

    // Validate steps
    if (process.steps.isEmpty) {
      errors.add(ValidationError(
        field: '$path.steps',
        message: 'Process must have at least one step',
      ));
    }

    // Validate each step
    for (int i = 0; i < process.steps.length; i++) {
      errors.addAll(_validateAction(process.steps[i], '$path.steps[$i]'));
    }

    // Validate trigger
    if (process.trigger != null) {
      errors.addAll(_validateTrigger(process.trigger!, '$path.trigger'));
    }

    // Validate error handlers
    if (process.error != null) {
      for (int i = 0; i < process.error!.length; i++) {
        errors.addAll(_validateAction(process.error![i], '$path.error[$i]'));
      }
    }

    // Validate finally handlers
    if (process.finally$ != null) {
      for (int i = 0; i < process.finally$!.length; i++) {
        errors.addAll(_validateAction(process.finally$![i], '$path.finally[$i]'));
      }
    }

    return errors;
  }

  List<ValidationError> _validateAction(ActionDefinition action, String path) {
    final errors = <ValidationError>[];

    // Validate action type
    if (action.action.isEmpty) {
      errors.add(ValidationError(
        field: '$path.action',
        message: 'Action type is required',
      ));
    }

    // Validate control flow actions
    switch (action.action) {
      case 'if':
        if (action.params?['condition'] == null) {
          errors.add(ValidationError(
            field: '$path.params.condition',
            message: 'If action requires condition parameter',
          ));
        }
        if (action.then == null && action.else$ == null) {
          errors.add(ValidationError(
            field: '$path',
            message: 'If action requires then or else branch',
          ));
        }
        break;

      case 'while':
      case 'for':
        if (action.do$ == null || action.do$!.isEmpty) {
          errors.add(ValidationError(
            field: '$path.do',
            message: '${action.action} action requires do block',
          ));
        }
        break;

      case 'switch':
        if (action.value == null) {
          errors.add(ValidationError(
            field: '$path.value',
            message: 'Switch action requires value',
          ));
        }
        if (action.cases == null || action.cases!.isEmpty) {
          errors.add(ValidationError(
            field: '$path.cases',
            message: 'Switch action requires cases',
          ));
        }
        break;

      case 'parallel':
        if (action.branches == null || action.branches!.isEmpty) {
          errors.add(ValidationError(
            field: '$path.branches',
            message: 'Parallel action requires branches',
          ));
        }
        break;
    }

    // Validate sub-actions
    if (action.then != null) {
      for (int i = 0; i < action.then!.length; i++) {
        errors.addAll(_validateAction(action.then![i], '$path.then[$i]'));
      }
    }
    if (action.else$ != null) {
      for (int i = 0; i < action.else$!.length; i++) {
        errors.addAll(_validateAction(action.else$![i], '$path.else[$i]'));
      }
    }
    if (action.do$ != null) {
      for (int i = 0; i < action.do$!.length; i++) {
        errors.addAll(_validateAction(action.do$![i], '$path.do[$i]'));
      }
    }
    if (action.branches != null) {
      for (int i = 0; i < action.branches!.length; i++) {
        final branch = action.branches![i];
        for (int j = 0; j < branch.steps.length; j++) {
          errors.addAll(_validateAction(branch.steps[j], '$path.branches[$i].steps[$j]'));
        }
      }
    }

    // Validate retry configuration
    if (action.retry != null) {
      if (action.retry!.count < 0) {
        errors.add(ValidationError(
          field: '$path.retry.count',
          message: 'Retry count must be non-negative',
          value: action.retry!.count,
        ));
      }
      if (action.retry!.delayMs < 0) {
        errors.add(ValidationError(
          field: '$path.retry.delayMs',
          message: 'Retry delay must be non-negative',
          value: action.retry!.delayMs,
        ));
      }
    }

    return errors;
  }

  List<ValidationError> _validateTrigger(TriggerDefinition trigger, String path) {
    final errors = <ValidationError>[];

    switch (trigger.type) {
      case TriggerType.event:
        if (trigger.event == null || trigger.event!.isEmpty) {
          errors.add(ValidationError(
            field: '$path.event',
            message: 'Event trigger requires event name',
          ));
        }
        break;

      case TriggerType.condition:
        if (trigger.condition == null || trigger.condition!.isEmpty) {
          errors.add(ValidationError(
            field: '$path.condition',
            message: 'Condition trigger requires condition expression',
          ));
        }
        break;

      case TriggerType.schedule:
        if (trigger.interval == null && trigger.cron == null) {
          errors.add(ValidationError(
            field: '$path',
            message: 'Schedule trigger requires interval or cron',
          ));
        }
        if (trigger.interval != null && trigger.interval! <= 0) {
          errors.add(ValidationError(
            field: '$path.interval',
            message: 'Schedule interval must be positive',
            value: trigger.interval,
          ));
        }
        break;

      default:
        // Manual and startup triggers don't need validation
        break;
    }

    return errors;
  }

  List<ValidationError> _validateResource(ResourceDefinition resource, String path) {
    final errors = <ValidationError>[];

    if (resource.type.isEmpty) {
      errors.add(ValidationError(
        field: '$path.type',
        message: 'Resource type is required',
      ));
    }

    // Validate hardware resources
    switch (resource.type) {
      case 'gpio':
        if (resource.config['pins'] == null) {
          errors.add(ValidationError(
            field: '$path.config.pins',
            message: 'GPIO resource requires pins configuration',
          ));
        }
        break;

      case 'i2c':
        if (resource.config['bus'] == null) {
          errors.add(ValidationError(
            field: '$path.config.bus',
            message: 'I2C resource requires bus configuration',
          ));
        }
        break;

      case 'spi':
        if (resource.config['device'] == null) {
          errors.add(ValidationError(
            field: '$path.config.device',
            message: 'SPI resource requires device configuration',
          ));
        }
        break;

      case 'uart':
        if (resource.config['port'] == null) {
          errors.add(ValidationError(
            field: '$path.config.port',
            message: 'UART resource requires port configuration',
          ));
        }
        break;

      case 'modbus':
        if (resource.config['mode'] == null) {
          errors.add(ValidationError(
            field: '$path.config.mode',
            message: 'Modbus resource requires mode configuration',
          ));
        }
        break;
    }

    return errors;
  }

  List<ValidationError> _validateState(StateDefinition state, String path) {
    final errors = <ValidationError>[];

    // Validate constraints
    if (state.constraints != null) {
      final constraints = state.constraints!;
      
      if (state.type == StateType.number) {
        if (constraints.min != null && constraints.max != null &&
            constraints.min! > constraints.max!) {
          errors.add(ValidationError(
            field: '$path.constraints',
            message: 'Min value cannot be greater than max value',
            value: constraints,
          ));
        }
      }

      if (state.type == StateType.string) {
        if (constraints.minLength != null && constraints.maxLength != null &&
            constraints.minLength! > constraints.maxLength!) {
          errors.add(ValidationError(
            field: '$path.constraints',
            message: 'Min length cannot be greater than max length',
            value: constraints,
          ));
        }
      }
    }

    // Validate initial value matches type
    if (state.initial != null) {
      final typeError = _validateValueType(state.initial, state.type);
      if (typeError != null) {
        errors.add(ValidationError(
          field: '$path.initial',
          message: typeError,
          value: state.initial,
        ));
      }
    }

    return errors;
  }

  List<ValidationError> _validateChannel(ChannelDefinition channel, String path) {
    final errors = <ValidationError>[];

    if (channel.capacity != null && channel.capacity! <= 0) {
      errors.add(ValidationError(
        field: '$path.capacity',
        message: 'Channel capacity must be positive',
        value: channel.capacity,
      ));
    }

    return errors;
  }

  List<ValidationError> _validateEvent(EventDefinition event, String path) {
    final errors = <ValidationError>[];

    if (event.id.isEmpty) {
      errors.add(ValidationError(
        field: '$path.id',
        message: 'Event ID is required',
      ));
    }

    if (event.type.isEmpty) {
      errors.add(ValidationError(
        field: '$path.type',
        message: 'Event type is required',
      ));
    }

    if (event.source.isEmpty) {
      errors.add(ValidationError(
        field: '$path.source',
        message: 'Event source is required',
      ));
    }

    return errors;
  }

  List<ValidationError> _crossValidate(FlowDefinition flow) {
    final errors = <ValidationError>[];
    
    // Check for duplicate process IDs
    final processIds = <String>{};
    for (final process in flow.processes) {
      if (!processIds.add(process.id)) {
        errors.add(ValidationError(
          field: 'processes',
          message: 'Duplicate process ID: ${process.id}',
        ));
      }
    }

    // Check event references
    final eventIds = flow.events?.map((e) => e.id).toSet() ?? {};
    for (final process in flow.processes) {
      if (process.trigger?.type == TriggerType.event &&
          process.trigger!.event != null &&
          !eventIds.contains(process.trigger!.event)) {
        errors.add(ValidationError(
          field: 'processes.${process.id}.trigger.event',
          message: 'Referenced event not found: ${process.trigger!.event}',
        ));
      }
    }

    // Check state variable references in conditions
    // TODO: Parse and validate expressions

    return errors;
  }

  String? _validateValueType(dynamic value, StateType type) {
    switch (type) {
      case StateType.boolean:
        if (value is! bool) {
          return 'Expected boolean value, got ${value.runtimeType}';
        }
        break;

      case StateType.number:
        if (value is! num) {
          return 'Expected number value, got ${value.runtimeType}';
        }
        break;

      case StateType.string:
        if (value is! String) {
          return 'Expected string value, got ${value.runtimeType}';
        }
        break;

      case StateType.object:
        if (value is! Map<String, dynamic>) {
          return 'Expected object value, got ${value.runtimeType}';
        }
        break;

      case StateType.array:
        if (value is! List) {
          return 'Expected array value, got ${value.runtimeType}';
        }
        break;
    }
    return null;
  }
}