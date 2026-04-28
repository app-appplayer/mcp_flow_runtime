/// Runtime-related type definitions

import 'flow_types.dart';

/// Runtime states
enum RuntimeStatus {
  created,
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// Runtime configuration
class RuntimeConfig {
  final int tickRateMs;
  final int maxProcesses;
  final int maxMemoryKB;
  final String? flowFilePath;
  final String storeType;
  final Map<String, dynamic>? storeConfig;
  final bool enableMonitoring;
  final bool enableWatchdog;
  final int? watchdogIntervalMs;
  final String logLevel;
  final String? logFilePath;

  const RuntimeConfig({
    this.tickRateMs = 10,
    this.maxProcesses = 50,
    this.maxMemoryKB = 131072,
    this.flowFilePath,
    this.storeType = 'memory',
    this.storeConfig,
    this.enableMonitoring = true,
    this.enableWatchdog = true,
    this.watchdogIntervalMs,
    this.logLevel = 'info',
    this.logFilePath,
  });

  factory RuntimeConfig.fromJson(Map<String, dynamic> json) => RuntimeConfig(
        tickRateMs: json['tickRateMs'] as int? ?? 10,
        maxProcesses: json['maxProcesses'] as int? ?? 50,
        maxMemoryKB: json['maxMemoryKB'] as int? ?? 131072,
        flowFilePath: json['flowFilePath'] as String?,
        storeType: json['storeType'] as String? ?? 'memory',
        storeConfig: json['storeConfig'] as Map<String, dynamic>?,
        enableMonitoring: json['enableMonitoring'] as bool? ?? true,
        enableWatchdog: json['enableWatchdog'] as bool? ?? true,
        watchdogIntervalMs: json['watchdogIntervalMs'] as int?,
        logLevel: json['logLevel'] as String? ?? 'info',
        logFilePath: json['logFilePath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'tickRateMs': tickRateMs,
        'maxProcesses': maxProcesses,
        'maxMemoryKB': maxMemoryKB,
        if (flowFilePath != null) 'flowFilePath': flowFilePath,
        'storeType': storeType,
        if (storeConfig != null) 'storeConfig': storeConfig,
        'enableMonitoring': enableMonitoring,
        'enableWatchdog': enableWatchdog,
        if (watchdogIntervalMs != null) 'watchdogIntervalMs': watchdogIntervalMs,
        'logLevel': logLevel,
        if (logFilePath != null) 'logFilePath': logFilePath,
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
  final String definitionId;
  ProcessState state;
  final DateTime createdAt;
  final DateTime startedAt;
  DateTime? completedAt;
  int currentStepIndex;
  final Map<String, dynamic> localContext;
  dynamic errorMessage;

  ProcessInstance({
    required this.id,
    required this.definitionId,
    this.state = ProcessState.created,
    DateTime? createdAt,
    DateTime? startedAt,
    this.completedAt,
    this.currentStepIndex = 0,
    Map<String, dynamic>? localContext,
    this.errorMessage,
  })  : createdAt = createdAt ?? DateTime.now(),
        startedAt = startedAt ?? DateTime.now(),
        localContext = localContext ?? {};

  Duration get executionTime => (completedAt ?? DateTime.now()).difference(startedAt);
}

/// Action execution result
class ActionResult {
  final ActionStatus status;
  final dynamic value;
  final String? errorCode;
  final String? errorMessage;
  final Duration executionTime;

  const ActionResult({
    required this.status,
    this.value,
    this.errorCode,
    this.errorMessage,
    required this.executionTime,
  });
}

/// Action execution status
enum ActionStatus {
  success,
  failure,
  timeout,
  skipped,
}

/// Execution context for actions
class ExecutionContext {
  final ProcessInstance process;
  final Map<String, dynamic> globalState;
  final Map<String, dynamic> resources;
  final Map<String, dynamic> channels;
  final Map<String, dynamic> args;
  final Future<void> Function(String processId, Map<String, dynamic> args)? executeProcessCallback;
  final Future<void> Function(String processId)? stopProcessCallback;

  const ExecutionContext({
    required this.process,
    required this.globalState,
    required this.resources,
    required this.channels,
    this.args = const {},
    this.executeProcessCallback,
    this.stopProcessCallback,
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
      executeProcessCallback: executeProcessCallback,
      stopProcessCallback: stopProcessCallback,
    );
  }

  /// Get a variable value, checking local then global scope
  dynamic getVariable(String name) {
    return process.localContext[name] ?? globalState[name];
  }

  /// Set a variable in the appropriate scope
  void setVariable(String name, dynamic value, {bool global = false}) {
    if (global || globalState.containsKey(name)) {
      globalState[name] = value;
    } else {
      process.localContext[name] = value;
    }
  }
}

/// Process scheduler entry
class ScheduledProcess {
  final String definitionId;
  final String triggerType;
  final Map<String, dynamic>? triggerParams;
  final DateTime scheduledAt;

  ScheduledProcess({
    required this.definitionId,
    required this.triggerType,
    this.triggerParams,
    DateTime? scheduledAt,
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
  final DateTime startedAt;
  final int totalProcessesStarted;
  final int totalProcessesCompleted;
  final int totalProcessesFailed;
  final int activeProcessCount;
  final int totalActionsExecuted;
  final Map<String, int> actionCountByType;

  RuntimeStatistics({
    DateTime? startedAt,
    required this.totalProcessesStarted,
    required this.totalProcessesCompleted,
    required this.totalProcessesFailed,
    required this.activeProcessCount,
    required this.totalActionsExecuted,
    required this.actionCountByType,
  }) : startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'totalProcessesStarted': totalProcessesStarted,
        'totalProcessesCompleted': totalProcessesCompleted,
        'totalProcessesFailed': totalProcessesFailed,
        'activeProcessCount': activeProcessCount,
        'totalActionsExecuted': totalActionsExecuted,
        'actionCountByType': actionCountByType,
      };
}

/// Process information for MCP integration
class ProcessInfo {
  final String id;
  final String name;
  final String? description;
  final bool enabled;
  final ProcessState status;
  final TriggerType? triggerType;
  final ProcessPriority priority;
  
  const ProcessInfo({
    required this.id,
    required this.name,
    this.description,
    required this.enabled,
    required this.status,
    this.triggerType,
    required this.priority,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'enabled': enabled,
    'status': status.toString(),
    if (triggerType != null) 'triggerType': triggerType.toString(),
    'priority': priority.toString(),
  };
}