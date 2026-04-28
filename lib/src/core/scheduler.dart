/// Process scheduler for MCP Flow Runtime

import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';

import '../types/runtime_types.dart';
import '../errors/flow_errors.dart';

/// Internal scheduled process entry used by the scheduler
class _ScheduledEntry {
  final ProcessInstance process;
  final int priority;
  final DateTime scheduledAt;
  Timer? timer;
  Future<void> Function()? onExecute;

  _ScheduledEntry({
    required this.process,
    required this.priority,
    DateTime? scheduledAt,
    this.timer,
    this.onExecute,
  }) : scheduledAt = scheduledAt ?? DateTime.now();
}

/// Process scheduler implementation
class ProcessScheduler {
  final Logger _logger = Logger('ProcessScheduler');
  int maxProcesses;
  int tickRateMs;
  
  final Queue<_ScheduledEntry> _lowPriority = Queue();
  final Queue<_ScheduledEntry> _normalPriority = Queue();
  final Queue<_ScheduledEntry> _highPriority = Queue();
  final Queue<_ScheduledEntry> _realtimePriority = Queue();
  
  final Map<String, _ScheduledEntry> _activeProcesses = {};
  final List<_ScheduledEntry> _completedProcesses = [];
  
  Timer? _schedulerTimer;
  bool _running = false;
  
  int _totalScheduled = 0;
  int _totalCompleted = 0;
  int _totalErrors = 0;

  ProcessScheduler({
    this.maxProcesses = 50,
    this.tickRateMs = 10,
  });

  /// Get scheduler statistics
  int get totalProcesses => _totalScheduled;
  int get activeProcesses => _activeProcesses.length;
  int get completedProcesses => _totalCompleted;
  int get errorProcesses => _totalErrors;
  int get queuedProcesses => 
      _lowPriority.length + 
      _normalPriority.length + 
      _highPriority.length + 
      _realtimePriority.length;
  
  /// Get list of active process IDs
  List<String> getActiveProcessIds() {
    return _activeProcesses.keys.toList();
  }
  
  /// Set the scheduler tick rate
  void setTickRate(Duration duration) {
    tickRateMs = duration.inMilliseconds;
    
    // Restart timer if running
    if (_running && _schedulerTimer != null) {
      _schedulerTimer!.cancel();
      _schedulerTimer = Timer.periodic(
        Duration(milliseconds: tickRateMs),
        (_) => _tick(),
      );
    }
  }
  
  /// Set the maximum number of concurrent processes
  void setMaxProcesses(int max) {
    maxProcesses = max;
  }

  /// Start the scheduler
  Future<void> start() async {
    if (_running) {
      throw ConcreteFlowError('SCHEDULER_ERROR', 'Scheduler already running');
    }

    _logger.info('Starting process scheduler');
    _running = true;
    
    // Start scheduler tick
    _schedulerTimer = Timer.periodic(
      Duration(milliseconds: tickRateMs),
      (_) => _tick(),
    );
  }

  /// Stop the scheduler
  Future<void> stop() async {
    if (!_running) {
      return;
    }

    _logger.info('Stopping process scheduler');
    _running = false;
    
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
    
    // Wait for all active processes to complete with a timeout
    if (_activeProcesses.isNotEmpty) {
      _logger.info('Waiting for ${_activeProcesses.length} active processes to complete');
      
      // Give processes up to 5 seconds to complete
      final timeout = DateTime.now().add(Duration(seconds: 5));
      while (_activeProcesses.isNotEmpty && DateTime.now().isBefore(timeout)) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      if (_activeProcesses.isNotEmpty) {
        _logger.warning('Forcing stop of ${_activeProcesses.length} active processes');
        // Cancel any remaining processes
        for (final scheduled in _activeProcesses.values) {
          scheduled.timer?.cancel();
        }
        _activeProcesses.clear();
      }
    }
  }

  /// Schedule a process
  void schedule(
    ProcessInstance process, {
    required int priority,
    required Future<void> Function() onExecute,
    DateTime? at,
  }) {
    if (!_running) {
      throw ConcreteFlowError('SCHEDULER_ERROR', 'Scheduler not running');
    }

    final scheduled = _ScheduledEntry(
      process: process,
      priority: priority,
      scheduledAt: at,
    );

    // If scheduled for future, set timer
    if (at != null && at.isAfter(DateTime.now())) {
      final delay = at.difference(DateTime.now());
      scheduled.timer = Timer(delay, () {
        _enqueueProcess(scheduled, onExecute);
      });
      _logger.fine('Process ${process.id} scheduled for ${at.toIso8601String()}');
    } else {
      _enqueueProcess(scheduled, onExecute);
    }

    _totalScheduled++;
  }

