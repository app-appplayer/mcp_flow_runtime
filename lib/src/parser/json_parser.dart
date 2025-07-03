/// JSON parser for MCP Flow DSL

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import '../types/flow_types.dart';
import '../errors/flow_errors.dart';

/// JSON flow parser
class JsonFlowParser {
  final Logger _logger = Logger('JsonFlowParser');

  /// Parse flow definition from JSON
  FlowDefinition parse(Map<String, dynamic> json) {
    try {
      // Ensure proper type casting
      final typedJson = <String, dynamic>{};
      json.forEach((key, value) {
        if (value is Map) {
          typedJson[key] = _convertMap(value);
        } else if (value is List) {
          typedJson[key] = _convertList(value);
        } else {
          typedJson[key] = value;
        }
      });
      
      return FlowDefinition.fromJson(typedJson);
    } catch (e, stackTrace) {
      _logger.severe('Failed to parse flow JSON', e, stackTrace);
      throw FlowParseError(
        'Failed to parse flow definition: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }
  
  /// Convert dynamic map to typed map
  Map<String, dynamic> _convertMap(Map map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is Map) {
        result[key.toString()] = _convertMap(value);
      } else if (value is List) {
        result[key.toString()] = _convertList(value);
      } else {
        result[key.toString()] = value;
      }
    });
    return result;
  }
  
  /// Convert dynamic list to typed list
  List<dynamic> _convertList(List list) {
    return list.map((item) {
      if (item is Map) {
        return _convertMap(item);
      } else if (item is List) {
        return _convertList(item);
      } else {
        return item;
      }
    }).toList();
  }

  /// Load flow definition from file
  Future<Map<String, dynamic>> loadFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw FlowParseError('Flow file not found: $path');
      }

      final content = await file.readAsString();
      final json = jsonDecode(content);

      if (json is! Map<String, dynamic>) {
        throw FlowParseError('Flow file must contain a JSON object');
      }

      return json;
    } catch (e, stackTrace) {
      if (e is FlowParseError) rethrow;
      
      _logger.severe('Failed to load flow file: $path', e, stackTrace);
      throw FlowParseError(
        'Failed to load flow file: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Parse and validate flow from file
  Future<FlowDefinition> parseFile(String path) async {
    final json = await loadFromFile(path);
    return parse(json);
  }

  /// Convert flow definition to JSON
  Map<String, dynamic> toJson(FlowDefinition flow) {
    try {
      return flow.toJson();
    } catch (e, stackTrace) {
      _logger.severe('Failed to convert flow to JSON', e, stackTrace);
      throw FlowParseError(
        'Failed to convert flow to JSON: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Save flow definition to file
  Future<void> saveToFile(FlowDefinition flow, String path) async {
    try {
      final json = toJson(flow);
      final content = const JsonEncoder.withIndent('  ').convert(json);
      
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      
      _logger.info('Flow saved to: $path');
    } catch (e, stackTrace) {
      _logger.severe('Failed to save flow file: $path', e, stackTrace);
      throw FlowParseError(
        'Failed to save flow file: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }
}