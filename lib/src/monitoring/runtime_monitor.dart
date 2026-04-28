/// Runtime monitoring and metrics collection
import 'dart:async';
import 'package:logging/logging.dart';
import '../core/runtime.dart';
import '../types/flow_types.dart';
import '../types/runtime_types.dart';

/// Monitoring configuration
class MonitoringConfig {
  /// Enable process execution metrics
  final bool enableProcessMetrics;
  
  /// Enable state change tracking
  final bool enableStateTracking;
  
  /// Enable resource usage monitoring
  final bool enableResourceMonitoring;
  
  /// Enable event tracking
  final bool enableEventTracking;
  
  /// Metrics collection interval (milliseconds)
  final int metricsInterval;
  
  /// Maximum number of metrics to keep in memory
  final int maxMetricsHistory;
  
  const MonitoringConfig({
    this.enableProcessMetrics = true,
    this.enableStateTracking = true,
    this.enableResourceMonitoring = true,
    this.enableEventTracking = true,
    this.metricsInterval = 1000,
    this.maxMetricsHistory = 1000,
  });
}

/// Process execution metric
class ProcessMetric {
  final String processId;
  final DateTime startTime;
  final DateTime? endTime;
  final ProcessExecutionStatus status;
  final String? error;
  final int stepCount;
  final int completedSteps;
  final Map<String, dynamic> metadata;
  
  ProcessMetric({
    required this.processId,
    required this.startTime,
    this.endTime,
    required this.status,
    this.error,
    required this.stepCount,
    required this.completedSteps,
    this.metadata = const {},
  });
  
  Duration get duration => endTime?.difference(startTime) ?? DateTime.now().difference(startTime);
  
  Map<String, dynamic> toJson() => {
    'processId': processId,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'status': status.name,
    'error': error,
    'stepCount': stepCount,
    'completedSteps': completedSteps,
    'duration': duration.inMilliseconds,
    'metadata': metadata,
  };
}

/// State change event
class StateChangeEvent {
  final String variable;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime timestamp;
  final String? triggeredBy;
  
  StateChangeEvent({
    required this.variable,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
    this.triggeredBy,
  });
  
  Map<String, dynamic> toJson() => {
    'variable': variable,
    'oldValue': oldValue,
    'newValue': newValue,
    'timestamp': timestamp.toIso8601String(),
    'triggeredBy': triggeredBy,
  };
}

/// Resource usage metric
class ResourceMetric {
  final String resourceId;
  final String resourceType;
  final DateTime timestamp;
  final Map<String, dynamic> usage;
  
  ResourceMetric({
    required this.resourceId,
    required this.resourceType,
    required this.timestamp,
    required this.usage,
  });
  
  Map<String, dynamic> toJson() => {
    'resourceId': resourceId,
    'resourceType': resourceType,
    'timestamp': timestamp.toIso8601String(),
    'usage': usage,
  };
}

/// Event metric
class EventMetric {
  final String eventName;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  final String? source;
  
  EventMetric({
    required this.eventName,
    required this.timestamp,
    this.data,
    this.source,
  });
  
  Map<String, dynamic> toJson() => {
    'eventName': eventName,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
    'source': source,
  };
}

/// Runtime health status
enum HealthStatus {
  healthy,
  degraded,
  unhealthy,
}

/// Health check result
class HealthCheckResult {
  final HealthStatus status;
  final Map<String, HealthStatus> components;
  final List<String> issues;
  final DateTime timestamp;
  
