/// BundleStepAdapter — Static utility for converting FlowStep instances
/// to runtime-consumable maps with type-specific config handling.
library;

import 'package:mcp_bundle/mcp_bundle.dart';

/// Warnings collected during step conversion.
class StepConversionResult {
  StepConversionResult({
    required this.steps,
    this.warnings = const [],
  });

  /// Converted step maps.
  final List<Map<String, dynamic>> steps;

  /// Warnings generated during conversion.
  final List<FlowError> warnings;
}

/// Static utility class for converting [FlowStep] instances to
/// runtime-consumable maps with type-specific config handling.
class BundleStepAdapter {
  BundleStepAdapter._();

  /// Required config keys per step type.
  static const Map<String, List<String>> _requiredKeys = {
    'action': ['actionType'],
    'skill': ['skillId'],
    'flow': ['flowId'],
    'condition': ['expression'],
    'switchCase': ['expression'],
    'parallel': ['branches'],
    'api': ['url', 'method'],
    'llm': ['provider', 'model', 'prompt'],
    'setVar': ['variable', 'value'],
    'transform': ['input', 'expression'],
    'output': ['expression'],
  };

  /// Step types where at least one of the listed keys must be present.
  static const Map<String, List<String>> _requiredAnyKeys = {
    'loop': ['expression', 'maxIterations'],
    'wait': ['durationMs', 'condition'],
  };

  /// Convert a list of [FlowStep] instances to runtime-consumable maps.
  ///
  /// Each step is converted via [toStepMap] with type-specific config
  /// validation. Unknown step types produce a warning but are still
  /// included in the output (with type set to 'unknown').
  static StepConversionResult toStepList(List<FlowStep> steps) {
    final warnings = <FlowError>[];
    final result = <Map<String, dynamic>>[];

    for (final step in steps) {
      final converted = toStepMap(step);
      result.add(converted.step);
      warnings.addAll(converted.warnings);
    }

    return StepConversionResult(steps: result, warnings: warnings);
  }

  /// Convert a single [FlowStep] to a runtime-consumable map.
  static _SingleStepResult toStepMap(FlowStep step) {
    final warnings = <FlowError>[];
    final typeName = step.type.name;

    // Handle unknown step type
    final outputType =
        step.type == StepType.unknown ? 'unknown' : typeName;

    if (step.type == StepType.unknown) {
      warnings.add(FlowError(
        code: 'INVALID_STEP_TYPE',
        message: 'Unknown step type for step "${step.id}"',
        path: 'steps/${step.id}',
      ));
    }

    // Validate required config keys
    _validateRequiredKeys(step, warnings);

    final map = <String, dynamic>{
      'id': step.id,
      'type': outputType,
    };

    if (step.name != null) map['name'] = step.name;
    if (step.config.isNotEmpty) map['config'] = step.config;
    if (step.condition != null) map['condition'] = step.condition;
    if (step.next.isNotEmpty) map['next'] = step.next;
    if (step.onError != null) map['onError'] = step.onError;
    if (step.timeoutMs != null) map['timeoutMs'] = step.timeoutMs;
    if (step.retry != null) map['retry'] = step.retry!.toJson();

    return _SingleStepResult(step: map, warnings: warnings);
  }

  static void _validateRequiredKeys(
      FlowStep step, List<FlowError> warnings) {
    final typeName = step.type.name;

    // Check strict required keys
    if (_requiredKeys.containsKey(typeName)) {
      for (final key in _requiredKeys[typeName]!) {
        if (!step.config.containsKey(key)) {
          warnings.add(FlowError(
            code: 'INVALID_STEP_CONFIG',
            message:
                'Step "${step.id}" of type "$typeName" is missing required config key "$key"',
            path: 'steps/${step.id}/config/$key',
          ));
        }
      }
    }

    // Check "at least one of" required keys
    if (_requiredAnyKeys.containsKey(typeName)) {
      final keys = _requiredAnyKeys[typeName]!;
      final hasAny = keys.any((k) => step.config.containsKey(k));
      if (!hasAny) {
        warnings.add(FlowError(
          code: 'INVALID_STEP_CONFIG',
          message:
              'Step "${step.id}" of type "$typeName" requires at least one of: ${keys.join(", ")}',
          path: 'steps/${step.id}/config',
        ));
      }
    }
  }
}

class _SingleStepResult {
  _SingleStepResult({required this.step, this.warnings = const []});

  final Map<String, dynamic> step;
  final List<FlowError> warnings;
}
