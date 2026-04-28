/// Flow runtime error definitions

import '../parser/validator.dart' show ValidationError;
export '../parser/validator.dart' show ValidationSeverity, ValidationError;


/// Base class for all flow runtime errors
abstract class FlowError implements Exception {
  final String code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  const FlowError(this.code, this.message, {this.cause, this.stackTrace});

  @override
  String toString() => '[$code] $message';
}

/// Concrete FlowError for general use cases
class ConcreteFlowError extends FlowError {
  const ConcreteFlowError(
    super.code,
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Error during flow parsing
class FlowParseError extends FlowError {
  final String? field;

  const FlowParseError(
    String message, {
    this.field,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('PARSE_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message${field != null ? ' (field: $field)' : ''}';
}

/// Error during flow validation
class FlowValidationError extends FlowError {
  final List<ValidationError> errors;

  const FlowValidationError(
    String message, {
    required this.errors,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('VALIDATION_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message (${errors.length} error(s))';
}

/// Error during process execution
class ProcessExecutionError extends FlowError {
  final String processId;
  final String? actionType;
  final int? stepIndex;

  const ProcessExecutionError(
    String message, {
    required this.processId,
    this.actionType,
    this.stepIndex,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('PROCESS_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message (process: $processId${stepIndex != null ? ', step: $stepIndex' : ''}${actionType != null ? ', action: $actionType' : ''})';
}

/// Error accessing hardware resources
class HardwareError extends FlowError {
  final String resourceId;
  final String resourceType;
  final int? errorCode;

  const HardwareError(
    String message, {
    required this.resourceId,
    required this.resourceType,
    this.errorCode,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('HARDWARE_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message (resource: $resourceType:$resourceId${errorCode != null ? ', errno: $errorCode' : ''})';
}

/// Error in state management
class FlowStateError extends FlowError {
  final String? variableName;

  const FlowStateError(
    String message, {
    this.variableName,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('STATE_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message${variableName != null ? ' (variable: $variableName)' : ''}';
}

/// Error in MCP communication
class McpError extends FlowError {
  final String? method;
  final int? mcpErrorCode;

  const McpError(
    String message, {
    this.method,
    this.mcpErrorCode,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('MCP_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message${method != null ? ' (method: $method)' : ''}${mcpErrorCode != null ? ' (mcpError: $mcpErrorCode)' : ''}';
}

/// Security/authorization error
class SecurityError extends FlowError {
  const SecurityError(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) : super('SECURITY_ERROR', message, cause: cause, stackTrace: stackTrace);
}

/// Resource limit exceeded error
class ResourceLimitError extends FlowError {
  final String resourceType;
  final int limit;
  final int requested;

  const ResourceLimitError(
    String message, {
    required this.resourceType,
    required this.limit,
    required this.requested,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('RESOURCE_LIMIT_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message (resource: $resourceType, limit: $limit, requested: $requested)';
}

/// Timeout error
class TimeoutError extends FlowError {
  final Duration timeout;
  final String operation;

  const TimeoutError(
    String message, {
    required this.timeout,
    required this.operation,
    Object? cause,
    StackTrace? stackTrace,
  }) : super('TIMEOUT_ERROR', message, cause: cause, stackTrace: stackTrace);

  @override
  String toString() => '[$code] $message (operation: $operation, timeout: ${timeout.inMilliseconds}ms)';
}