  /// Cancel a scheduled process
  bool cancel(String processId) {
    // Check active processes
    final active = _activeProcesses[processId];
    if (active != null) {
      active.timer?.cancel();
      _activeProcesses.remove(processId);
      return true;
    }

    // Check queues
    bool removed = false;
    removed |= _removeFromQueue(_realtimePriority, processId);
    removed |= _removeFromQueue(_highPriority, processId);
    removed |= _removeFromQueue(_normalPriority, processId);
    removed |= _removeFromQueue(_lowPriority, processId);

    return removed;
  }
  
  /// Cancel all instances of a process by definition ID
  bool cancelByDefinitionId(String definitionId) {
    bool cancelled = false;
    
    // Check active processes
    final activeToCancel = <String>[];
    for (final entry in _activeProcesses.entries) {
      if (entry.key.startsWith('${definitionId}_')) {
        activeToCancel.add(entry.key);
      }
    }
    
    for (final id in activeToCancel) {
      final active = _activeProcesses[id];
      if (active != null) {
        active.timer?.cancel();
        _activeProcesses.remove(id);
        cancelled = true;
      }
    }
    
    // Check and remove from queues
    cancelled |= _removeFromQueueByDefinitionId(_realtimePriority, definitionId);
    cancelled |= _removeFromQueueByDefinitionId(_highPriority, definitionId);
    cancelled |= _removeFromQueueByDefinitionId(_normalPriority, definitionId);
    cancelled |= _removeFromQueueByDefinitionId(_lowPriority, definitionId);
    
    return cancelled;
  }
  
  /// Cancel all processes
  void cancelAll() {
    _logger.info('Cancelling all processes');
    
    // Cancel all active processes
    for (final active in _activeProcesses.values) {
      active.timer?.cancel();
    }
    _activeProcesses.clear();
    
    // Clear all queues
    _realtimePriority.clear();
    _highPriority.clear();
    _normalPriority.clear();
    _lowPriority.clear();
  }

  /// Check if can schedule more processes
  bool canSchedule() {
    return _activeProcesses.length < maxProcesses;
  }
  
  /// Check if can schedule more processes with count consideration
  bool canScheduleCount(int additionalCount) {
    return _activeProcesses.length + additionalCount <= maxProcesses;
  }

  // Private methods

  void _tick() {
    if (!_running) return;

    // Process queues in priority order with batching for concurrent execution
    final toExecute = <_ScheduledEntry>[];
    final availableSlots = maxProcesses - _activeProcesses.length;
    
    // Collect processes to execute in this tick (up to available slots)
    while (toExecute.length < availableSlots && _realtimePriority.isNotEmpty) {
      toExecute.add(_realtimePriority.removeFirst());
    }
    
    while (toExecute.length < availableSlots && _highPriority.isNotEmpty) {
      toExecute.add(_highPriority.removeFirst());
    }
    
    while (toExecute.length < availableSlots && _normalPriority.isNotEmpty) {
      toExecute.add(_normalPriority.removeFirst());
    }
    
    while (toExecute.length < availableSlots && _lowPriority.isNotEmpty) {
      toExecute.add(_lowPriority.removeFirst());
    }
    
    // Execute all collected processes concurrently
    for (final scheduled in toExecute) {
      _executeConcurrent(scheduled);
    }

    // Clean up completed processes
    _cleanupCompleted();
  }

  void _enqueueProcess(
    _ScheduledEntry scheduled,
    Future<void> Function() onExecute,
  ) {
    // Store execution callback
    scheduled.process.localContext['__onExecute'] = onExecute;

    // Add to appropriate queue
    switch (scheduled.priority) {
      case 0: // low
        _lowPriority.add(scheduled);
        break;
      case 1: // normal
        _normalPriority.add(scheduled);
        break;
      case 2: // high
        _highPriority.add(scheduled);
        break;
      case 3: // realtime
        _realtimePriority.add(scheduled);
        break;
      default:
        _normalPriority.add(scheduled);
    }

    _logger.fine('Process ${scheduled.process.id} enqueued with priority ${scheduled.priority}');
  }

