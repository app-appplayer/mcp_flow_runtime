/// Runtime-related type definitions

import 'dart:async';

import 'flow_types.dart';

/// Runtime states
enum RuntimeStatus {
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// Runtime configuration
class RuntimeConfig {
  final int maxProcesses;
  final int maxMemoryMB;
  final int maxCpuPercent;
  final int tickRateMs;
  final int maxIOOperationsPerSecond;
  final int maxNetworkConnections;
  final ErrorHandlingPolicy errorHandling;
  final SecurityPolicy? security;

  const RuntimeConfig({
    this.maxProcesses = 50,
    this.maxMemoryMB = 128,
    this.maxCpuPercent = 80,
    this.tickRateMs = 10,
    this.maxIOOperationsPerSecond = 1000,
    this.maxNetworkConnections = 10,
    this.errorHandling = const ErrorHandlingPolicy(),
    this.security,
  });

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) => RuntimeConfig(
        maxProcesses: json['maxProcesses'] as int? ?? 50,
        maxMemoryMB: json['maxMemoryMB'] as int? ?? 128,
        maxCpuPercent: json['maxCpuPercent'] as int? ?? 80,
        tickRateMs: json['tickRateMs'] as int? ?? 10,
        maxIOOperationsPerSecond:
            json['maxIOOperationsPerSecond'] as int? ?? 1000,
        maxNetworkConnections: json['maxNetworkConnections'] as int? ?? 10,
        errorHandling: json['errorHandling'] != null
            ? ErrorHandlingPolicy.fromJson(
                json['errorHandling'] as Map<String, dynamic>)
            : const ErrorHandlingPolicy(),
        security: json['security'] != null
            ? SecurityPolicy.fromJson(json['security'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'maxProcesses': maxProcesses,
        'maxMemoryMB': maxMemoryMB,
        'maxCpuPercent': maxCpuPercent,
        'tickRateMs': tickRateMs,
        'maxIOOperationsPerSecond': maxIOOperationsPerSecond,
        'maxNetworkConnections': maxNetworkConnections,
        'errorHandling': errorHandling.toJson(),
        if (security != null) 'security': security!.toJson(),
      };
}

/// Error handling policy
class ErrorHandlingPolicy {
  final int defaultRetryCount;
  final int defaultRetryDelay;
  final String defaultBackoff;
  final bool panicOnCriticalError;
  final AutoRestartPolicy? autoRestart;
  final DeadlockDetection? deadlockDetection;

  const ErrorHandlingPolicy({
    this.defaultRetryCount = 3,
    this.defaultRetryDelay = 1000,
    this.defaultBackoff = 'exponential',
    this.panicOnCriticalError = false,
    this.autoRestart,
    this.deadlockDetection,
  });

  factory ErrorHandlingPolicy.fromJson(Map<String, dynamic> json) =>
      ErrorHandlingPolicy(
        defaultRetryCount: json['defaultRetryCount'] as int? ?? 3,
        defaultRetryDelay: json['defaultRetryDelay'] as int? ?? 1000,
        defaultBackoff: json['defaultBackoff'] as String? ?? 'exponential',
        panicOnCriticalError: json['panicOnCriticalError'] as bool? ?? false,
        autoRestart: json['autoRestart'] != null
            ? AutoRestartPolicy.fromJson(
                json['autoRestart'] as Map<String, dynamic>)
            : null,
        deadlockDetection: json['deadlockDetection'] != null
            ? DeadlockDetection.fromJson(
                json['deadlockDetection'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'defaultRetryCount': defaultRetryCount,
        'defaultRetryDelay': defaultRetryDelay,
        'defaultBackoff': defaultBackoff,
        'panicOnCriticalError': panicOnCriticalError,
        if (autoRestart != null) 'autoRestart': autoRestart!.toJson(),
        if (deadlockDetection != null)
          'deadlockDetection': deadlockDetection!.toJson(),
      };
}

/// Auto-restart policy
class AutoRestartPolicy {
  final bool enabled;
  final int maxRestarts;
  final int restartDelay;
  final double backoffMultiplier;

  const AutoRestartPolicy({
    this.enabled = true,
    this.maxRestarts = 5,
    this.restartDelay = 30000,
    this.backoffMultiplier = 2.0,
  });

  factory AutoRestartPolicy.fromJson(Map<String, dynamic> json) =>
      AutoRestartPolicy(
        enabled: json['enabled'] as bool? ?? true,
        maxRestarts: json['maxRestarts'] as int? ?? 5,
        restartDelay: json['restartDelay'] as int? ?? 30000,
        backoffMultiplier:
            (json['backoffMultiplier'] as num?)?.toDouble() ?? 2.0,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'maxRestarts': maxRestarts,
        'restartDelay': restartDelay,
        'backoffMultiplier': backoffMultiplier,
      };
}

/// Deadlock detection configuration
class DeadlockDetection {
  final bool enabled;
  final int timeoutMs;
  final String action;

  const DeadlockDetection({
    this.enabled = true,
    this.timeoutMs = 60000,
    this.action = 'restart_affected_processes',
  });

  factory DeadlockDetection.fromJson(Map<String, dynamic> json) =>
      DeadlockDetection(
        enabled: json['enabled'] as bool? ?? true,
        timeoutMs: json['timeoutMs'] as int? ?? 60000,
        action: json['action'] as String? ?? 'restart_affected_processes',
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'timeoutMs': timeoutMs,
        'action': action,
      };
}

/// Security policy
class SecurityPolicy {
  final AuthenticationMode authMode;
  final AuthorizationMode authzMode;
  final bool tlsEnabled;
  final String? tlsMinVersion;

  const SecurityPolicy({
    this.authMode = AuthenticationMode.token,
    this.authzMode = AuthorizationMode.rbac,
    this.tlsEnabled = true,
    this.tlsMinVersion = '1.2',
  });

  factory SecurityPolicy.fromJson(Map<String, dynamic> json) => SecurityPolicy(
        authMode: AuthenticationMode.values.byName(
            json['authMode'] as String? ?? 'token'),
        authzMode: AuthorizationMode.values.byName(
            json['authzMode'] as String? ?? 'rbac'),
        tlsEnabled: json['tlsEnabled'] as bool? ?? true,
        tlsMinVersion: json['tlsMinVersion'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'authMode': authMode.name,
        'authzMode': authzMode.name,
        'tlsEnabled': tlsEnabled,
        if (tlsMinVersion != null) 'tlsMinVersion': tlsMinVersion,
      };
}

/// Authentication modes
enum AuthenticationMode { none, token, certificate, oauth }

/// Authorization modes
enum AuthorizationMode { none, rbac, acl }

/// Process states
enum ProcessState {
  created,
  waiting,
  ready,
  executing,
  suspended,
  completed,
  error,
}

/// Process runtime information
class ProcessInstance {
  final String id;
  final ProcessDefinition definition;
  ProcessState state;
  final DateTime startedAt;
  DateTime? completedAt;
  final Map<String, dynamic> variables;
  final List<ActionResult> actionResults;
  dynamic lastError;
  int retryCount;

  ProcessInstance({
    required this.id,
    required this.definition,
    this.state = ProcessState.created,
    DateTime? startedAt,
    this.completedAt,
    Map<String, dynamic>? variables,
    List<ActionResult>? actionResults,
    this.lastError,
    this.retryCount = 0,
  })  : startedAt = startedAt ?? DateTime.now(),
        variables = variables ?? {},
        actionResults = actionResults ?? [];

  Duration get executionTime => (completedAt ?? DateTime.now()).difference(startedAt);
}

/// Action execution result
class ActionResult {
  final String actionType;
  final ActionStatus status;
  final dynamic result;
  final dynamic error;
  final DateTime timestamp;
  final Duration executionTime;

  const ActionResult({
    required this.actionType,
    required this.status,
    this.result,
    this.error,
    required this.timestamp,
    required this.executionTime,
  });
}

/// Action execution status
enum ActionStatus {
  success,
  error,
  timeout,
  skipped,
  retry,
}

/// Execution context for actions
class ExecutionContext {
  final ProcessInstance process;
  final Map<String, dynamic> globalState;
  final Map<String, dynamic> resources;
  final Map<String, StreamController> channels;
  final Map<String, dynamic> args;

  const ExecutionContext({
    required this.process,
    required this.globalState,
    required this.resources,
    required this.channels,
    this.args = const {},
  });

  /// Create a child context for sub-actions
  ExecutionContext createChildContext({
    Map<String, dynamic>? additionalVars,
  }) {
    return ExecutionContext(
      process: process,
      globalState: globalState,
      resources: resources,
      channels: channels,
      args: {...args, ...?additionalVars},
    );
  }

  /// Get a variable value, checking local then global scope
  dynamic getVariable(String name) {
    return process.variables[name] ?? globalState[name];
  }

  /// Set a variable in the appropriate scope
  void setVariable(String name, dynamic value, {bool global = false}) {
    if (global || globalState.containsKey(name)) {
      globalState[name] = value;
    } else {
      process.variables[name] = value;
    }
  }
}

/// Process scheduler entry
class ScheduledProcess {
  final ProcessInstance process;
  final int priority;
  final DateTime scheduledAt;
  Timer? timer;

  ScheduledProcess({
    required this.process,
    required this.priority,
    DateTime? scheduledAt,
    this.timer,
  }) : scheduledAt = scheduledAt ?? DateTime.now();
}

/// Resource usage statistics
class ResourceUsage {
  final int memoryBytes;
  final double cpuPercent;
  final int ioOperations;
  final int networkConnections;
  final DateTime timestamp;

  const ResourceUsage({
    required this.memoryBytes,
    required this.cpuPercent,
    required this.ioOperations,
    required this.networkConnections,
    required this.timestamp,
  });
}

/// Runtime statistics
class RuntimeStatistics {
  final RuntimeStatus status;
  final DateTime startedAt;
  final Duration uptime;
  final int totalProcesses;
  final int activeProcesses;
  final int completedProcesses;
  final int errorProcesses;
  final ResourceUsage resourceUsage;
  final Map<String, int> actionCounts;

  const RuntimeStatistics({
    required this.status,
    required this.startedAt,
    required this.uptime,
    required this.totalProcesses,
    required this.activeProcesses,
    required this.completedProcesses,
    required this.errorProcesses,
    required this.resourceUsage,
    required this.actionCounts,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        'uptime': uptime.inMilliseconds,
        'totalProcesses': totalProcesses,
        'activeProcesses': activeProcesses,
        'completedProcesses': completedProcesses,
        'errorProcesses': errorProcesses,
        'resourceUsage': {
          'memoryBytes': resourceUsage.memoryBytes,
          'cpuPercent': resourceUsage.cpuPercent,
          'ioOperations': resourceUsage.ioOperations,
          'networkConnections': resourceUsage.networkConnections,
          'timestamp': resourceUsage.timestamp.toIso8601String(),
        },
        'actionCounts': actionCounts,
      };
}