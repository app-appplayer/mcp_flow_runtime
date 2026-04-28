/// Watchdog timer for process monitoring and safety
import 'dart:async';
import 'package:logging/logging.dart';

/// Watchdog configuration
class WatchdogConfig {
  final bool enabled;
  final int timeoutMs;
  final String action;
  final List<String> criticalProcesses;

  const WatchdogConfig({
    this.enabled = false,
    this.timeoutMs = 30000,
    this.action = 'restart_process',
    this.criticalProcesses = const [],
  });

  factory WatchdogConfig.fromJson(Map<String, dynamic> json) {
    return WatchdogConfig(
      enabled: json['enabled'] as bool? ?? false,
      timeoutMs: json['timeoutMs'] as int? ?? 30000,
      action: json['action'] as String? ?? 'restart_process',
      criticalProcesses: (json['criticalProcesses'] as List?)
              ?.map((p) => p as String)
              .toList() ??
          const [],
    );
  }
}

/// Process watchdog timer
class ProcessWatchdog {
  final Logger _logger = Logger('ProcessWatchdog');
  final WatchdogConfig config;
  final Map<String, Timer> _processTimers = {};
  final Map<String, DateTime> _lastActivity = {};
  final void Function(String processId, String action) onTimeout;

  ProcessWatchdog({
    required this.config,
    required this.onTimeout,
  });

  /// Start monitoring a process
  void startMonitoring(String processId) {
    if (!config.enabled) return;

    _logger.fine('Starting watchdog for process: $processId');
    _lastActivity[processId] = DateTime.now();
    
    // Cancel any existing timer
    _processTimers[processId]?.cancel();
    
    // Start new timer
    _processTimers[processId] = Timer.periodic(
      Duration(milliseconds: config.timeoutMs ~/ 3), // Check 3x within timeout
      (_) => _checkProcess(processId),
    );
  }

  /// Stop monitoring a process
  void stopMonitoring(String processId) {
    _logger.fine('Stopping watchdog for process: $processId');
    _processTimers[processId]?.cancel();
    _processTimers.remove(processId);
    _lastActivity.remove(processId);
  }

  /// Update process activity (heartbeat)
  void heartbeat(String processId) {
    if (!config.enabled) return;
    _lastActivity[processId] = DateTime.now();
  }

  /// Check if a process has timed out
  void _checkProcess(String processId) {
    final lastActivity = _lastActivity[processId];
    if (lastActivity == null) return;

    final elapsed = DateTime.now().difference(lastActivity).inMilliseconds;
    if (elapsed > config.timeoutMs) {
      _logger.warning('Process $processId exceeded watchdog timeout: ${elapsed}ms > ${config.timeoutMs}ms');
      
      // Stop monitoring this process
      stopMonitoring(processId);
      
      // Trigger timeout action
      final action = config.criticalProcesses.contains(processId) 
          ? 'restart_runtime' // Critical processes trigger runtime restart
          : config.action;
      
      onTimeout(processId, action);
    }
  }

  /// Dispose all timers
  void dispose() {
    for (final timer in _processTimers.values) {
      timer.cancel();
    }
    _processTimers.clear();
    _lastActivity.clear();
  }
}

/// Runtime watchdog for overall system health
class RuntimeWatchdog {
  final Logger _logger = Logger('RuntimeWatchdog');
  final WatchdogConfig config;
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeat;
  int _missedHeartbeats = 0;
  final void Function(String action) onSystemTimeout;

  RuntimeWatchdog({
    required this.config,
    required this.onSystemTimeout,
  });

  /// Start runtime monitoring
  void start() {
    if (!config.enabled) return;

    _logger.info('Starting runtime watchdog with timeout: ${config.timeoutMs}ms');
    _lastHeartbeat = DateTime.now();
    _missedHeartbeats = 0;

    // Check heartbeat periodically
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: config.timeoutMs ~/ 3),
      (_) => _checkHeartbeat(),
    );
  }

  /// Stop runtime monitoring
  void stop() {
    _logger.info('Stopping runtime watchdog');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastHeartbeat = null;
    _missedHeartbeats = 0;
  }

  /// Update runtime heartbeat
  void heartbeat() {
    if (!config.enabled) return;
    _lastHeartbeat = DateTime.now();
    _missedHeartbeats = 0;
  }

  /// Check runtime heartbeat
  void _checkHeartbeat() {
    final lastHeartbeat = _lastHeartbeat;
    if (lastHeartbeat == null) return;

    final elapsed = DateTime.now().difference(lastHeartbeat).inMilliseconds;
    if (elapsed > config.timeoutMs) {
      _missedHeartbeats++;
      _logger.warning('Runtime missed heartbeat #$_missedHeartbeats: ${elapsed}ms > ${config.timeoutMs}ms');
      
      // Default to 3 missed heartbeats before action
      if (_missedHeartbeats >= 3) {
        _logger.severe('Runtime watchdog timeout - triggering action: ${config.action}');
        stop();
        onSystemTimeout(config.action);
      }
    }
  }

  /// Dispose resources
  void dispose() {
    stop();
  }
}