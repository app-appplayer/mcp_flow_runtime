import 'dart:math' as math;
import 'package:expressions/expressions.dart';

import '../errors/flow_errors.dart';

/// Expression evaluator for MCP Flow DSL
class FlowExpressionEvaluator extends ExpressionEvaluator {
  FlowExpressionEvaluator();

  /// Current recursion depth tracker
  int _currentDepth = 0;

  /// Maximum expression string length (Spec 13-security: 1024)
  static const int maxExpressionLength = 1024;

  /// Maximum recursion depth (Spec 13-security: 10)
  static const int maxRecursionDepth = 10;

  /// Maximum evaluation time in milliseconds (SRS NFR-PERF-004: 10ms, within Spec's 100ms cap)
  static const int maxEvaluationTimeMs = 10;

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
  dynamic evalMemberExpression(
      MemberExpression expression, Map<String, dynamic> context) {
    final obj = eval(expression.object, context);
    final propertyName = expression.property.name;
    
    // Handle Map access
    if (obj is Map<String, dynamic>) {
      final value = obj[propertyName];
      // If the value is a function and this is part of a call expression,
      // the parent CallExpression will handle the invocation
      return value;
    }
    
    // Handle List/Array properties and methods
    if (obj is List) {
      switch (propertyName) {
        case 'length':
          return obj.length;
        case 'first':
          return obj.isEmpty ? null : obj.first;
        case 'last':
          return obj.isEmpty ? null : obj.last;
        case 'isEmpty':
          return obj.isEmpty;
        case 'isNotEmpty':
          return obj.isNotEmpty;
        case 'concat':
          // Return a function that can concatenate arrays
          return (dynamic other) {
            if (other is List) {
              return [...obj, ...other];
            } else {
              return [...obj, other];
            }
          };
        case 'push':
          // Return a function that adds element and returns new length
          return (dynamic item) {
            obj.add(item);
            return obj.length;
          };
        case 'pop':
          // Return a function that removes and returns last element
          return () => obj.isNotEmpty ? obj.removeLast() : null;
        case 'indexOf':
          // Return a function that finds index of element
          return (dynamic item) => obj.indexOf(item);
        case 'filter':
          // Return a function that filters array based on predicate
          return (dynamic predicate) {
            if (predicate is Function) {
              final result = <dynamic>[];
              for (int i = 0; i < obj.length; i++) {
                final item = obj[i];
                // Call predicate with item, index, array
                final keep = predicate(item, i, obj);
                if (keep == true || (keep is bool && keep)) {
                  result.add(item);
                }
              }
              return result;
            }
            throw ExpressionEvaluatorException('filter requires a function');
          };
        case 'map':
          // Return a function that maps array elements
          return (dynamic mapper) {
            if (mapper is Function) {
              final result = <dynamic>[];
              for (int i = 0; i < obj.length; i++) {
                // Call mapper with item, index, array
                result.add(mapper(obj[i], i, obj));
              }
              return result;
            }
            throw ExpressionEvaluatorException('map requires a function');
          };
        case 'reduce':
          // Return a function that reduces array to single value
          return (dynamic reducer, [dynamic initialValue]) {
            if (reducer is Function) {
              if (obj.isEmpty && initialValue == null) {
                throw ExpressionEvaluatorException('Reduce of empty array with no initial value');
              }
              
              var accumulator = initialValue;
              int startIndex = 0;
              
              if (initialValue == null) {
                accumulator = obj[0];
                startIndex = 1;
              }
              
              for (int i = startIndex; i < obj.length; i++) {
                // Call reducer with accumulator, currentValue, index, array
                accumulator = reducer(accumulator, obj[i], i, obj);
              }
              
              return accumulator;
            }
            throw ExpressionEvaluatorException('reduce requires a function');
          };
        case 'find':
          // Return a function that finds first element matching predicate
          return (dynamic predicate) {
            if (predicate is Function) {
              for (int i = 0; i < obj.length; i++) {
                if (predicate(obj[i], i, obj) == true) {
                  return obj[i];
                }
              }
              return null;
            }
            throw ExpressionEvaluatorException('find requires a function');
          };
        case 'findIndex':
          // Return a function that finds index of first element matching predicate
          return (dynamic predicate) {
            if (predicate is Function) {
              for (int i = 0; i < obj.length; i++) {
                if (predicate(obj[i], i, obj) == true) {
                  return i;
                }
              }
              return -1;
            }
            throw ExpressionEvaluatorException('findIndex requires a function');
          };
        case 'some':
          // Return a function that tests if any element matches predicate
          return (dynamic predicate) {
            if (predicate is Function) {
              for (int i = 0; i < obj.length; i++) {
                if (predicate(obj[i], i, obj) == true) {
                  return true;
                }
              }
              return false;
            }
            throw ExpressionEvaluatorException('some requires a function');
          };
        case 'every':
          // Return a function that tests if all elements match predicate
          return (dynamic predicate) {
            if (predicate is Function) {
              for (int i = 0; i < obj.length; i++) {
                if (predicate(obj[i], i, obj) != true) {
                  return false;
                }
              }
              return true;
            }
            throw ExpressionEvaluatorException('every requires a function');
          };
        case 'includes':
          // Return a function that checks if array contains element
          return (dynamic item) => obj.contains(item);
        case 'reverse':
          // Return a function that reverses the array
          return () => obj.reversed.toList();
        case 'sort':
          // Return a function that sorts the array
          return ([dynamic compareFn]) {
            final copy = List.from(obj);
            if (compareFn != null && compareFn is Function) {
              copy.sort((a, b) {
                final result = compareFn(a, b);
                if (result is num) {
                  return result.toInt();
                }
                return 0;
              });
            } else {
              copy.sort();
            }
            return copy;
          };
        case 'slice':
          // Return a function that returns a shallow copy of a portion of array
          return ([int? start, int? end]) {
            start ??= 0;
            if (start < 0) start = obj.length + start;
            if (start < 0) start = 0;
            if (start > obj.length) start = obj.length;
            
            end ??= obj.length;
            if (end < 0) end = obj.length + end;
            if (end < 0) end = 0;
            if (end > obj.length) end = obj.length;
            
            if (start >= end) return [];
            return obj.sublist(start, end);
          };
        case 'join':
          // Return a function that joins array elements into string
          return ([String? separator]) {
            separator ??= ',';
            return obj.join(separator);
          };
        default:
          // Allow numeric index access
          final index = int.tryParse(propertyName);
          if (index != null && index >= 0 && index < obj.length) {
            return obj[index];
          }
      }
    }
    
    // Handle String properties and methods
    if (obj is String) {
      switch (propertyName) {
        case 'length':
          return obj.length;
        case 'isEmpty':
          return obj.isEmpty;
        case 'isNotEmpty':
          return obj.isNotEmpty;
        case 'toUpperCase':
          return () => obj.toUpperCase();
        case 'toLowerCase':
          return () => obj.toLowerCase();
        case 'trim':
          return () => obj.trim();
        case 'substring':
          return (int start, [int? end]) {
            if (end != null) {
              return obj.substring(start, end);
            }
            return obj.substring(start);
          };
        case 'indexOf':
          return (String search, [int? start]) => obj.indexOf(search, start ?? 0);
        case 'lastIndexOf':
          return (String search, [int? start]) => obj.lastIndexOf(search, start);
        case 'startsWith':
          return (String search) => obj.startsWith(search);
        case 'endsWith':
          return (String search) => obj.endsWith(search);
        case 'split':
          return (String separator) => obj.split(separator);
        case 'replace':
          return (String from, String to) => obj.replaceAll(from, to);
        case 'replaceFirst':
          return (String from, String to) => obj.replaceFirst(from, to);
        case 'contains':
          return (String search) => obj.contains(search);
        case 'charAt':
          return (int index) => index >= 0 && index < obj.length ? obj[index] : '';
        default:
          // Allow numeric index access
          final index = int.tryParse(propertyName);
          if (index != null && index >= 0 && index < obj.length) {
            return obj[index];
          }
      }
    }
    
    throw ExpressionEvaluatorException(
      'Cannot access member $propertyName on ${obj.runtimeType}',
    );
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
    // Add built-in functions to context as per spec section 8.4
    // Note: User variables should override built-in functions
    final enhancedContext = <String, dynamic>{
      // Math functions
      'abs': (num x) => x.abs(),
      'pow': (num base, num exponent) => math.pow(base, exponent),
      'sqrt': (num x) => math.sqrt(x),
      'min': (dynamic a, [dynamic b, dynamic c, dynamic d, dynamic e]) {
        // Handle array as first argument
        if (a is List) {
          if (a.isEmpty) return 0;
          num result = a[0] is num ? a[0] : 0;
          for (var item in a) {
            if (item is num && item < result) {
              result = item;
            }
          }
          return result;
        }
        // Handle individual numbers
        num result = a is num ? a : 0;
        if (b != null && b is num) result = math.min(result, b);
        if (c != null && c is num) result = math.min(result, c);
        if (d != null && d is num) result = math.min(result, d);
        if (e != null && e is num) result = math.min(result, e);
        return result;
      },
      'max': (dynamic a, [dynamic b, dynamic c, dynamic d, dynamic e]) {
        // Handle array as first argument
        if (a is List) {
          if (a.isEmpty) return 0;
          num result = a[0] is num ? a[0] : 0;
          for (var item in a) {
            if (item is num && item > result) {
              result = item;
            }
          }
          return result;
        }
        // Handle individual numbers
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
      'clamp': (num value, num min, num max) => value.clamp(min, max),
      
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
      
      // Array operations
      'length': (List arr) => arr.length,
      'sum': (List arr) {
        num result = 0;
        for (var item in arr) {
          if (item is num) result += item;
        }
        return result;
      },
      'avg': (List arr) {
        if (arr.isEmpty) return 0;
        num sum = 0;
        int count = 0;
        for (var item in arr) {
          if (item is num) {
            sum += item;
            count++;
          }
        }
        return count > 0 ? sum / count : 0;
      },
      'first': (List arr) => arr.isEmpty ? null : arr.first,
      'last': (List arr) => arr.isEmpty ? null : arr.last,
      'append': (List arr, dynamic item) => [...arr, item],
      'filter': (List arr, Function predicate) {
        final result = <dynamic>[];
        for (int i = 0; i < arr.length; i++) {
          if (predicate(arr[i], i, arr) == true) {
            result.add(arr[i]);
          }
        }
        return result;
      },
      'map': (List arr, Function mapper) {
        final result = <dynamic>[];
        for (int i = 0; i < arr.length; i++) {
          result.add(mapper(arr[i], i, arr));
        }
        return result;
      },
      'reduce': (List arr, Function reducer, [dynamic initialValue]) {
        if (arr.isEmpty && initialValue == null) {
          throw ExpressionEvaluatorException('Reduce of empty array with no initial value');
        }
        
        var accumulator = initialValue;
        int startIndex = 0;
        
        if (initialValue == null) {
          accumulator = arr[0];
          startIndex = 1;
        }
        
        for (int i = startIndex; i < arr.length; i++) {
          accumulator = reducer(accumulator, arr[i], i, arr);
        }
        
        return accumulator;
      },
      
      // String operations
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
      'upper': (String str) => str.toUpperCase(),
      'lower': (String str) => str.toLowerCase(),
      'trim': (String str) => str.trim(),
      'split': (String str, String delimiter) => str.split(delimiter),
      
      // Type checking
      'typeof': (dynamic value) {
        if (value == null) return 'null';
        if (value is bool) return 'boolean';
        if (value is int || value is double) return 'number';
        if (value is String) return 'string';
        if (value is List) return 'array';
        if (value is Map) return 'object';
        return 'unknown';
      },
      
      // Bit operations
      'setBit': (int value, int bit) => value | (1 << bit),
      'clearBit': (int value, int bit) => value & ~(1 << bit),
      'toggleBit': (int value, int bit) => value ^ (1 << bit),
      'testBit': (int value, int bit) => (value & (1 << bit)) != 0,
      
      // Bitwise shift operations (for preprocessed expressions)
      '_lshift': (dynamic a, dynamic b) {
        final left = a is int ? a : 
                     a is double ? a.toInt() : 
                     a is bool ? (a ? 1 : 0) :
                     int.tryParse(a.toString()) ?? 0;
        final right = b is int ? b : 
                      b is double ? b.toInt() : 
                      b is bool ? (b ? 1 : 0) :
                      int.tryParse(b.toString()) ?? 0;
        return left << right;
      },
      '_rshift': (dynamic a, dynamic b) {
        final left = a is int ? a : 
                     a is double ? a.toInt() : 
                     a is bool ? (a ? 1 : 0) :
                     int.tryParse(a.toString()) ?? 0;
        final right = b is int ? b : 
                      b is double ? b.toInt() : 
                      b is bool ? (b ? 1 : 0) :
                      int.tryParse(b.toString()) ?? 0;
        return left >> right;
      },
      
      // Date/Time functions
      'now': () => DateTime.now().millisecondsSinceEpoch,
      'Date': {
        'now': () => DateTime.now().millisecondsSinceEpoch,
      },
      'Math': {
        'pow': (num base, num exponent) => math.pow(base, exponent),
        'sqrt': (num x) => math.sqrt(x),
        'abs': (num x) => x.abs(),
        'min': (num a, num b) => math.min(a, b),
        'max': (num a, num b) => math.max(a, b),
        'round': (num x) => x.round(),
        'floor': (num x) => x.floor(),
        'ceil': (num x) => x.ceil(),
        'random': () => math.Random().nextDouble(),
      },
      
      // Object functions
      'Object': {
        'keys': (dynamic obj) {
          if (obj is Map) {
            return obj.keys.toList();
          }
          return [];
        },
        'values': (dynamic obj) {
          if (obj is Map) {
            return obj.values.toList();
          }
          return [];
        },
        'entries': (dynamic obj) {
          if (obj is Map) {
            return obj.entries.map((e) => [e.key, e.value]).toList();
          }
          return [];
        },
      },
      
      // Standard values
      'true': true,
      'false': false,
      'null': null,
      
      // User context variables override built-ins
      ...context,
    };

    // Evaluate with enhanced context
    return _evaluateWithTypeCoercion(expression, enhancedContext);
  }

  dynamic _evaluateWithTypeCoercion(Expression expression, Map<String, dynamic> context) {
    try {
      // Handle unary operations
      if (expression is UnaryExpression) {
        return _handleUnaryExpression(expression, context);
      }
      // Handle binary operations with type coercion
      if (expression is BinaryExpression) {
        return _handleBinaryExpression(expression, context);
      }
      return super.eval(expression, context);
    } catch (e) {
      rethrow;
    }
  }

  dynamic _handleBinaryExpression(BinaryExpression expr, Map<String, dynamic> context) {
    // Handle logical operators with short-circuit evaluation
    switch (expr.operator) {
      case '||':
        final left = eval(expr.left, context);
        if (_toBool(left)) return left; // Return truthy left value
        return eval(expr.right, context); // Return right value (truthy or not)
      case '&&':
        final left = eval(expr.left, context);
        if (!_toBool(left)) return left; // Return falsy left value
        return eval(expr.right, context); // Return right value
    }
    
    // For other operators, evaluate both sides first
    final left = eval(expr.left, context);
    final right = eval(expr.right, context);
    
    switch (expr.operator) {
      case '+':
        // String concatenation takes priority if either operand is a String
        if (left is String || right is String) {
          return '${left ?? ""}${right ?? ""}';
        }
        // Numeric addition for non-string operands
        return _toNumber(left) + _toNumber(right);
      case '-':
        return _toNumber(left) - _toNumber(right);
      case '*':
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

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
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
  
  dynamic _handleUnaryExpression(UnaryExpression expr, Map<String, dynamic> context) {
    final operand = eval(expr.argument, context);
    
    switch (expr.operator) {
      case '!':
        return !_toBool(operand);
      case '-':
        return -_toNumber(operand);
      case '+':
        return _toNumber(operand);
      case '~':
        // Bitwise NOT operator
        return ~_toInt(operand);
      default:
        throw ExpressionEvaluatorException(
          'Unknown unary operator: ${expr.operator}',
        );
    }
  }
}