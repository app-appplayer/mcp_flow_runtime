/// BundleFlowReadAdapter — Read adapter implementing FlowPort.
///
/// Converts a loaded McpBundle into runtime-consumable Flow definition JSON.
/// No external dependencies required (no asset resolution needed).
library;

import 'package:mcp_bundle/mcp_bundle.dart';

import 'bundle_step_adapter.dart';

/// Read adapter that implements [FlowPort] from mcp_bundle.
///
/// Converts McpBundle → runtime-consumable Flow definition JSON.
/// Throws [UnsupportedError] for [fromDefinition] (write operation).
class BundleFlowReadAdapter implements FlowPort {
  @override
  Future<FlowResult<Map<String, dynamic>>> toDefinition(
      McpBundle bundle) async {
    // 1. Validate FlowSection presence
    if (bundle.flow == null) {
      return FlowResult.fail(FlowError(
        code: 'MISSING_FLOW_SECTION',
        message: 'McpBundle does not contain a FlowSection',
      ));
    }

    // 2. Validate required manifest fields
    if (bundle.manifest.name.isEmpty || bundle.manifest.version.isEmpty) {
      return FlowResult.fail(FlowError(
        code: 'INVALID_MANIFEST',
        message:
            'Required manifest fields (name, version) are missing or empty',
        path: 'manifest',
      ));
    }

    try {
      final flowSection = bundle.flow!;
      final warnings = <FlowError>[];

      // 3. Map FlowSection → runtime definition
      final flowsList = <Map<String, dynamic>>[];
      for (final flow in flowSection.flows) {
        // Skip flows with missing id or name
        if (flow.id.isEmpty || flow.name.isEmpty) {
          warnings.add(FlowError(
            code: 'INVALID_FLOW_DEFINITION',
            message:
                'FlowDefinition missing required field (id or name), skipping',
            path: 'flows/${flow.id.isEmpty ? "(empty)" : flow.id}',
          ));
          continue;
        }

        final flowMap = _mapFlowDefinition(flow, warnings);
        flowsList.add(flowMap);
      }

      // 4. Build output
      final result = <String, dynamic>{
        'id': bundle.manifest.id,
        'name': bundle.manifest.name,
        'version': bundle.manifest.version,
        if (bundle.manifest.description != null)
          'description': bundle.manifest.description,
        'schemaVersion': flowSection.schemaVersion,
        'flows': flowsList,
      };

      if (flowSection.sharedState.isNotEmpty) {
        result['sharedState'] = flowSection.sharedState;
      }

      if (flowSection.errorHandlers.isNotEmpty) {
        result['errorHandlers'] =
            flowSection.errorHandlers.map((e) => e.toJson()).toList();
      }

      if (warnings.isNotEmpty) {
        return FlowResult.okWithWarnings(result, warnings);
      }
      return FlowResult.ok(result);
    } catch (e) {
      return FlowResult.fail(FlowError(
        code: 'CONVERSION_ERROR',
        message: 'Failed to convert bundle to Flow definition: $e',
      ));
    }
  }

  @override
  Future<FlowResult<Map<String, dynamic>>> toFlowInfo(
      McpBundle bundle) async {
    // Validate FlowSection presence
    if (bundle.flow == null) {
      return FlowResult.fail(FlowError(
        code: 'MISSING_FLOW_SECTION',
        message: 'McpBundle does not contain a FlowSection',
      ));
    }

    // Validate required manifest fields
    if (bundle.manifest.name.isEmpty || bundle.manifest.version.isEmpty) {
      return FlowResult.fail(FlowError(
        code: 'INVALID_MANIFEST',
        message:
            'Required manifest fields (name, version) are missing or empty',
        path: 'manifest',
      ));
    }

    try {
      final flowSection = bundle.flow!;

      // Build flow summaries
      final flowSummaries = <Map<String, dynamic>>[];
      for (final flow in flowSection.flows) {
        if (flow.id.isEmpty || flow.name.isEmpty) continue;

        final summary = <String, dynamic>{
          'id': flow.id,
          'name': flow.name,
        };

        if (flow.description != null) {
          summary['description'] = flow.description;
        }

        if (flow.trigger != null) {
          summary['trigger'] = <String, dynamic>{
            'type': flow.trigger!.type.name,
            if (flow.trigger!.config.isNotEmpty)
              'config': flow.trigger!.config,
          };
        }

        summary['inputCount'] = flow.inputs.length;
        summary['hasOutput'] = flow.output != null;

        flowSummaries.add(summary);
      }

      final result = <String, dynamic>{
        if (bundle.manifest.id.isNotEmpty) 'id': bundle.manifest.id,
        'name': bundle.manifest.name,
        'version': bundle.manifest.version,
        if (bundle.manifest.description != null)
          'description': bundle.manifest.description,
        'flows': flowSummaries,
      };

      if (flowSection.sharedState.isNotEmpty) {
        result['sharedStateKeys'] = flowSection.sharedState.keys.toList();
      }

      return FlowResult.ok(result);
    } catch (e) {
      return FlowResult.fail(FlowError(
        code: 'CONVERSION_ERROR',
        message: 'Failed to extract Flow info: $e',
      ));
    }
  }

  @override
  Future<FlowResult<FlowWriteOutput>> fromDefinition(
      Map<String, dynamic> definitionJson) {
    throw UnsupportedError(
        'BundleFlowReadAdapter does not support write operations');
  }

  /// Map a single FlowDefinition to a runtime-consumable map.
  Map<String, dynamic> _mapFlowDefinition(
      FlowDefinition flow, List<FlowError> warnings) {
    final map = <String, dynamic>{
      'id': flow.id,
      'name': flow.name,
    };

    if (flow.description != null) map['description'] = flow.description;

    // Trigger mapping
    if (flow.trigger != null) {
      final trigger = flow.trigger!;
      final triggerType = trigger.type == TriggerType.unknown
          ? 'unknown'
          : trigger.type.name;

      if (trigger.type == TriggerType.unknown) {
        warnings.add(FlowError(
          code: 'INVALID_TRIGGER_TYPE',
          message: 'Unknown trigger type in flow "${flow.id}"',
          path: 'flows/${flow.id}/trigger',
        ));
      }

      map['trigger'] = <String, dynamic>{
        'type': triggerType,
        if (trigger.config.isNotEmpty) 'config': trigger.config,
        if (trigger.condition != null) 'condition': trigger.condition,
      };
    }

    // Steps mapping via BundleStepAdapter
    if (flow.steps.isNotEmpty) {
      final stepResult = BundleStepAdapter.toStepList(flow.steps);
      map['steps'] = stepResult.steps;
      warnings.addAll(stepResult.warnings);
    }

    // Inputs mapping
    if (flow.inputs.isNotEmpty) {
      map['inputs'] = flow.inputs.map((i) => i.toJson()).toList();
    }

    // Output mapping
    if (flow.output != null) {
      map['output'] = flow.output!.toJson();
    }

    // Timeout
    if (flow.timeoutMs != null) {
      map['timeoutMs'] = flow.timeoutMs;
    }

    // Retry config
    if (flow.retry != null) {
      map['retry'] = flow.retry!.toJson();
    }

    return map;
  }
}
