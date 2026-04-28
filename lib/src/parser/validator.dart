/// Flow definition validator

import '../types/flow_types.dart';

/// Validation severity level
enum ValidationSeverity { error, warning }

/// Validation error details
class ValidationError {
  final String code;
  final String message;
  final String? path;
  final ValidationSeverity severity;
  final dynamic value;

  ValidationError({
    required this.code,
    required this.message,
    this.path,
    this.severity = ValidationSeverity.error,
    this.value,
  });

  @override
  String toString() => '[${severity.name}] $code: $message${path != null ? ' at $path' : ''}';
}

/// Flow validator
class FlowValidator {
  // Valid action types
  static const Set<String> _validActions = {
    // ===== HARDWARE ACTIONS =====
    'gpioRead', 'gpioWrite', 'gpioConfig', 'gpioToggle', 'gpioInterrupt',
    'pwmSet', 'pwmWrite', 'pwmConfig',
    'i2cRead', 'i2cWrite', 'i2cScan',
    'spiTransfer', 'spiWrite', 'spiRead',
    'adcRead', 'adcReadVoltage', 'dacWrite', 'dacWriteVoltage',
    'uartRead', 'uartWrite', 'uartAvailable', 'uartFlush',
    'modbusRead', 'modbusWrite',

    // ===== STATE ACTIONS =====
    'stateGet', 'stateSet', 'stateUpdate', 'stateDelete', 'stateClear',
    'increment', 'decrement', 'append', 'merge', 'toggle',

    // ===== CONTROL FLOW ACTIONS =====
    'if', 'while', 'for', 'switch', 'parallel', 'try',
    'break', 'continue', 'return',

    // ===== CHANNEL ACTIONS =====
    'channelSend', 'channelReceive', 'channelPublish', 'channelSubscribe',
    'channelCreate', 'channelClose',

    // ===== PROCESS ACTIONS =====
    'fork', 'join', 'processStart', 'processStop',

    // ===== MCP ACTIONS =====
    'mcpNotify', 'mcpUpdateResource', 'mcpCallTool', 'mcpSubscribe',

    // ===== SYNC ACTIONS =====
    'syncLock', 'syncUnlock', 'syncWait', 'syncSignal', 'syncBarrier',

    // ===== MEMORY ACTIONS =====
    'memoryAllocate', 'memoryWrite', 'memoryRead', 'memoryAtomic',

    // ===== MQTT ACTIONS =====
    'mqttPublish', 'mqttSubscribe', 'mqttUnsubscribe',

    // ===== TIMER ACTIONS =====
    'wait', 'timerStart', 'timerStop', 'delay', 'waitUntil', 'timeStart', 'timeElapsed',

    // ===== SYSTEM ACTIONS =====
    'log', 'systemGetInfo', 'systemSetConfig', 'systemRestart', 'systemShutdown',
    'eventEmit',

    // ===== NON-SPEC EXTENSIONS =====
    'expression', 'function',
    'httpRequest', 'httpGet', 'httpPost', 'httpPut', 'httpDelete',
    'fileRead', 'fileWrite', 'fileAppend', 'fileDelete', 'fileExists',
    'serviceDiscover', 'serviceConnect', 'serviceCall', 'serviceSubscribe',
  };

  // Known resource types for unknown-type warning
  static const Set<String> _knownResourceTypes = {
    'gpio', 'i2c', 'spi', 'pwm', 'uart', 'adc', 'dac', 'modbus', 'mqtt',
  };

