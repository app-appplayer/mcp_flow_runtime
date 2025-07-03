/// Flow runtime error definitions

/// Base class for all flow runtime errors
class FlowError implements Exception {
  final String message;
  final dynamic cause;
  final StackTrace? stackTrace;

  const FlowError(this.message, {this.cause, this.stackTrace});

  @override
  String toString() => 'FlowError: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

/// Error during flow parsing
class FlowParseError extends FlowError {
  const FlowParseError(super.message, {super.cause, super.stackTrace});

  @override
  String toString() => 'FlowParseError: $message';
}

/// Error during flow validation
class FlowValidationError extends FlowError {
  final String field;
  final dynamic value;

  const FlowValidationError(
    super.message, {
    required this.field,
    this.value,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'FlowValidationError: $field - $message';
}

/// Error during process execution
class ProcessExecutionError extends FlowError {
  final String processId;
  final String? actionType;

  const ProcessExecutionError(
    super.message, {
    required this.processId,
    this.actionType,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'ProcessExecutionError[$processId${actionType != null ? ':$actionType' : ''}]: $message';
}

/// Error accessing hardware resources
class HardwareError extends FlowError {
  final String resourceId;
  final String resourceType;

  const HardwareError(
    super.message, {
    required this.resourceId,
    required this.resourceType,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'HardwareError[$resourceType:$resourceId]: $message';
}

/// Error in state management
class StateError extends FlowError {
  final String stateVariable;

  const StateError(
    super.message, {
    required this.stateVariable,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'StateError[$stateVariable]: $message';
}

/// Error in MCP communication
class McpError extends FlowError {
  final String? toolName;
  final String? resourceUri;

  const McpError(
    super.message, {
    this.toolName,
    this.resourceUri,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'McpError${toolName != null ? '[$toolName]' : ''}${resourceUri != null ? '[$resourceUri]' : ''}: $message';
}

/// Security/authorization error
class SecurityError extends FlowError {
  final String? action;
  final String? resource;

  const SecurityError(
    super.message, {
    this.action,
    this.resource,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'SecurityError${action != null ? '[action=$action]' : ''}${resource != null ? '[resource=$resource]' : ''}: $message';
}

/// Resource limit exceeded error
class ResourceLimitError extends FlowError {
  final String resourceType;
  final int limit;
  final int requested;

  const ResourceLimitError(
    super.message, {
    required this.resourceType,
    required this.limit,
    required this.requested,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'ResourceLimitError[$resourceType]: $message (limit: $limit, requested: $requested)';
}

/// Timeout error
class TimeoutError extends FlowError {
  final Duration timeout;
  final String operation;

  const TimeoutError(
    super.message, {
    required this.timeout,
    required this.operation,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'TimeoutError[$operation]: $message (timeout: ${timeout.inMilliseconds}ms)';
}