  void _executeNext(Queue<_ScheduledEntry> queue) {
    if (queue.isEmpty) return;

    final scheduled = queue.removeFirst();
    final process = scheduled.process;
    
    // Get execution callback before marking active
    final onExecuteRaw = process.localContext['__onExecute'];
    if (onExecuteRaw == null) {
      _logger.severe('Process ${process.id} has no __onExecute callback! Variables: ${process.localContext}');
      // Mark process as error and return
      process.state = ProcessState.error;
      return;
    }
    final onExecute = onExecuteRaw as Future<void> Function();
    process.localContext.remove('__onExecute');

    // Mark as active only when actually starting execution
    _activeProcesses[process.id] = scheduled;
    process.state = ProcessState.executing;

    // Execute process asynchronously to allow concurrent execution
    _logger.fine('Executing process ${process.id}');
    
    // Execute without await to allow parallel execution
    onExecute().then((_) {
      // Process completed successfully
      process.state = ProcessState.completed;
      process.completedAt = DateTime.now();
      _totalCompleted++;
      _logger.fine('Process ${process.id} completed successfully');
    }).catchError((error, stackTrace) {
      // Process failed
      process.state = ProcessState.error;
      process.completedAt = DateTime.now();
      process.errorMessage = error;
      _totalErrors++;
      _logger.warning('Process ${process.id} failed', error, stackTrace);
    }).whenComplete(() {
      // Remove from active
      _activeProcesses.remove(process.id);
      _completedProcesses.add(scheduled);
    });
  }

  bool _removeFromQueue(Queue<_ScheduledEntry> queue, String processId) {
    final toRemove = queue.where((s) => s.process.id == processId).toList();
    for (final scheduled in toRemove) {
      queue.remove(scheduled);
    }
    return toRemove.isNotEmpty;
  }
  
  bool _removeFromQueueByDefinitionId(Queue<_ScheduledEntry> queue, String definitionId) {
    final toRemove = queue.where((s) => s.process.id.startsWith('${definitionId}_')).toList();
    for (final scheduled in toRemove) {
      queue.remove(scheduled);
    }
    return toRemove.isNotEmpty;
  }

  void _executeConcurrent(_ScheduledEntry scheduled) {
    final process = scheduled.process;
    
    // Get execution callback
    final onExecuteRaw = process.localContext['__onExecute'];
    if (onExecuteRaw == null) {
      _logger.severe('Process ${process.id} has no __onExecute callback! Variables: ${process.localContext}');
      process.state = ProcessState.error;
      return;
    }
    final onExecute = onExecuteRaw as Future<void> Function();
    process.localContext.remove('__onExecute');

    // Mark as active
    _activeProcesses[process.id] = scheduled;
    process.state = ProcessState.executing;

    // Execute process asynchronously for true concurrency
    _logger.fine('Executing process ${process.id} concurrently');
    
    onExecute().then((_) {
      // Process completed successfully
      process.state = ProcessState.completed;
      process.completedAt = DateTime.now();
      _totalCompleted++;
      _logger.fine('Process ${process.id} completed successfully');
    }).catchError((error, stackTrace) {
      // Process failed
      process.state = ProcessState.error;
      process.completedAt = DateTime.now();
      process.errorMessage = error;
      _totalErrors++;
      _logger.warning('Process ${process.id} failed', error, stackTrace);
    }).whenComplete(() {
      // Remove from active
      _activeProcesses.remove(process.id);
      _completedProcesses.add(scheduled);
    });
  }

  void _cleanupCompleted() {
    // Keep only recent completed processes (last 100)
    if (_completedProcesses.length > 100) {
      _completedProcesses.removeRange(0, _completedProcesses.length - 100);
    }
  }
  
  /// Get process instance by ID
  ProcessInstance? getProcessInstance(String processId) {
    // Check active processes
    if (_activeProcesses.containsKey(processId)) {
      return _activeProcesses[processId]!.process;
    }
    
    // Check queues
    for (final queue in [_realtimePriority, _highPriority, _normalPriority, _lowPriority]) {
      for (final scheduled in queue) {
        if (scheduled.process.id == processId) {
          return scheduled.process;
        }
      }
    }
    
    return null;
  }
}