  HealthCheckResult({
    required this.status,
    required this.components,
    required this.issues,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'status': status.name,
    'components': components.map((k, v) => MapEntry(k, v.name)),
    'issues': issues,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Runtime monitor
class RuntimeMonitor {
  final McpFlowRuntime _runtime;
  final MonitoringConfig _config;
  final Logger _logger = Logger('RuntimeMonitor');
  
  // Metrics storage
  final List<ProcessMetric> _processMetrics = [];
  final List<StateChangeEvent> _stateChanges = [];
  final List<ResourceMetric> _resourceMetrics = [];
  final List<EventMetric> _eventMetrics = [];
  
  // Active process tracking
  final Map<String, ProcessMetric> _activeProcesses = {};
  
  // Monitoring state
  Timer? _metricsTimer;
  bool _isMonitoring = false;
  
  // Listeners
  final _processStartController = StreamController<ProcessMetric>.broadcast();
  final _processEndController = StreamController<ProcessMetric>.broadcast();
  final _stateChangeController = StreamController<StateChangeEvent>.broadcast();
  final _resourceMetricController = StreamController<ResourceMetric>.broadcast();
  final _eventMetricController = StreamController<EventMetric>.broadcast();
  final _healthCheckController = StreamController<HealthCheckResult>.broadcast();
  
  RuntimeMonitor({
    required McpFlowRuntime runtime,
    MonitoringConfig? config,
  })  : _runtime = runtime,
        _config = config ?? const MonitoringConfig();
  
  /// Stream of process start events
  Stream<ProcessMetric> get onProcessStart => _processStartController.stream;
  
  /// Stream of process end events
  Stream<ProcessMetric> get onProcessEnd => _processEndController.stream;
  
  /// Stream of state changes
  Stream<StateChangeEvent> get onStateChange => _stateChangeController.stream;
  
  /// Stream of resource metrics
  Stream<ResourceMetric> get onResourceMetric => _resourceMetricController.stream;
  
  /// Stream of event metrics
  Stream<EventMetric> get onEventMetric => _eventMetricController.stream;
  
  /// Stream of health check results
  Stream<HealthCheckResult> get onHealthCheck => _healthCheckController.stream;
  
  /// Start monitoring
  void start() {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    _logger.info('Starting runtime monitoring');
    
    // Set up runtime hooks
    _setupRuntimeHooks();
    
    // Start metrics collection timer
    if (_config.metricsInterval > 0) {
      _metricsTimer = Timer.periodic(
        Duration(milliseconds: _config.metricsInterval),
        (_) => _collectMetrics(),
      );
    }
  }
  
  /// Stop monitoring
  void stop() {
    if (!_isMonitoring) return;
    
    _isMonitoring = false;
    _logger.info('Stopping runtime monitoring');
    
    _metricsTimer?.cancel();
    _teardownRuntimeHooks();
  }
  
  /// Get current metrics summary
  Map<String, dynamic> getMetricsSummary() {
    final now = DateTime.now();
    final lastMinute = now.subtract(Duration(minutes: 1));
    
    // Process metrics
    final recentProcesses = _processMetrics
        .where((m) => m.startTime.isAfter(lastMinute))
        .toList();
    
    final successCount = recentProcesses
        .where((m) => m.status == ProcessExecutionStatus.completed)
        .length;
    final failureCount = recentProcesses
        .where((m) => m.status == ProcessExecutionStatus.failed)
        .length;
    
    final avgDuration = recentProcesses.isEmpty
        ? 0
        : recentProcesses
            .map((m) => m.duration.inMilliseconds)
            .reduce((a, b) => a + b) / recentProcesses.length;
    
    // State metrics
    final recentStateChanges = _stateChanges
        .where((e) => e.timestamp.isAfter(lastMinute))
        .length;
    
    // Resource metrics
    final recentResourceMetrics = _resourceMetrics
        .where((m) => m.timestamp.isAfter(lastMinute))
        .length;
    
    // Event metrics
    final recentEvents = _eventMetrics
        .where((m) => m.timestamp.isAfter(lastMinute))
        .length;
    
    return {
      'timestamp': now.toIso8601String(),
      'processes': {
        'active': _activeProcesses.length,
        'recentTotal': recentProcesses.length,
        'recentSuccess': successCount,
        'recentFailure': failureCount,
        'avgDurationMs': avgDuration.round(),
      },
      'state': {
        'changesPerMinute': recentStateChanges,
        'totalVariables': _runtime.getAllStateVariables().length,
      },
      'resources': {
        'metricsPerMinute': recentResourceMetrics,
      },
      'events': {
        'eventsPerMinute': recentEvents,
      },
    };
  }
  
  /// Get process metrics
  List<ProcessMetric> getProcessMetrics({
    DateTime? since,
    String? processId,
    ProcessExecutionStatus? status,
  }) {
    var metrics = List<ProcessMetric>.from(_processMetrics);
    
    if (since != null) {
      metrics = metrics.where((m) => m.startTime.isAfter(since)).toList();
    }
    
    if (processId != null) {
      metrics = metrics.where((m) => m.processId == processId).toList();
    }
    
    if (status != null) {
      metrics = metrics.where((m) => m.status == status).toList();
    }
    
    return metrics;
  }
  
  /// Get state change history
  List<StateChangeEvent> getStateChangeHistory({
    DateTime? since,
    String? variable,
  }) {
    var events = List<StateChangeEvent>.from(_stateChanges);
    
    if (since != null) {
      events = events.where((e) => e.timestamp.isAfter(since)).toList();
    }
    
    if (variable != null) {
      events = events.where((e) => e.variable == variable).toList();
    }
    
    return events;
  }
  
  /// Perform health check
  Future<HealthCheckResult> performHealthCheck() async {
    final issues = <String>[];
    final components = <String, HealthStatus>{};
    
    // Check runtime status
    final runtimeStatus = _runtime.status;
    if (runtimeStatus == RuntimeStatus.running) {
      components['runtime'] = HealthStatus.healthy;
    } else if (runtimeStatus == RuntimeStatus.stopped) {
      components['runtime'] = HealthStatus.degraded;
      issues.add('Runtime is stopped');
    } else {
      components['runtime'] = HealthStatus.unhealthy;
      issues.add('Runtime is in error state');
    }
    
    // Check process execution
    final recentFailures = _processMetrics
        .where((m) => 
            m.endTime != null &&
            m.endTime!.isAfter(DateTime.now().subtract(Duration(minutes: 5))) &&
            m.status == ProcessExecutionStatus.failed)
        .length;
    
    if (recentFailures == 0) {
      components['processes'] = HealthStatus.healthy;
    } else if (recentFailures < 5) {
      components['processes'] = HealthStatus.degraded;
      issues.add('$recentFailures process failures in last 5 minutes');
    } else {
      components['processes'] = HealthStatus.unhealthy;
      issues.add('High process failure rate: $recentFailures in last 5 minutes');
    }
    
    // Check state store
    try {
      // Try to access state to verify store is working
      _runtime.getAllStateVariables();
      components['stateStore'] = HealthStatus.healthy;
    } catch (e) {
      components['stateStore'] = HealthStatus.unhealthy;
      issues.add('State store unavailable: $e');
    }
    
    // Check process list availability
    try {
      _runtime.getProcessList();
      components['processRegistry'] = HealthStatus.healthy;
    } catch (e) {
      components['processRegistry'] = HealthStatus.unhealthy;
      issues.add('Cannot get process list: $e');
    }
    
    // Determine overall status
    final statuses = components.values.toList();
    final overallStatus = statuses.contains(HealthStatus.unhealthy)
        ? HealthStatus.unhealthy
        : statuses.contains(HealthStatus.degraded)
            ? HealthStatus.degraded
            : HealthStatus.healthy;
    
    final result = HealthCheckResult(
      status: overallStatus,
      components: components,
      issues: issues,
      timestamp: DateTime.now(),
    );
    
    _healthCheckController.add(result);
    return result;
  }
  
  /// Clear old metrics
  void pruneMetrics({DateTime? before}) {
    final cutoff = before ?? DateTime.now().subtract(Duration(hours: 1));
    
    _processMetrics.removeWhere((m) => m.endTime?.isBefore(cutoff) ?? false);
    _stateChanges.removeWhere((e) => e.timestamp.isBefore(cutoff));
    _resourceMetrics.removeWhere((m) => m.timestamp.isBefore(cutoff));
    _eventMetrics.removeWhere((m) => m.timestamp.isBefore(cutoff));
    
    // Enforce max history
    void enforceMax<T>(List<T> list) {
      if (list.length > _config.maxMetricsHistory) {
        list.removeRange(0, list.length - _config.maxMetricsHistory);
      }
    }
    
    enforceMax(_processMetrics);
    enforceMax(_stateChanges);
    enforceMax(_resourceMetrics);
    enforceMax(_eventMetrics);
  }
  
  /// Dispose monitor
  void dispose() {
    stop();
    
    _processStartController.close();
    _processEndController.close();
    _stateChangeController.close();
    _resourceMetricController.close();
    _eventMetricController.close();
    _healthCheckController.close();
  }
  
  // Private methods
  
  void _setupRuntimeHooks() {
    // TODO: Set up runtime event listeners
    // This would require runtime to expose events
  }
  
  void _teardownRuntimeHooks() {
    // TODO: Remove runtime event listeners
  }
  
  void _collectMetrics() {
    // Collect resource metrics if enabled
    if (_config.enableResourceMonitoring) {
      _collectResourceMetrics();
    }
    
    // Perform periodic health check
    performHealthCheck().catchError((e) {
      _logger.warning('Health check failed: $e');
      return HealthCheckResult(
        status: HealthStatus.unhealthy,
        components: {},
        issues: ['Health check failed: $e'],
        timestamp: DateTime.now(),
      );
    });
    
    // Prune old metrics
    pruneMetrics();
  }
  
  void _collectResourceMetrics() {
    // TODO: Collect actual resource metrics from HAL
    // For now, generate sample metrics
    
    final metric = ResourceMetric(
      resourceId: 'system',
      resourceType: 'system',
      timestamp: DateTime.now(),
      usage: {
        'activeProcesses': _activeProcesses.length,
        'stateVariables': _runtime.getAllStateVariables().length,
      },
    );
    
    _resourceMetrics.add(metric);
    _resourceMetricController.add(metric);
  }
  
  /// Record process start
  void recordProcessStart(String processId, ProcessDefinition process) {
    if (!_config.enableProcessMetrics) return;
    
    final metric = ProcessMetric(
      processId: processId,
      startTime: DateTime.now(),
      status: ProcessExecutionStatus.running,
      stepCount: process.steps.length,
      completedSteps: 0,
      metadata: {
        'name': process.name,
        'trigger': process.trigger?.type ?? 'none',
      },
    );
    
    _activeProcesses[processId] = metric;
    _processStartController.add(metric);
  }
  
  /// Record process end
  void recordProcessEnd(
    String processId,
    ProcessExecutionStatus status, {
    String? error,
    int? completedSteps,
  }) {
    if (!_config.enableProcessMetrics) return;
    
    final startMetric = _activeProcesses.remove(processId);
    if (startMetric == null) return;
    
    final endMetric = ProcessMetric(
      processId: processId,
      startTime: startMetric.startTime,
      endTime: DateTime.now(),
      status: status,
      error: error,
      stepCount: startMetric.stepCount,
      completedSteps: completedSteps ?? startMetric.stepCount,
      metadata: startMetric.metadata,
    );
    
    _processMetrics.add(endMetric);
    _processEndController.add(endMetric);
  }
  
  /// Record state change
  void recordStateChange(
    String variable,
    dynamic oldValue,
    dynamic newValue, {
    String? triggeredBy,
  }) {
    if (!_config.enableStateTracking) return;
    
    final event = StateChangeEvent(
      variable: variable,
      oldValue: oldValue,
      newValue: newValue,
      timestamp: DateTime.now(),
      triggeredBy: triggeredBy,
    );
    
    _stateChanges.add(event);
    _stateChangeController.add(event);
  }
  
  /// Record event
  void recordEvent(
    String eventName, {
    Map<String, dynamic>? data,
    String? source,
  }) {
    if (!_config.enableEventTracking) return;
    
    final metric = EventMetric(
      eventName: eventName,
      timestamp: DateTime.now(),
      data: data,
      source: source,
    );
    
    _eventMetrics.add(metric);
    _eventMetricController.add(metric);
  }
}

/// Process execution status
enum ProcessExecutionStatus {
  running,
  completed,
  failed,
  cancelled,
}