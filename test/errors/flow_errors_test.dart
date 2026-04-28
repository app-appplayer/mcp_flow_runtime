import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';

// Helper to create a ConcreteFlowError for base-class testing
ConcreteFlowError makeError({
  String code = 'TEST_ERROR',
  String message = 'test message',
  Object? cause,
  StackTrace? stackTrace,
}) {
  return ConcreteFlowError(code, message, cause: cause, stackTrace: stackTrace);
}

// Sample ValidationError entries for FlowValidationError tests
final sampleValidationErrors = [
  ValidationError(
    code: 'ID_DUPLICATE',
    message: 'Duplicate process id',
    path: 'processes[1].id',
    severity: ValidationSeverity.error,
  ),
  ValidationError(
    code: 'MISSING_FIELD',
    message: 'Missing trigger',
    path: 'processes[0].trigger',
    severity: ValidationSeverity.warning,
    value: null,
  ),
];

void main() {
  // ============================================================
  // 2. FlowError base tests (TC-E001 ~ TC-E002)
  // ============================================================
  group('FlowError base', () {
    test('TC-E001a: FlowError.toString returns [code] message format', () {
      final error = ConcreteFlowError('TEST_ERROR', 'something failed');
      expect(error.toString(), contains('[TEST_ERROR]'));
      expect(error.toString(), contains('something failed'));
    });

    test('TC-E001b: FlowError.toString with empty message', () {
      final error = ConcreteFlowError('TEST_ERROR', '');
      expect(error.toString(), contains('[TEST_ERROR]'));
      // Should not throw
      error.toString();
    });

    test('TC-E001c: FlowError.cause stores the original exception', () {
      final cause = FormatException('bad json');
      final error = ConcreteFlowError('TEST_ERROR', 'wrap', cause: cause);
      expect(error.cause, isA<FormatException>());
    });

    test('TC-E002a: FlowError.stackTrace stores provided stack trace', () {
      final st = StackTrace.current;
      final error = makeError(stackTrace: st);
      expect(error.stackTrace, isNotNull);
    });

    test('TC-E002b: FlowError.stackTrace defaults to null', () {
      final error = makeError();
      expect(error.stackTrace, isNull);
    });

    test('TC-E002c: FlowError implements Exception', () {
      final error = ConcreteFlowError('C', 'M');
      expect(error, isA<Exception>());
    });
  });

  // ============================================================
  // 3. FlowParseError tests (TC-E011 ~ TC-E012)
  // ============================================================
  group('FlowParseError', () {
    test('TC-E011a: FlowParseError has PARSE_ERROR code', () {
      final error = FlowParseError('invalid field', field: 'processes');
      expect(error.code, equals('PARSE_ERROR'));
    });

    test('TC-E011b: FlowParseError stores field', () {
      final error = FlowParseError('invalid field', field: 'processes');
      expect(error.field, equals('processes'));
    });

    test('TC-E011c: FlowParseError field defaults to null', () {
      final error = FlowParseError('invalid field');
      expect(error.field, isNull);
    });

    test('TC-E012a: FlowParseError is FlowError', () {
      final error = FlowParseError('M');
      expect(error, isA<FlowError>());
    });

    test('TC-E012b: FlowParseError toString contains code and message', () {
      final error = FlowParseError('bad value', field: 'resources.led');
      expect(error.toString(), contains('PARSE_ERROR'));
      expect(error.toString(), contains('bad value'));
    });

    test('TC-E012c: FlowParseError cause propagation', () {
      final error = FlowParseError('M', cause: FormatException('x'));
      expect(error.cause, isA<FormatException>());
    });
  });

  // ============================================================
  // 4. FlowValidationError tests (TC-E021 ~ TC-E022)
  // ============================================================
  group('FlowValidationError', () {
    test('TC-E021a: FlowValidationError stores multiple validation errors', () {
      final error = FlowValidationError('validation failed',
          errors: sampleValidationErrors);
      expect(error.code, equals('VALIDATION_ERROR'));
      expect(error.errors.length, equals(2));
    });

    test('TC-E021b: FlowValidationError with empty error list', () {
      final error = FlowValidationError('validation failed', errors: []);
      expect(error.errors.isEmpty, isTrue);
    });

    test('TC-E021c: FlowValidationError is FlowError', () {
      final error = FlowValidationError('M', errors: []);
      expect(error, isA<FlowError>());
    });

    test('TC-E022a: FlowValidationError code is VALIDATION_ERROR', () {
      final error = FlowValidationError('M', errors: []);
      expect(error.code, equals('VALIDATION_ERROR'));
    });

    test('TC-E022b: FlowValidationError errors contain correct path', () {
      final error = FlowValidationError('M', errors: sampleValidationErrors);
      expect(error.errors[0].path, equals('processes[1].id'));
    });

    test('TC-E022c: FlowValidationError errors contain correct severity', () {
      final error = FlowValidationError('M', errors: sampleValidationErrors);
      expect(error.errors[0].severity, equals(ValidationSeverity.error));
      expect(error.errors[1].severity, equals(ValidationSeverity.warning));
    });
  });

  // ============================================================
  // 5. ProcessExecutionError tests (TC-E031 ~ TC-E032)
  // ============================================================
  group('ProcessExecutionError', () {
    test(
        'TC-E031a: ProcessExecutionError stores processId, actionType, stepIndex',
        () {
      final error = ProcessExecutionError(
        'step failed',
        processId: 'proc_1',
        actionType: 'gpio.write',
        stepIndex: 3,
      );
      expect(error.code, equals('PROCESS_ERROR'));
      expect(error.processId, equals('proc_1'));
      expect(error.actionType, equals('gpio.write'));
      expect(error.stepIndex, equals(3));
    });

    test('TC-E031b: ProcessExecutionError stepIndex defaults to null', () {
      final error =
          ProcessExecutionError('step failed', processId: 'proc_1');
      expect(error.stepIndex, isNull);
    });

    test('TC-E031c: ProcessExecutionError actionType defaults to null', () {
      final error =
          ProcessExecutionError('step failed', processId: 'proc_1');
      expect(error.actionType, isNull);
    });

    test('TC-E032a: ProcessExecutionError is FlowError', () {
      final error =
          ProcessExecutionError('M', processId: 'p');
      expect(error, isA<FlowError>());
    });

    test('TC-E032b: ProcessExecutionError toString contains processId', () {
      final error = ProcessExecutionError('step failed',
          processId: 'proc_1');
      final str = error.toString();
      expect(str, contains('PROCESS_ERROR'));
      expect(str, contains('proc_1'));
    });

    test('TC-E032c: ProcessExecutionError cause propagation', () {
      final error = ProcessExecutionError('M',
          processId: 'p', cause: StateError('bad state'));
      expect(error.cause, isA<StateError>());
    });
  });

  // ============================================================
  // 6. HardwareError tests (TC-E041 ~ TC-E042)
  // ============================================================
  group('HardwareError', () {
    test('TC-E041a: HardwareError stores resource info and errorCode', () {
      final error = HardwareError(
        'GPIO write failed',
        resourceId: 'led',
        resourceType: 'gpio',
        errorCode: 5,
      );
      expect(error.code, equals('HARDWARE_ERROR'));
      expect(error.resourceId, equals('led'));
      expect(error.resourceType, equals('gpio'));
      expect(error.errorCode, equals(5));
    });

    test('TC-E041b: HardwareError errorCode defaults to null', () {
      final error = HardwareError('M',
          resourceId: 'led', resourceType: 'gpio');
      expect(error.errorCode, isNull);
    });

    test('TC-E041c: HardwareError is FlowError', () {
      final error = HardwareError('M',
          resourceId: 'x', resourceType: 'gpio');
      expect(error, isA<FlowError>());
    });

    test('TC-E042a: HardwareError toString contains resourceId and resourceType',
        () {
      final error = HardwareError('GPIO write failed',
          resourceId: 'led', resourceType: 'gpio');
      final str = error.toString();
      expect(str, contains('HARDWARE_ERROR'));
      expect(str, contains('led'));
      expect(str, contains('gpio'));
    });

    test('TC-E042b: HardwareError stores various resourceTypes', () {
      for (final rt in ['i2c', 'spi', 'uart', 'adc']) {
        final error =
            HardwareError('M', resourceId: 'r', resourceType: rt);
        expect(error.resourceType, equals(rt));
      }
    });

    test('TC-E042c: HardwareError cause propagation', () {
      final error = HardwareError('M',
          resourceId: 'r',
          resourceType: 'gpio',
          cause: Exception('permission denied'));
      expect(error.cause, isA<Exception>());
    });
  });

  // ============================================================
  // 7. FlowStateError tests (TC-E051)
  // ============================================================
  group('FlowStateError', () {
    test('TC-E051a: FlowStateError stores variableName', () {
      final error =
          FlowStateError('undefined variable', variableName: 'temperature');
      expect(error.code, equals('STATE_ERROR'));
      expect(error.variableName, equals('temperature'));
    });

    test('TC-E051b: FlowStateError variableName defaults to null', () {
      final error = FlowStateError('undefined variable');
      expect(error.variableName, isNull);
    });

    test('TC-E051c: FlowStateError is FlowError', () {
      final error = FlowStateError('M');
      expect(error, isA<FlowError>());
    });
  });

  // ============================================================
  // 8. McpError tests (TC-E061 ~ TC-E062)
  // ============================================================
  group('McpError', () {
    test('TC-E061a: McpError stores method and mcpErrorCode', () {
      final error = McpError(
        'method not found',
        method: 'tools/call',
        mcpErrorCode: -32601,
      );
      expect(error.code, equals('MCP_ERROR'));
      expect(error.method, equals('tools/call'));
      expect(error.mcpErrorCode, equals(-32601));
    });

    test('TC-E061b: McpError method defaults to null', () {
      final error = McpError('M');
      expect(error.method, isNull);
    });

    test('TC-E061c: McpError mcpErrorCode defaults to null', () {
      final error = McpError('M');
      expect(error.mcpErrorCode, isNull);
    });

    test('TC-E062a: McpError is FlowError', () {
      final error = McpError('M');
      expect(error, isA<FlowError>());
    });
  });

  // ============================================================
  // 9. SecurityError tests (TC-E071)
  // ============================================================
  group('SecurityError', () {
    test('TC-E071a: SecurityError stores code and message', () {
      final error = SecurityError('unauthorized access');
      expect(error.code, equals('SECURITY_ERROR'));
      expect(error.message, equals('unauthorized access'));
    });

    test('TC-E071b: SecurityError has no extra context fields', () {
      // SecurityError only has code, message, cause, stackTrace from FlowError
      final error = SecurityError('M', cause: Exception('x'));
      expect(error.code, equals('SECURITY_ERROR'));
      expect(error.message, equals('M'));
      expect(error.cause, isA<Exception>());
    });

    test('TC-E071c: SecurityError is FlowError', () {
      final error = SecurityError('M');
      expect(error, isA<FlowError>());
    });
  });

  // ============================================================
  // 10. ResourceLimitError tests (TC-E081 ~ TC-E082)
  // ============================================================
  group('ResourceLimitError', () {
    test('TC-E081a: ResourceLimitError stores limit and requested count', () {
      final error = ResourceLimitError(
        'too many processes',
        resourceType: 'process',
        limit: 10,
        requested: 11,
      );
      expect(error.code, equals('RESOURCE_LIMIT_ERROR'));
      expect(error.resourceType, equals('process'));
      expect(error.limit, equals(10));
      expect(error.requested, equals(11));
    });

    test('TC-E081b: ResourceLimitError boundary when limit equals requested',
        () {
      final error = ResourceLimitError(
        'at limit',
        resourceType: 'process',
        limit: 5,
        requested: 5,
      );
      // Object creation should succeed
      expect(error.limit, equals(5));
      expect(error.requested, equals(5));
    });

    test('TC-E081c: ResourceLimitError is FlowError', () {
      final error = ResourceLimitError('M',
          resourceType: 'r', limit: 1, requested: 2);
      expect(error, isA<FlowError>());
    });

    test('TC-E082a: ResourceLimitError toString contains limit and requested',
        () {
      final error = ResourceLimitError('too many',
          resourceType: 'process', limit: 10, requested: 11);
      final str = error.toString();
      expect(str, contains('RESOURCE_LIMIT_ERROR'));
      expect(str, contains('10'));
      expect(str, contains('11'));
    });
  });

  // ============================================================
  // 11. TimeoutError tests (TC-E091 ~ TC-E092)
  // ============================================================
  group('TimeoutError', () {
    test('TC-E091a: TimeoutError stores timeout duration and operation', () {
      final error = TimeoutError(
        'process timed out',
        timeout: Duration(seconds: 30),
        operation: 'process.execute',
      );
      expect(error.code, equals('TIMEOUT_ERROR'));
      expect(error.timeout, equals(Duration(seconds: 30)));
      expect(error.operation, equals('process.execute'));
    });

    test('TC-E091b: TimeoutError with Duration.zero', () {
      final error = TimeoutError('M',
          timeout: Duration.zero, operation: 'op');
      expect(error.timeout, equals(Duration.zero));
    });

    test('TC-E091c: TimeoutError is FlowError', () {
      final error = TimeoutError('M',
          timeout: Duration(seconds: 1), operation: 'op');
      expect(error, isA<FlowError>());
    });

    test('TC-E092a: TimeoutError toString contains operation', () {
      final error = TimeoutError('timed out',
          timeout: Duration(seconds: 5), operation: 'process.execute');
      final str = error.toString();
      expect(str, contains('TIMEOUT_ERROR'));
      expect(str, contains('process.execute'));
    });
  });

  // ============================================================
  // 12. ConcreteFlowError tests (TC-E101)
  // ============================================================
  group('ConcreteFlowError', () {
    test('TC-E101a: ConcreteFlowError accepts caller-defined code', () {
      final error = ConcreteFlowError('CUSTOM_CODE', 'custom message');
      expect(error.code, equals('CUSTOM_CODE'));
      expect(error.message, equals('custom message'));
    });

    test('TC-E101b: ConcreteFlowError is FlowError', () {
      final error = ConcreteFlowError('C', 'M');
      expect(error, isA<FlowError>());
    });

    test('TC-E101c: ConcreteFlowError propagates cause and stackTrace', () {
      final st = StackTrace.current;
      final error = ConcreteFlowError('C', 'M',
          cause: Exception('x'), stackTrace: st);
      expect(error.cause, isNotNull);
      expect(error.stackTrace, isNotNull);
    });
  });

  // ============================================================
  // 13. ValidationError / ValidationSeverity tests (TC-E111 ~ TC-E112)
  // ============================================================
  group('ValidationError / ValidationSeverity', () {
    test('TC-E111a: ValidationError stores all fields', () {
      final ve = ValidationError(
        code: 'ID_DUPLICATE',
        message: 'dup',
        path: 'processes[0].id',
        severity: ValidationSeverity.error,
        value: 'proc_1',
      );
      expect(ve.code, equals('ID_DUPLICATE'));
      expect(ve.message, equals('dup'));
      expect(ve.path, equals('processes[0].id'));
      expect(ve.severity, equals(ValidationSeverity.error));
      expect(ve.value, equals('proc_1'));
    });

    test('TC-E111b: ValidationError path defaults to null', () {
      final ve = ValidationError(code: 'C', message: 'M');
      expect(ve.path, isNull);
    });

    test('TC-E111c: ValidationError value defaults to null', () {
      final ve = ValidationError(code: 'C', message: 'M');
      expect(ve.value, isNull);
    });

    test('TC-E112a: ValidationSeverity.error exists', () {
      expect(ValidationSeverity.error, isNotNull);
    });

    test('TC-E112b: ValidationSeverity.warning exists', () {
      expect(ValidationSeverity.warning, isNotNull);
    });

    test('TC-E112c: ValidationSeverity has exactly 2 values', () {
      expect(ValidationSeverity.values.length, equals(2));
    });
  });

  // ============================================================
  // 14. Hierarchy and integration tests (TC-E121 ~ TC-E122)
  // ============================================================
  group('Hierarchy and integration', () {
    test('TC-E121a: all FlowError subclasses are instances of FlowError', () {
      final errors = <FlowError>[
        ConcreteFlowError('C', 'M'),
        FlowParseError('M'),
        FlowValidationError('M', errors: []),
        ProcessExecutionError('M', processId: 'p'),
        HardwareError('M', resourceId: 'r', resourceType: 'gpio'),
        FlowStateError('M'),
        McpError('M'),
        SecurityError('M'),
        ResourceLimitError('M', resourceType: 'r', limit: 1, requested: 2),
        TimeoutError('M', timeout: Duration(seconds: 1), operation: 'op'),
      ];
      for (final e in errors) {
        expect(e, isA<FlowError>());
        expect(e, isA<Exception>());
      }
    });

    test('TC-E121b: all FlowError subclasses implement Exception', () {
      final errors = <FlowError>[
        ConcreteFlowError('C', 'M'),
        FlowParseError('M'),
        FlowValidationError('M', errors: []),
        ProcessExecutionError('M', processId: 'p'),
        HardwareError('M', resourceId: 'r', resourceType: 'gpio'),
        FlowStateError('M'),
        McpError('M'),
        SecurityError('M'),
        ResourceLimitError('M', resourceType: 'r', limit: 1, requested: 2),
        TimeoutError('M', timeout: Duration(seconds: 1), operation: 'op'),
      ];
      for (final e in errors) {
        expect(e, isA<Exception>());
      }
    });

    test('TC-E121c: catch FlowError captures all subclasses', () {
      final errors = <Object>[
        FlowParseError('M'),
        HardwareError('M', resourceId: 'r', resourceType: 'gpio'),
        TimeoutError('M', timeout: Duration(seconds: 1), operation: 'op'),
      ];
      for (final e in errors) {
        var caught = false;
        try {
          throw e;
        } on FlowError {
          caught = true;
        }
        expect(caught, isTrue);
      }
    });

    test('TC-E122a: each subclass has a unique error code', () {
      final codes = <String>{
        FlowParseError('M').code,
        FlowValidationError('M', errors: []).code,
        ProcessExecutionError('M', processId: 'p').code,
        HardwareError('M', resourceId: 'r', resourceType: 'gpio').code,
        FlowStateError('M').code,
        McpError('M').code,
        SecurityError('M').code,
        ResourceLimitError('M', resourceType: 'r', limit: 1, requested: 2)
            .code,
        TimeoutError('M', timeout: Duration(seconds: 1), operation: 'op').code,
      };
      expect(codes.length, equals(9));
    });

    test(
        'TC-E122b: catching specific subclass does not catch other subclasses',
        () {
      var caughtParse = false;
      var caughtGeneric = false;
      try {
        throw HardwareError('M', resourceId: 'r', resourceType: 'gpio');
      } on FlowParseError {
        caughtParse = true;
      } on FlowError {
        caughtGeneric = true;
      }
      expect(caughtParse, isFalse);
      expect(caughtGeneric, isTrue);
    });

    test('TC-E122c: all subclass toString outputs contain their error code',
        () {
      final errors = <FlowError>[
        FlowParseError('M'),
        FlowValidationError('M', errors: []),
        ProcessExecutionError('M', processId: 'p'),
        HardwareError('M', resourceId: 'r', resourceType: 'gpio'),
        FlowStateError('M'),
        McpError('M'),
        SecurityError('M'),
        ResourceLimitError('M', resourceType: 'r', limit: 1, requested: 2),
        TimeoutError('M', timeout: Duration(seconds: 1), operation: 'op'),
      ];
      for (final e in errors) {
        expect(e.toString(), contains(e.code));
      }
    });
  });
}
