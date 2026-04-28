import 'dart:convert';
import 'dart:math' as math;
import 'package:expressions/expressions.dart';
import 'package:logging/logging.dart';

import '../errors/flow_errors.dart';

/// Enhanced expression evaluator with JavaScript-like built-in objects and functions
class EnhancedExpressionEvaluator extends ExpressionEvaluator {
  EnhancedExpressionEvaluator();

  /// Maximum expression string length (Spec 13-security: 1024)
  static const int maxExpressionLength = 1024;

  /// Maximum recursion depth (Spec 13-security: 10)
  static const int maxRecursionDepth = 10;

  /// Maximum evaluation time in milliseconds (SRS NFR-PERF-004: 10ms)
  static const int maxEvaluationTimeMs = 10;

  /// Current recursion depth tracker
  int _currentDepth = 0;

  /// Prohibited patterns for security (Spec 13-security)
  static const List<String> _prohibitedPatterns = [
    'file.',
    'fs.',
    'http.',
    'net.',
    'exec.',
    'eval(',
    'Function(',
    'require(',
  ];

  /// Safety-checked expression evaluation
  dynamic safeEval(String expressionString, Map<String, dynamic> context) {
    // Check expression length
    if (expressionString.length > maxExpressionLength) {
      throw ConcreteFlowError(
        'EXPR_LENGTH_EXCEEDED',
        'Expression exceeds maximum length of $maxExpressionLength characters',
      );
    }

    // Validate prohibited patterns
    for (final pattern in _prohibitedPatterns) {
      if (expressionString.contains(pattern)) {
        throw ConcreteFlowError(
          'EXPR_PROHIBITED_PATTERN',
          'Expression contains prohibited pattern: $pattern',
        );
      }
    }

    // Parse expression
    final expression = Expression.parse(expressionString);

    // Enforce timeout using Stopwatch
    final stopwatch = Stopwatch()..start();
    _currentDepth = 0;

    try {
      final result = eval(expression, context);
      stopwatch.stop();
      if (stopwatch.elapsedMilliseconds > maxEvaluationTimeMs) {
        throw ConcreteFlowError('EVAL_TIMEOUT', 'Expression evaluation exceeded ${maxEvaluationTimeMs}ms');
      }
      return result;
    } finally {
      stopwatch.stop();
      _currentDepth = 0;
    }
  }

  @override
  dynamic eval(Expression expression, Map<String, dynamic> context) {
    // Check recursion depth
    _currentDepth++;
    if (_currentDepth > maxRecursionDepth) {
      throw ConcreteFlowError(
        'EXPR_RECURSION_DEPTH',
        'Expression exceeds maximum recursion depth of $maxRecursionDepth',
      );
    }

    try {
      return _evalInternal(expression, context);
    } finally {
      _currentDepth--;
    }
  }

