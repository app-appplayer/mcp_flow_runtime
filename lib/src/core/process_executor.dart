/// Process executor for MCP Flow Runtime

import 'dart:async';

import 'package:logging/logging.dart';

import '../types/flow_types.dart';
import '../types/runtime_types.dart';
import '../errors/flow_errors.dart';
import '../hal/hal_interface.dart';
import '../state/state_manager.dart';
import 'action_executor.dart';

/// Process executor implementation
class ProcessExecutor {
  final Logger _logger = Logger('ProcessExecutor');
  final HardwareAbstractionLayer hal;
  final StateManager stateManager;
  final Map<String, StreamController> channels;
  final Map<String, dynamic> resources;
  final RuntimeConfig config;
  
  late final ActionExecutor _actionExecutor;
  final Map<String, int> _actionCounts = {};

  ProcessExecutor({
    required this.hal,
    required this.stateManager,
    required this.channels,
    required this.resources,
    required this.config,
  }) {
    _actionExecutor = ActionExecutor(
      hal: hal,
      stateManager: stateManager,
      channels: channels,
      resources: resources,
      config: config,
    );
  }

  /// Get action execution counts
  Map<String, int> get actionCounts => Map.from(_actionCounts);

  /// Execute a process
  Future<void> execute(ProcessInstance process) async {
    _logger.info('Executing process: ${process.id}');
    process.state = ProcessState.executing;

    final context = ExecutionContext(
      process: process,
      globalState: stateManager.toMap(),
      resources: resources,
      channels: channels,
    );

    try {
      // Execute steps
      await _executeSteps(process.definition.steps, context);
      
      process.state = ProcessState.completed;
      _logger.info('Process completed: ${process.id}');
    } catch (error, stackTrace) {
      _logger.warning('Process error: ${process.id}', error, stackTrace);
      process.state = ProcessState.error;
      process.lastError = error;

      // Execute error handlers if defined
      if (process.definition.error != null) {
        try {
          _logger.fine('Executing error handlers for process: ${process.id}');
          await _executeSteps(process.definition.error!, context);
        } catch (errorHandlerError, errorHandlerStackTrace) {
          _logger.warning(
            'Error handler failed for process: ${process.id}',
            errorHandlerError,
            errorHandlerStackTrace,
          );
        }
      }

      // Re-throw original error
      rethrow;
    } finally {
      // Execute finally handlers if defined
      if (process.definition.finally$ != null) {
        try {
          _logger.fine('Executing finally handlers for process: ${process.id}');
          await _executeSteps(process.definition.finally$!, context);
        } catch (finallyError, finallyStackTrace) {
          _logger.warning(
            'Finally handler failed for process: ${process.id}',
            finallyError,
            finallyStackTrace,
          );
        }
      }

      // Update global state with any changes
      for (final entry in context.globalState.entries) {
        if (stateManager.hasVariable(entry.key)) {
          await stateManager.set(entry.key, entry.value);
        }
      }
    }

    // Handle loop processes
    if (process.definition.loop && process.state == ProcessState.completed) {
      _logger.fine('Process ${process.id} is configured to loop, restarting...');
      process.state = ProcessState.ready;
      process.retryCount++;
      // The scheduler will handle re-execution
    }
  }

  /// Execute a list of action steps
  Future<void> _executeSteps(
    List<ActionDefinition> steps,
    ExecutionContext context,
  ) async {
    for (final step in steps) {
      // Check condition
      if (step.condition != null) {
        final shouldExecute = await _actionExecutor.evaluateCondition(
          step.condition!,
          context,
        );
        if (!shouldExecute) {
          _logger.fine('Skipping action ${step.action} due to condition');
          continue;
        }
      }

      // Execute action
      await _executeAction(step, context);
    }
  }

