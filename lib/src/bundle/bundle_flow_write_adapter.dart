/// BundleFlowWriteAdapter — Write adapter implementing FlowPort.
///
/// Converts Flow definition JSON into bundle-compatible sections.
/// Returns FlowWriteOutput containing FlowSection + manifest metadata.
library;

import 'package:mcp_bundle/mcp_bundle.dart';

/// Write adapter that implements [FlowPort] from mcp_bundle.
///
/// Converts Flow definition JSON → FlowWriteOutput (FlowSection + metadata).
/// Throws [UnsupportedError] for [toDefinition] and [toFlowInfo] (read operations).
class BundleFlowWriteAdapter implements FlowPort {
  @override
  Future<FlowResult<FlowWriteOutput>> fromDefinition(
      Map<String, dynamic> definitionJson) async {
    try {
      // 1. Extract metadata
      final manifestMetadata = <String, dynamic>{};
      if (definitionJson['id'] != null) {
        manifestMetadata['id'] = definitionJson['id'];
      }
      if (definitionJson['name'] != null) {
        manifestMetadata['name'] = definitionJson['name'];
      }
      if (definitionJson['version'] != null) {
        manifestMetadata['version'] = definitionJson['version'];
      }
      if (definitionJson['description'] != null) {
        manifestMetadata['description'] = definitionJson['description'];
      }

      // 2. Extract schemaVersion
      final schemaVersion =
          definitionJson['schemaVersion'] as String? ?? '1.0.0';

      // 3. Extract flows
      final flowsList = <FlowDefinition>[];
      final rawFlows = definitionJson['flows'] as List<dynamic>?;
      if (rawFlows != null) {
        for (final rawFlow in rawFlows) {
          flowsList.add(
              FlowDefinition.fromJson(rawFlow as Map<String, dynamic>));
        }
      }

      // 4. Extract sharedState
      final sharedState =
          definitionJson['sharedState'] as Map<String, dynamic>? ?? {};

      // 5. Extract errorHandlers
      final errorHandlers = <ErrorHandler>[];
      final rawHandlers = definitionJson['errorHandlers'] as List<dynamic>?;
      if (rawHandlers != null) {
        for (final rawHandler in rawHandlers) {
          errorHandlers.add(
              ErrorHandler.fromJson(rawHandler as Map<String, dynamic>));
        }
      }

      // 6. Build FlowSection
      final flowSection = FlowSection(
        schemaVersion: schemaVersion,
        flows: flowsList,
        sharedState: sharedState,
        errorHandlers: errorHandlers,
      );

      return FlowResult.ok(FlowWriteOutput(
        flowSection: flowSection,
        manifestMetadata: manifestMetadata,
      ));
    } catch (e) {
      return FlowResult.fail(FlowError(
        code: 'CONVERSION_ERROR',
        message: 'Failed to convert Flow definition to bundle sections: $e',
      ));
    }
  }

  @override
  Future<FlowResult<Map<String, dynamic>>> toDefinition(McpBundle bundle) {
    throw UnsupportedError(
        'BundleFlowWriteAdapter does not support read operations');
  }

  @override
  Future<FlowResult<Map<String, dynamic>>> toFlowInfo(McpBundle bundle) {
    throw UnsupportedError(
        'BundleFlowWriteAdapter does not support read operations');
  }
}