  /// Internal evaluation with built-in context
  dynamic _evalInternal(Expression expression, Map<String, dynamic> context) {
    // Add built-in objects to context
    final enhancedContext = <String, dynamic>{
      ...context,
      'Math': _MathObject(),
      'Date': _DateObject(),
      'JSON': _JSONObject(),
      'console': _ConsoleObject(),
      'parseInt': (dynamic value, [int? radix]) => _parseInt(value, radix),
      'parseFloat': (dynamic value) => _parseFloat(value),
      'isNaN': (dynamic value) => _isNaN(value),
      'isFinite': (dynamic value) => _isFinite(value),
      'true': true,
      'false': false,
      'null': null,
      'undefined': null,

      // Built-in functions (Spec §8.4)
      // Math functions
      'abs': (num x) => x.abs(),
      'min': (dynamic a, [dynamic b, dynamic c, dynamic d, dynamic e]) {
        if (a is List) {
          if (a.isEmpty) return 0;
          num result = a[0] is num ? a[0] : 0;
          for (var item in a) {
            if (item is num && item < result) result = item;
          }
          return result;
        }
        num result = a is num ? a : 0;
        if (b != null && b is num) result = math.min(result, b);
        if (c != null && c is num) result = math.min(result, c);
        if (d != null && d is num) result = math.min(result, d);
        if (e != null && e is num) result = math.min(result, e);
        return result;
      },
      'max': (dynamic a, [dynamic b, dynamic c, dynamic d, dynamic e]) {
        if (a is List) {
          if (a.isEmpty) return 0;
          num result = a[0] is num ? a[0] : 0;
          for (var item in a) {
            if (item is num && item > result) result = item;
          }
          return result;
        }
        num result = a is num ? a : 0;
        if (b != null && b is num) result = math.max(result, b);
        if (c != null && c is num) result = math.max(result, c);
        if (d != null && d is num) result = math.max(result, d);
        if (e != null && e is num) result = math.max(result, e);
        return result;
      },
      'round': (num x) => x.round(),
      'floor': (num x) => x.floor(),
      'ceil': (num x) => x.ceil(),
      'clamp': (num value, num minVal, num maxVal) => value.clamp(minVal, maxVal),

      // Type conversion
      'int': (dynamic x) {
        if (x is int) return x;
        if (x is double) return x.toInt();
        if (x is String) return int.tryParse(x) ?? 0;
        if (x is bool) return x ? 1 : 0;
        return 0;
      },
      'float': (dynamic x) {
        if (x is double) return x;
        if (x is int) return x.toDouble();
        if (x is String) return double.tryParse(x) ?? 0.0;
        if (x is bool) return x ? 1.0 : 0.0;
        return 0.0;
      },
      'bool': (dynamic x) {
        if (x is bool) return x;
        if (x is num) return x != 0;
        if (x is String) return x.isNotEmpty;
        if (x == null) return false;
        if (x is List) return x.isNotEmpty;
        if (x is Map) return x.isNotEmpty;
        return true;
      },
      'string': (dynamic x) => x.toString(),

      // Collection functions
      'length': (dynamic x) {
        if (x is List) return x.length;
        if (x is String) return x.length;
        if (x is Map) return x.length;
        return 0;
      },
      'sum': (List arr) {
        num result = 0;
        for (var item in arr) {
          if (item is num) result += item;
        }
        return result;
      },
      'avg': (List arr) {
        if (arr.isEmpty) return 0;
        num s = 0;
        int count = 0;
        for (var item in arr) {
          if (item is num) { s += item; count++; }
        }
        return count > 0 ? s / count : 0;
      },
      'first': (List arr) => arr.isEmpty ? null : arr.first,
      'last': (List arr) => arr.isEmpty ? null : arr.last,

      // String functions
      'concat': (String s1, [String? s2, String? s3, String? s4, String? s5]) {
        var result = s1;
        if (s2 != null) result += s2;
        if (s3 != null) result += s3;
        if (s4 != null) result += s4;
        if (s5 != null) result += s5;
        return result;
      },
      'substring': (String str, int start, int length) {
        final end = math.min(start + length, str.length);
        return str.substring(start, end);
      },
      'indexOf': (String str, String search) => str.indexOf(search),
      'upper': (String s) => s.toUpperCase(),
      'lower': (String s) => s.toLowerCase(),
      'trim': (String s) => s.trim(),
      'split': (String s, String delimiter) => s.split(delimiter),

      // Time functions
      'now': () => DateTime.now().millisecondsSinceEpoch,

      // Bit operations
      'setBit': (int value, int bit) => value | (1 << bit),
      'clearBit': (int value, int bit) => value & ~(1 << bit),
      'toggleBit': (int value, int bit) => value ^ (1 << bit),
      'testBit': (int value, int bit) => (value & (1 << bit)) != 0,
    };

    // Evaluate with enhanced context
    return _evaluateWithTypeCoercion(expression, enhancedContext);
  }

  dynamic _evaluateWithTypeCoercion(Expression expression, Map<String, dynamic> context) {
    try {
      // Handle binary operations with type coercion
      if (expression is BinaryExpression) {
        return _handleBinaryExpression(expression, context);
      }
      return super.eval(expression, context);
    } catch (e) {
      // Handle member access for built-in types
      if (expression is MemberExpression) {
        return _handleMemberExpression(expression, context);
      }
      rethrow;
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is bool) return value ? 1 : 0;
    if (value == null) return 0;
    return 0;
  }

