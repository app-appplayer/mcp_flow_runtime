/// Process scheduler for MCP Flow Runtime

import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';

import '../types/runtime_types.dart';
import '../errors/flow_errors.dart';

/// Process scheduler implementation
class ProcessScheduler {
  final Logger _logger = Logger('ProcessScheduler');
  final int maxProcesses;
  final int tickRateMs;
  
  final Queue<ScheduledProcess> _lowPriority = Queue();
  final Queue<ScheduledProcess> _normalPriority = Queue();
  final Queue<ScheduledProcess> _highPriority = Queue();
  final Queue<ScheduledProcess> _realtimePriority = Queue();
  
  final Map<String, ScheduledProcess> _activeProcesses = {};
  final List<ScheduledProcess> _completedProcesses = [];
  
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

  /// Start the scheduler
  Future<void> start() async {
    if (_running) {
      throw FlowError('Scheduler already running');
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
    
    // Cancel all active processes
    for (final scheduled in _activeProcesses.values) {
      scheduled.timer?.cancel();
    }
    _activeProcesses.clear();
  }

  /// Schedule a process
  void schedule(
    ProcessInstance process, {
    required int priority,
    required Future<void> Function() onExecute,
    DateTime? at,
  }) {
    if (!_running) {
      throw FlowError('Scheduler not running');
    }

    final scheduled = ScheduledProcess(
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

  /// Check if can schedule more processes
  bool canSchedule() {
    return _activeProcesses.length < maxProcesses;
  }

  // Private methods

  void _tick() {
    if (!_running) return;

    // Process queues in priority order
    while (canSchedule() && _realtimePriority.isNotEmpty) {
      _executeNext(_realtimePriority);
    }
    
    while (canSchedule() && _highPriority.isNotEmpty) {
      _executeNext(_highPriority);
    }
    
    while (canSchedule() && _normalPriority.isNotEmpty) {
      _executeNext(_normalPriority);
    }
    
    while (canSchedule() && _lowPriority.isNotEmpty) {
      _executeNext(_lowPriority);
    }

    // Clean up completed processes
    _cleanupCompleted();
  }

  void _enqueueProcess(
    ScheduledProcess scheduled,
    Future<void> Function() onExecute,
  ) {
    // Store execution callback
    scheduled.process.variables['__onExecute'] = onExecute;

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

  void _executeNext(Queue<ScheduledProcess> queue) {
    if (queue.isEmpty) return;

    final scheduled = queue.removeFirst();
    final process = scheduled.process;
    
    // Mark as active
    _activeProcesses[process.id] = scheduled;
    process.state = ProcessState.executing;

    // Get execution callback
    final onExecute = process.variables['__onExecute'] as Future<void> Function();
    process.variables.remove('__onExecute');

    // Execute process
    _logger.fine('Executing process ${process.id}');
    
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
      process.lastError = error;
      _totalErrors++;
      _logger.warning('Process ${process.id} failed', error, stackTrace);
    }).whenComplete(() {
      // Remove from active
      _activeProcesses.remove(process.id);
      _completedProcesses.add(scheduled);
    });
  }

  bool _removeFromQueue(Queue<ScheduledProcess> queue, String processId) {
    final toRemove = queue.where((s) => s.process.id == processId).toList();
    for (final scheduled in toRemove) {
      queue.remove(scheduled);
    }
    return toRemove.isNotEmpty;
  }

  void _cleanupCompleted() {
    // Keep only recent completed processes (last 100)
    if (_completedProcesses.length > 100) {
      _completedProcesses.removeRange(0, _completedProcesses.length - 100);
    }
  }
}