  /// Execute a single action
  Future<void> _executeAction(
    ActionDefinition action,
    ExecutionContext context,
  ) async {
    _logger.fine('Executing action: ${action.action}');
    
    // Track action count
    _actionCounts[action.action] = (_actionCounts[action.action] ?? 0) + 1;

    // Handle control flow actions
    switch (action.action) {
      case 'if':
        await _executeIf(action, context);
        return;
        
      case 'while':
        await _executeWhile(action, context);
        return;
        
      case 'for':
        await _executeFor(action, context);
        return;
        
      case 'switch':
        await _executeSwitch(action, context);
        return;
        
      case 'parallel':
        await _executeParallel(action, context);
        return;
        
      case 'try':
        await _executeTry(action, context);
        return;
    }

    // Execute regular action with timeout and retry
    final timeout = action.timeout != null
        ? Duration(milliseconds: action.timeout!)
        : null;

    try {
      final result = await _executeWithRetry(
        () => _actionExecutor.execute(action, context),
        retry: action.retry,
        timeout: timeout,
      );

      // Bind result if requested
      if (action.bindTo != null && result != null) {
        context.setVariable(action.bindTo!, result);
      }

      // Record successful execution
      context.process.actionResults.add(ActionResult(
        actionType: action.action,
        status: ActionStatus.success,
        result: result,
        timestamp: DateTime.now(),
        executionTime: Duration.zero, // TODO: Track actual execution time
      ));
    } catch (error, stackTrace) {
      _logger.warning('Action failed: ${action.action}', error, stackTrace);
      
      // Record failed execution
      context.process.actionResults.add(ActionResult(
        actionType: action.action,
        status: ActionStatus.error,
        error: error,
        timestamp: DateTime.now(),
        executionTime: Duration.zero,
      ));

      // Handle error based on configuration
      if (action.errorHandling != null) {
        // TODO: Implement error handling strategies
        _logger.fine('Applying error handling for action: ${action.action}');
      }

      rethrow;
    }
  }