  dynamic _handleBinaryExpression(BinaryExpression expr, Map<String, dynamic> context) {
    // Short-circuit evaluation for logical operators
    switch (expr.operator) {
      case '||':
        final left = eval(expr.left, context);
        if (_toBool(left)) return left;
        return eval(expr.right, context);
      case '&&':
        final left = eval(expr.left, context);
        if (!_toBool(left)) return left;
        return eval(expr.right, context);
    }

    // For other operators, evaluate both sides
    final left = eval(expr.left, context);
    final right = eval(expr.right, context);

    switch (expr.operator) {
      case '+':
        // String concatenation
        if (left is String || right is String) {
          return '${left ?? ""}${right ?? ""}';
        }
        // Numeric addition with coercion
        return _toNumber(left) + _toNumber(right);
      case '-':
        return _toNumber(left) - _toNumber(right);
      case '*':
        // String repetition
        if (left is String && right is num) {
          return left * right.toInt();
        }
        return _toNumber(left) * _toNumber(right);
      case '/':
        if (_toNumber(right) == 0) {
          throw ConcreteFlowError('DIVISION_BY_ZERO', 'Cannot divide by zero');
        }
        return _toNumber(left) / _toNumber(right);
      case '%':
        if (_toNumber(right) == 0) {
          throw ConcreteFlowError('DIVISION_BY_ZERO', 'Cannot modulo by zero');
        }
        return _toNumber(left) % _toNumber(right);
      case '==':
        return left == right;
      case '!=':
        return left != right;
      case '>':
        return _toNumber(left) > _toNumber(right);
      case '<':
        return _toNumber(left) < _toNumber(right);
      case '>=':
        return _toNumber(left) >= _toNumber(right);
      case '<=':
        return _toNumber(left) <= _toNumber(right);
      // Bitwise operators
      case '&':
        return _toInt(left) & _toInt(right);
      case '|':
        return _toInt(left) | _toInt(right);
      case '^':
        return _toInt(left) ^ _toInt(right);
      case '<<':
        return _toInt(left) << _toInt(right);
      case '>>':
        return _toInt(left) >> _toInt(right);
      // Power operator
      case '**':
        return math.pow(_toNumber(left), _toNumber(right));
      default:
        return super.eval(expr, context);
    }
  }