  /// Validate flow definition
  List<ValidationError> validate(FlowDefinition flow) {
    final errors = <ValidationError>[];

    // Validate version
    if (flow.version.isEmpty) {
      errors.add(ValidationError(
        code: 'MISSING_REQUIRED_FIELD',
        path: 'version',
        message: 'Version is required',
      ));
    }

    // Validate configuration tickRateMs
    if (flow.configuration?.runtime?.tickRateMs != null) {
      final tickRateMs = flow.configuration!.runtime!.tickRateMs!;
      if (tickRateMs <= 0) {
        errors.add(ValidationError(
          code: 'INVALID_TYPE',
          path: 'configuration.runtime.tickRateMs',
          message: 'tickRateMs must be greater than 0',
          value: tickRateMs,
        ));
      }
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
        code: 'MISSING_REQUIRED_FIELD',
        path: '$path.id',
        message: 'Process ID is required',
      ));
    }

    // Validate steps
    if (process.steps.isEmpty) {
      errors.add(ValidationError(
        code: 'MISSING_REQUIRED_FIELD',
        path: '$path.steps',
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
        code: 'MISSING_REQUIRED_FIELD',
        path: '$path.action',
        message: 'Action type is required',
      ));
    } else if (!_validActions.contains(action.action)) {
      errors.add(ValidationError(
        code: 'INVALID_ACTION',
        path: '$path.action',
        message: 'Invalid action type: ${action.action}',
        value: action.action,
      ));
    }

    // Validate control flow actions
    switch (action.action) {
      case 'if':
        // Check for condition at top level first (per spec), then fallback to params
        if (action.condition == null && action.params?['condition'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.condition',
            message: 'If action requires condition',
          ));
        }
        if (action.then == null && action.else$ == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path',
            message: 'If action requires then or else branch',
          ));
        }
        break;

      case 'while':
      case 'for':
        if (action.do$ == null || action.do$!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.do',
            message: '${action.action} action requires do block',
          ));
        }
        break;

      case 'switch':
        if (action.value == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.value',
            message: 'Switch action requires value',
          ));
        }
        if (action.cases == null || action.cases!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.cases',
            message: 'Switch action requires cases',
          ));
        }
        break;

      case 'parallel':
        if (action.branches == null || action.branches!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.branches',
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
          code: 'INVALID_TYPE',
          path: '$path.retry.count',
          message: 'Retry count must be non-negative',
          value: action.retry!.count,
        ));
      }
      if (action.retry!.delayMs < 0) {
        errors.add(ValidationError(
          code: 'INVALID_TYPE',
          path: '$path.retry.delayMs',
          message: 'Retry delay must be non-negative',
          value: action.retry!.delayMs,
        ));
      }
    }

    return errors;
  }

  List<ValidationError> _validateTrigger(TriggerDefinition trigger, String path) {
    final errors = <ValidationError>[];

    // Validate trigger type is known
    switch (trigger.type) {
      case TriggerType.event:
        if (trigger.event == null || trigger.event!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_TRIGGER_FIELD',
            path: '$path.event',
            message: 'Event trigger requires event name',
          ));
        }
        break;

      case TriggerType.condition:
        if (trigger.condition == null || trigger.condition!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_TRIGGER_FIELD',
            path: '$path.condition',
            message: 'Condition trigger requires condition expression',
          ));
        }
        break;

      case TriggerType.schedule:
        if (trigger.interval == null && trigger.cron == null) {
          errors.add(ValidationError(
            code: 'MISSING_TRIGGER_FIELD',
            path: '$path',
            message: 'Schedule trigger requires interval or cron',
          ));
        }
        if (trigger.interval != null && trigger.interval! <= 0) {
          errors.add(ValidationError(
            code: 'INVALID_TYPE',
            path: '$path.interval',
            message: 'Schedule interval must be positive',
            value: trigger.interval,
          ));
        }
        break;

      case TriggerType.channelReceive:
        if (trigger.channel == null || trigger.channel!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_TRIGGER_FIELD',
            path: '$path.channel',
            message: 'Channel receive trigger requires channel name',
          ));
        }
        break;

      case TriggerType.stateChange:
        if (trigger.variable == null && trigger.condition == null) {
          errors.add(ValidationError(
            code: 'MISSING_TRIGGER_FIELD',
            path: '$path',
            message: 'State change trigger requires variable or condition',
          ));
        }
        break;

      case TriggerType.resourceEvent:
        if (trigger.resource == null || trigger.resource!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_TRIGGER_FIELD',
            path: '$path.resource',
            message: 'Resource event trigger requires resource name',
          ));
        }
        if (trigger.event == null || trigger.event!.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_TRIGGER_FIELD',
            path: '$path.event',
            message: 'Resource event trigger requires event name',
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
        code: 'MISSING_REQUIRED_FIELD',
        path: '$path.type',
        message: 'Resource type is required',
      ));
    }

    // Warn on unknown resource types
    if (resource.type.isNotEmpty && !_knownResourceTypes.contains(resource.type)) {
      errors.add(ValidationError(
        code: 'UNKNOWN_RESOURCE_TYPE',
        path: '$path.type',
        message: 'Unknown resource type: ${resource.type}',
        value: resource.type,
        severity: ValidationSeverity.warning,
      ));
    }

    // Validate hardware resources (warnings — runtime enforces at use time)
    switch (resource.type) {
      case 'gpio':
        if (resource.config['pins'] == null && resource.config['pin'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.pins',
            message: 'GPIO resource requires pin or pins configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        break;

      case 'i2c':
        if (resource.config['bus'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.bus',
            message: 'I2C resource requires bus configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        if (resource.config['address'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.address',
            message: 'I2C resource requires address configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        break;

      case 'spi':
        if (resource.config['bus'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.bus',
            message: 'SPI resource requires bus configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        if (resource.config['device'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.device',
            message: 'SPI resource requires device configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        break;

      case 'uart':
        if (resource.config['port'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.port',
            message: 'UART resource requires port configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        if (resource.config['baudRate'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.baudRate',
            message: 'UART resource requires baudRate configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        break;

      case 'modbus':
        if (resource.config['mode'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.mode',
            message: 'Modbus resource requires mode configuration',
            severity: ValidationSeverity.warning,
          ));
        }
        if (resource.config['address'] == null) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_FIELD',
            path: '$path.config.address',
            message: 'Modbus resource requires address configuration',
            severity: ValidationSeverity.warning,
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
            code: 'INVALID_TYPE',
            path: '$path.constraints',
            message: 'Min value cannot be greater than max value',
            value: constraints,
          ));
        }
      }

      if (state.type == StateType.string) {
        if (constraints.minLength != null && constraints.maxLength != null &&
            constraints.minLength! > constraints.maxLength!) {
          errors.add(ValidationError(
            code: 'INVALID_TYPE',
            path: '$path.constraints',
            message: 'Min length cannot be greater than max length',
            value: constraints,
          ));
        }
      }

      // Validate initial value within min/max range
      if (state.initial != null && state.type == StateType.number && state.initial is num) {
        final initialNum = (state.initial as num).toDouble();
        if (constraints.min != null && initialNum < constraints.min!) {
          errors.add(ValidationError(
            code: 'INVALID_TYPE',
            path: '$path.initial',
            message: 'Initial value $initialNum is less than min ${constraints.min}',
            value: state.initial,
          ));
        }
        if (constraints.max != null && initialNum > constraints.max!) {
          errors.add(ValidationError(
            code: 'INVALID_TYPE',
            path: '$path.initial',
            message: 'Initial value $initialNum is greater than max ${constraints.max}',
            value: state.initial,
          ));
        }
      }
    }

    // Validate initial value matches type
    if (state.initial != null) {
      final typeError = _validateValueType(state.initial, state.type);
      if (typeError != null) {
        errors.add(ValidationError(
          code: 'INVALID_TYPE',
          path: '$path.initial',
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
        code: 'INVALID_TYPE',
        path: '$path.capacity',
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
        code: 'MISSING_REQUIRED_FIELD',
        path: '$path.id',
        message: 'Event ID is required',
      ));
    }

    if (event.type.isEmpty) {
      errors.add(ValidationError(
        code: 'MISSING_REQUIRED_FIELD',
        path: '$path.type',
        message: 'Event type is required',
      ));
    }

    if (event.source.isEmpty) {
      errors.add(ValidationError(
        code: 'MISSING_REQUIRED_FIELD',
        path: '$path.source',
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
          code: 'DUPLICATE_PROCESS_ID',
          path: 'processes',
          message: 'Duplicate process ID: ${process.id}',
          value: process.id,
        ));
      }
    }

    // Check channel references in triggers
    final channelNames = flow.channels?.keys.toSet() ?? {};

    for (int i = 0; i < flow.processes.length; i++) {
      final process = flow.processes[i];
      if (process.trigger?.type == TriggerType.channelReceive &&
          process.trigger!.channel != null &&
          !channelNames.contains(process.trigger!.channel)) {
        errors.add(ValidationError(
          code: 'UNDEFINED_CHANNEL_REF',
          severity: ValidationSeverity.warning,
          path: 'processes[$i].trigger.channel',
          message: 'Referenced channel not found: ${process.trigger!.channel}',
          value: process.trigger!.channel,
        ));
      }
    }

    // Check channel references in actions
    for (int i = 0; i < flow.processes.length; i++) {
      final process = flow.processes[i];
      errors.addAll(_validateChannelReferencesInActions(
        process.steps,
        'processes[$i].steps',
        channelNames,
      ));

      if (process.error != null) {
        errors.addAll(_validateChannelReferencesInActions(
          process.error!,
          'processes[$i].error',
          channelNames,
        ));
      }

      if (process.finally$ != null) {
        errors.addAll(_validateChannelReferencesInActions(
          process.finally$!,
          'processes[$i].finally',
          channelNames,
        ));
      }
    }

    // TODO: Parse and validate state variable references in expressions

    return errors;
  }

  List<ValidationError> _validateChannelReferencesInActions(
    List<ActionDefinition> actions,
    String path,
    Set<String> channelNames,
  ) {
    final errors = <ValidationError>[];

    for (int i = 0; i < actions.length; i++) {
      final action = actions[i];

      // Check channel-related actions for valid channel references
      if ((action.action == 'channelSend' || action.action == 'channelReceive' ||
           action.action == 'channelPublish' || action.action == 'channelSubscribe') &&
          action.params?['channel'] != null) {
        final channelName = action.params!['channel'] as String;
        if (!channelNames.contains(channelName)) {
          errors.add(ValidationError(
            code: 'UNDEFINED_CHANNEL_REF',
          severity: ValidationSeverity.warning,
            path: '$path[$i].params.channel',
            message: 'Referenced channel not found: $channelName',
            value: channelName,
          ));
        }
      }

      // Recursively check nested actions
      if (action.then != null) {
        errors.addAll(_validateChannelReferencesInActions(
          action.then!,
          '$path[$i].then',
          channelNames,
        ));
      }
      if (action.else$ != null) {
        errors.addAll(_validateChannelReferencesInActions(
          action.else$!,
          '$path[$i].else',
          channelNames,
        ));
      }
      if (action.do$ != null) {
        errors.addAll(_validateChannelReferencesInActions(
          action.do$!,
          '$path[$i].do',
          channelNames,
        ));
      }
      if (action.branches != null) {
        for (int j = 0; j < action.branches!.length; j++) {
          errors.addAll(_validateChannelReferencesInActions(
            action.branches![j].steps,
            '$path[$i].branches[$j].steps',
            channelNames,
          ));
        }
      }
    }

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

      case StateType.any:
        // Any type accepts all values
        break;
    }
    return null;
  }
}