  /// Execute with retry logic
  Future<T> _executeWithRetry<T>(
    Future<T> Function() fn, {
    RetryConfig? retry,
    Duration? timeout,
  }) async {
    if (retry == null || retry.count <= 0) {
      // No retry, just execute with timeout
      if (timeout != null) {
        return fn().timeout(
          timeout,
          onTimeout: () => throw TimeoutError(
            'Action timed out',
            timeout: timeout,
            operation: 'action',
          ),
        );
      }
      return fn();
    }

    int attempts = 0;
    dynamic lastError;
    int delayMs = retry.delayMs;

    while (attempts <= retry.count) {
      try {
        if (timeout != null) {
          return await fn().timeout(
            timeout,
            onTimeout: () => throw TimeoutError(
              'Action timed out',
              timeout: timeout,
              operation: 'action',
            ),
          );
        }
        return await fn();
      } catch (error) {
        lastError = error;
        attempts++;

        if (attempts > retry.count) {
          break;
        }

        // Check retry conditions
        if (retry.retryConditions != null) {
          // TODO: Evaluate retry conditions
        }

        // Check stop conditions
        if (retry.stopConditions != null) {
          // TODO: Evaluate stop conditions
        }

        _logger.fine('Retry attempt $attempts after ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));

        // Apply backoff
        if (retry.backoff == 'exponential') {
          delayMs *= 2;
          if (retry.maxDelayMs != null && delayMs > retry.maxDelayMs!) {
            delayMs = retry.maxDelayMs!;
          }
        }
      }
    }

    throw lastError;
  }

  // Control flow implementations

  Future<void> _executeIf(ActionDefinition action, ExecutionContext context) async {
    final condition = action.params?['condition'] as String?;
    if (condition == null) {
      throw ProcessExecutionError(
        'If action requires condition parameter',
        processId: context.process.id,
        actionType: 'if',
      );
    }

    final result = await _actionExecutor.evaluateCondition(condition, context);
    
    if (result && action.then != null) {
      await _executeSteps(action.then!, context);
    } else if (!result && action.else$ != null) {
      await _executeSteps(action.else$!, context);
    }
  }

  Future<void> _executeWhile(ActionDefinition action, ExecutionContext context) async {
    final condition = action.params?['condition'] as String?;
    if (condition == null) {
      throw ProcessExecutionError(
        'While action requires condition parameter',
        processId: context.process.id,
        actionType: 'while',
      );
    }

    if (action.do$ == null) {
      return;
    }

    int iterations = 0;
    final maxIterations = action.params?['maxIterations'] as int? ?? 10000;

    while (await _actionExecutor.evaluateCondition(condition, context)) {
      if (iterations >= maxIterations) {
        throw ProcessExecutionError(
          'While loop exceeded maximum iterations ($maxIterations)',
          processId: context.process.id,
          actionType: 'while',
        );
      }

      await _executeSteps(action.do$!, context);
      iterations++;
    }
  }

  Future<void> _executeFor(ActionDefinition action, ExecutionContext context) async {
    final variable = action.params?['variable'] as String?;
    final from = action.params?['from'] as num? ?? 0;
    final to = action.params?['to'] as num?;
    final step = action.params?['step'] as num? ?? 1;

    if (variable == null || to == null) {
      throw ProcessExecutionError(
        'For action requires variable and to parameters',
        processId: context.process.id,
        actionType: 'for',
      );
    }

    if (action.do$ == null) {
      return;
    }

    for (num i = from; 
         step > 0 ? i < to : i > to; 
         i += step) {
      context.setVariable(variable, i);
      await _executeSteps(action.do$!, context);
    }
  }

  Future<void> _executeSwitch(ActionDefinition action, ExecutionContext context) async {
    if (action.value == null || action.cases == null) {
      throw ProcessExecutionError(
        'Switch action requires value and cases',
        processId: context.process.id,
        actionType: 'switch',
      );
    }

    final value = await _actionExecutor.evaluateExpression(
      action.value.toString(),
      context,
    );

    // Find matching case
    for (final entry in action.cases!.entries) {
      if (entry.key == 'default') continue;
      
      if (entry.key == value.toString()) {
        await _executeSteps(entry.value, context);
        return;
      }
    }

    // Execute default case if exists
    if (action.cases!.containsKey('default')) {
      await _executeSteps(action.cases!['default']!, context);
    }
  }

  Future<void> _executeParallel(ActionDefinition action, ExecutionContext context) async {
    if (action.branches == null || action.branches!.isEmpty) {
      return;
    }

    final futures = <Future<void>>[];
    
    for (final branch in action.branches!) {
      // Create child context for each branch
      final branchContext = context.createChildContext(
        additionalVars: {'branchId': branch.id},
      );
      
      futures.add(_executeSteps(branch.steps, branchContext));
    }

    // Execute based on join strategy
    switch (action.join ?? 'all') {
      case 'all':
        await Future.wait(futures);
        break;
        
      case 'any':
        await Future.any(futures);
        break;
        
      case 'race':
        try {
          await Future.any(futures);
        } catch (_) {
          // Ignore errors in race mode
        }
        break;
        
      default:
        await Future.wait(futures);
    }
  }

  Future<void> _executeTry(ActionDefinition action, ExecutionContext context) async {
    if (action.do$ == null) {
      return;
    }

    try {
      await _executeSteps(action.do$!, context);
    } catch (error) {
      if (action.params?['catch'] != null) {
        // Bind error to variable
        final errorVar = action.params!['catch'] as String;
        context.setVariable(errorVar, error.toString());
      }

      if (action.else$ != null) {
        await _executeSteps(action.else$!, context);
      } else {
        rethrow;
      }
    } finally {
      if (action.params?['finally'] != null) {
        final finallySteps = action.params!['finally'] as List<ActionDefinition>;
        await _executeSteps(finallySteps, context);
      }
    }
  }
}