  num _toNumber(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value);
      return parsed ?? 0;
    }
    if (value is bool) return value ? 1 : 0;
    if (value == null) return 0;
    return 0;
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value == null) return false;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  dynamic _handleMemberExpression(MemberExpression expr, Map<String, dynamic> context) {
    final object = eval(expr.object, context);
    final property = expr.property.name;

    // Math object
    if (object is _MathObject) {
      return _getMathProperty(object, property);
    }
    
    // Date object
    if (object is _DateObject) {
      return _getDateProperty(object, property);
    }
    
    // String methods
    if (object is String) {
      return _getStringMethod(object, property);
    }
    
    // Array methods
    if (object is List) {
      return _getArrayMethod(object, property);
    }

    // Number methods
    if (object is num) {
      return _getNumberMethod(object, property);
    }

    throw ExpressionEvaluatorException(
      'Access of member `$property` not supported for objects of type `${object.runtimeType}`',
    );
  }
  
  dynamic _getMathProperty(_MathObject math, String property) {
    switch (property) {
      case 'E': return math.E;
      case 'PI': return math.PI;
      case 'LN2': return math.LN2;
      case 'LN10': return math.LN10;
      case 'LOG2E': return math.LOG2E;
      case 'LOG10E': return math.LOG10E;
      case 'SQRT2': return math.SQRT2;
      case 'SQRT1_2': return math.SQRT1_2;
      case 'abs': return math.abs;
      case 'acos': return math.acos;
      case 'asin': return math.asin;
      case 'atan': return math.atan;
      case 'atan2': return math.atan2;
      case 'ceil': return math.ceil;
      case 'cos': return math.cos;
      case 'exp': return math.exp;
      case 'floor': return math.floor;
      case 'log': return math.log;
      case 'max': return math.max;
      case 'min': return math.min;
      case 'pow': return math.pow;
      case 'random': return math.random;
      case 'round': return math.round;
      case 'sin': return math.sin;
      case 'sqrt': return math.sqrt;
      case 'tan': return math.tan;
      case 'sign': return math.sign;
      case 'trunc': return math.trunc;
      default:
        throw ExpressionEvaluatorException('Math property `$property` not supported');
    }
  }
  
  dynamic _getDateProperty(_DateObject date, String property) {
    switch (property) {
      case 'now': return date.now;
      case 'UTC': return date.UTC;
      case 'parse': return date.parse;
      case 'format': return date.format;
      default:
        throw ExpressionEvaluatorException('Date property `$property` not supported');
    }
  }

  dynamic _getStringMethod(String str, String method) {
    switch (method) {
      case 'length':
        return str.length;
      case 'toUpperCase':
        return () => str.toUpperCase();
      case 'toLowerCase':
        return () => str.toLowerCase();
      case 'substring':
        return (int start, [int? end]) => str.substring(start, end ?? str.length);
      case 'substr':
        return (int start, [int? length]) {
          if (length == null) return str.substring(start);
          return str.substring(start, (start + length).clamp(0, str.length));
        };
      case 'indexOf':
        return (String search, [int? start]) => str.indexOf(search, start ?? 0);
      case 'lastIndexOf':
        return (String search, [int? start]) => str.lastIndexOf(search, start);
      case 'includes':
        return (String search) => str.contains(search);
      case 'startsWith':
        return (String search, [int? position]) {
          final pos = position ?? 0;
          return str.substring(pos).startsWith(search);
        };
      case 'endsWith':
        return (String search) => str.endsWith(search);
      case 'trim':
        return () => str.trim();
      case 'split':
        return (String separator, [int? limit]) {
          final parts = str.split(separator);
          if (limit != null && limit < parts.length) {
            return parts.sublist(0, limit);
          }
          return parts;
        };
      case 'replace':
        return (String search, String replacement) => str.replaceFirst(search, replacement);
      case 'replaceAll':
        return (String search, String replacement) => str.replaceAll(search, replacement);
      case 'charCodeAt':
        return (int index) => index < str.length ? str.codeUnitAt(index) : double.nan;
      case 'charAt':
        return (int index) => index < str.length ? str[index] : '';
      default:
        throw ExpressionEvaluatorException('String method `$method` not supported');
    }
  }

  dynamic _getArrayMethod(List arr, String method) {
    switch (method) {
      case 'length':
        return arr.length;
      case 'push':
        return (dynamic item) {
          arr.add(item);
          return arr.length;
        };
      case 'pop':
        return () => arr.isNotEmpty ? arr.removeLast() : null;
      case 'shift':
        return () => arr.isNotEmpty ? arr.removeAt(0) : null;
      case 'unshift':
        return (dynamic item) {
          arr.insert(0, item);
          return arr.length;
        };
      case 'indexOf':
        return (dynamic item, [int? start]) => arr.indexOf(item, start ?? 0);
      case 'includes':
        return (dynamic item) => arr.contains(item);
      case 'slice':
        return ([int? start, int? end]) {
          final s = start ?? 0;
          final e = end ?? arr.length;
          return arr.sublist(s.clamp(0, arr.length), e.clamp(0, arr.length));
        };
      case 'join':
        return ([String? separator]) => arr.join(separator ?? ',');
      case 'reverse':
        return () => arr.reversed.toList();
      case 'sort':
        return ([Function? compareFn]) {
          if (compareFn != null) {
            arr.sort((a, b) => compareFn(a, b).toInt());
          } else {
            arr.sort();
          }
          return arr;
        };
      case 'filter':
        return (Function predicate) {
          final result = [];
          for (var i = 0; i < arr.length; i++) {
            if (predicate(arr[i], i, arr)) {
              result.add(arr[i]);
            }
          }
          return result;
        };
      case 'map':
        return (Function mapper) {
          final result = [];
          for (var i = 0; i < arr.length; i++) {
            result.add(mapper(arr[i], i, arr));
          }
          return result;
        };
      case 'reduce':
        return (Function reducer, [dynamic initialValue]) {
          var accumulator = initialValue;
          var startIndex = 0;
          
          if (initialValue == null && arr.isNotEmpty) {
            accumulator = arr[0];
            startIndex = 1;
          }
          
          for (var i = startIndex; i < arr.length; i++) {
            accumulator = reducer(accumulator, arr[i], i, arr);
          }
          return accumulator;
        };
      case 'find':
        return (Function predicate) {
          for (var i = 0; i < arr.length; i++) {
            if (predicate(arr[i], i, arr)) {
              return arr[i];
            }
          }
          return null;
        };
      case 'findIndex':
        return (Function predicate) {
          for (var i = 0; i < arr.length; i++) {
            if (predicate(arr[i], i, arr)) {
              return i;
            }
          }
          return -1;
        };
      case 'every':
        return (Function predicate) {
          for (var i = 0; i < arr.length; i++) {
            if (!predicate(arr[i], i, arr)) {
              return false;
            }
          }
          return true;
        };
      case 'some':
        return (Function predicate) {
          for (var i = 0; i < arr.length; i++) {
            if (predicate(arr[i], i, arr)) {
              return true;
            }
          }
          return false;
        };
      default:
        throw ExpressionEvaluatorException('Array method `$method` not supported');
    }
  }

  dynamic _getNumberMethod(num number, String method) {
    switch (method) {
      case 'toFixed':
        return ([int? fractionDigits]) => number.toStringAsFixed(fractionDigits ?? 0);
      case 'toPrecision':
        return ([int? precision]) => number.toStringAsPrecision(precision ?? number.toString().length);
      case 'toString':
        return ([int? radix]) => radix != null ? number.toInt().toRadixString(radix) : number.toString();
      default:
        throw ExpressionEvaluatorException('Number method `$method` not supported');
    }
  }

  // Type coercion helpers
  static int _parseInt(dynamic value, [int? radix]) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      try {
        return int.parse(value, radix: radix);
      } catch (_) {
        return 0;
      }
    }
    if (value is bool) return value ? 1 : 0;
    return 0;
  }

  static double _parseFloat(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (_) {
        return double.nan;
      }
    }
    if (value is bool) return value ? 1.0 : 0.0;
    return double.nan;
  }

  static bool _isNaN(dynamic value) {
    if (value is num) return value.isNaN;
    return true;
  }

  static bool _isFinite(dynamic value) {
    if (value is num) return value.isFinite;
    return false;
  }
}

/// Math object implementation
class _MathObject {
  double get E => math.e;
  double get PI => math.pi;
  double get LN2 => math.ln2;
  double get LN10 => math.ln10;
  double get LOG2E => math.log2e;
  double get LOG10E => math.log10e;
  double get SQRT2 => math.sqrt2;
  double get SQRT1_2 => math.sqrt1_2;

  double abs(num x) => x.abs().toDouble();
  double acos(num x) => math.acos(x);
  double asin(num x) => math.asin(x);
  double atan(num x) => math.atan(x);
  double atan2(num y, num x) => math.atan2(y, x);
  double ceil(num x) => x.ceilToDouble();
  double cos(num x) => math.cos(x);
  double exp(num x) => math.exp(x);
  double floor(num x) => x.floorToDouble();
  double log(num x) => math.log(x);
  double max(num a, [num? b, num? c, num? d, num? e]) {
    var result = a.toDouble();
    if (b != null) result = math.max(result, b.toDouble());
    if (c != null) result = math.max(result, c.toDouble());
    if (d != null) result = math.max(result, d.toDouble());
    if (e != null) result = math.max(result, e.toDouble());
    return result;
  }
  double min(num a, [num? b, num? c, num? d, num? e]) {
    var result = a.toDouble();
    if (b != null) result = math.min(result, b.toDouble());
    if (c != null) result = math.min(result, c.toDouble());
    if (d != null) result = math.min(result, d.toDouble());
    if (e != null) result = math.min(result, e.toDouble());
    return result;
  }
  double pow(num x, num y) => math.pow(x, y).toDouble();
  double random() => math.Random().nextDouble();
  double round(num x) => x.roundToDouble();
  double sin(num x) => math.sin(x);
  double sqrt(num x) => math.sqrt(x);
  double tan(num x) => math.tan(x);
  int sign(num x) => x.sign.toInt();
  double trunc(num x) => x.truncateToDouble();
}

/// Date object implementation  
class _DateObject {
  int Function() get now => () => DateTime.now().millisecondsSinceEpoch;
  
  Function get UTC => (int year, [int? month, int? day, int? hour, int? minute, int? second, int? millisecond]) {
    return DateTime.utc(
      year,
      month ?? 1,
      day ?? 1,
      hour ?? 0,
      minute ?? 0,
      second ?? 0,
      millisecond ?? 0,
    ).millisecondsSinceEpoch;
  };
  
  Function get parse => (String dateString) {
    try {
      return DateTime.parse(dateString).millisecondsSinceEpoch;
    } catch (_) {
      return double.nan;
    }
  };

  /// Format a timestamp (milliseconds since epoch) to ISO-8601 string
  Function get format => (dynamic timestamp) {
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String();
    }
    return timestamp.toString();
  };
}

/// JSON object implementation
class _JSONObject {
  String stringify(dynamic value, [dynamic replacer, dynamic space]) {
    // Simple implementation - doesn't support replacer/space
    return _jsonEncode(value);
  }

  dynamic parse(String text) {
    return _jsonDecode(text);
  }

  String _jsonEncode(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';
    if (value is List) {
      return '[${value.map(_jsonEncode).join(',')}]';
    }
    if (value is Map) {
      final entries = value.entries.map((e) => '"${e.key}":${_jsonEncode(e.value)}');
      return '{${entries.join(',')}}';
    }
    return '{}';
  }

  dynamic _jsonDecode(String text) {
    try {
      // Use Dart's built-in JSON decoder
      return jsonDecode(text);
    } catch (e) {
      throw Exception('Invalid JSON: $e');
    }
  }
}

/// Console object implementation using structured logging
class _ConsoleObject {
  static final Logger _logger = Logger('Console');

  void log(dynamic message) {
    _logger.info('[LOG] $message');
  }

  void error(dynamic message) {
    _logger.severe('[ERROR] $message');
  }

  void warn(dynamic message) {
    _logger.warning('[WARN] $message');
  }

  void info(dynamic message) {
    _logger.info('[INFO] $message');
  }
}