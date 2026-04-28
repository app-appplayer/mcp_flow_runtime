/// Process executor for MCP Flow Runtime

import 'dart:async';

import 'package:logging/logging.dart';

import '../types/flow_types.dart';
import '../types/runtime_types.dart';
import '../errors/flow_errors.dart';
import '../hal/hal_interface.dart';
import '../state/state_manager.dart';
import '../channels/channel_interface.dart';
import 'action_executor.dart';
import 'circuit_breaker.dart';

/// Exception thrown by break action
class BreakException implements Exception {}

/// Exception thrown by continue action
class ContinueException implements Exception {}

/// Exception thrown by return action to terminate process execution
class ReturnException implements Exception {
  final dynamic value;
  ReturnException([this.value]);
}

/// Process executor implementation
class ProcessExecutor {
  final Logger _logger = Logger('ProcessExecutor');
  final HardwareAbstractionLayer hal;
  final StateManager stateManager;
  final Map<String, Channel> channels;
  final Map<String, dynamic> resources;
  final RuntimeConfig config;
  final Map<String, String> configEnvironment;
  final Future<void> Function(String processId, Map<String, dynamic> args)? executeProcessCallback;
  final Future<void> Function(String processId)? stopProcessCallback;
  final CircuitBreakerManager? circuitBreakerManager;
  final McpConfig? mcpConfig;
  FlowDefinition? flowDefinition;

  late final ActionExecutor _actionExecutor;
  final Map<String, int> _actionCounts = {};
  final void Function(String event, [dynamic data])? emitEventCallback;
  final void Function(String processId)? watchdogHeartbeatCallback;

  ProcessExecutor({
    required this.hal,
    required this.stateManager,
    required this.channels,
    required this.resources,
    required this.config,
    Map<String, String>? configEnvironment,
    this.executeProcessCallback,
    this.stopProcessCallback,
    this.emitEventCallback,
    this.watchdogHeartbeatCallback,
    this.circuitBreakerManager,
    this.mcpConfig,
    this.flowDefinition,
  }) : configEnvironment = configEnvironment ?? {} {
    _actionExecutor = ActionExecutor(
      hal: hal,
      stateManager: stateManager,
      channels: channels,
      resources: resources,
      config: config,
      configEnvironment: configEnvironment,
      emitEventCallback: emitEventCallback,
      circuitBreakerManager: circuitBreakerManager,
      mcpConfig: mcpConfig,
      executeProcessCallback: executeProcessCallback,
    );
  }

  /// Get action execution counts
  Map<String, int> get actionCounts => Map.from(_actionCounts);

  /// Look up the ProcessDefinition for a given ProcessInstance
  ProcessDefinition _lookupDefinition(ProcessInstance process) {
    if (flowDefinition == null) {
      throw ConcreteFlowError('RUNTIME_ERROR', 'No flow definition available');
    }
    return flowDefinition!.processes.firstWhere(
      (p) => p.id == process.definitionId,
      orElse: () => throw ConcreteFlowError(
        'RUNTIME_ERROR',
        'Process definition ${process.definitionId} not found',
      ),
    );
  }

  /// Execute a process
  Future<void> execute(ProcessInstance process) async {
    _logger.info('Executing process: ${process.id}');
    process.state = ProcessState.executing;

    final definition = _lookupDefinition(process);

    final context = ExecutionContext(
      process: process,
      globalState: stateManager.toMap(),
      resources: resources,
      channels: channels,
      args: process.localContext, // Pass process variables as args for expression evaluation
      executeProcessCallback: executeProcessCallback,
      stopProcessCallback: stopProcessCallback,
    );

    try {
      // Execute steps
      await _executeSteps(definition.steps, context);

      process.state = ProcessState.completed;
      _logger.info('Process completed: ${process.id}');
    } on ReturnException catch (e) {
      // Return action terminates process normally with optional value
      if (e.value != null && process.localContext.containsKey('__returnValue')) {
        process.localContext['__returnValue'] = e.value;
      }
      process.state = ProcessState.completed;
      _logger.info('Process returned: ${process.id}');
    } catch (error, stackTrace) {
      _logger.warning('Process error: ${process.id}', error, stackTrace);
      process.state = ProcessState.error;
      process.errorMessage = error;

      // Execute error handlers if defined
      var errorHandled = false;
      if (definition.error != null) {
        try {
          _logger.fine('Executing error handlers for process: ${process.id}');
          await _executeSteps(definition.error!, context);
          errorHandled = true;
          _logger.fine('Error handlers completed successfully for process: ${process.id}');
        } catch (errorHandlerError, errorHandlerStackTrace) {
          _logger.warning(
            'Error handler failed for process: ${process.id}',
            errorHandlerError,
            errorHandlerStackTrace,
          );
        }
      }

      // Re-throw original error only if not handled
      if (!errorHandled) {
        rethrow;
      } else {
        // Change state to completed if error was handled
        process.state = ProcessState.completed;
        _logger.info('Process completed with handled error: ${process.id}');
      }
    } finally {
      // Execute finally handlers if defined
      if (definition.finally$ != null) {
        try {
          _logger.fine('Executing finally handlers for process: ${process.id}');
          await _executeSteps(definition.finally$!, context);
        } catch (finallyError, finallyStackTrace) {
          _logger.warning(
            'Finally handler failed for process: ${process.id}',
            finallyError,
            finallyStackTrace,
          );
        }
      }

      // Note: We don't sync globalState back to stateManager here
      // because it may contain stale values if nested processes
      // have modified the state. State updates should only happen
      // through setState actions.
    }

    // Handle loop processes
    if (definition.loop && process.state == ProcessState.completed) {
      _logger.fine('Process ${process.id} is configured to loop, restarting...');
      process.state = ProcessState.ready;
      // The scheduler will handle re-execution
    }
  }

  /// Execute a list of action steps
  Future<void> _executeSteps(
    List<ActionDefinition> steps,
    ExecutionContext context,
  ) async {
    for (final step in steps) {
      // Some actions use 'condition' field for their own purposes
      // Don't treat it as an execution condition for these actions
      final actionsWithSpecialCondition = {
        'if', 'while', 'waitUntil'
      };
      
      // Check condition only if it's not a special action
      if (step.condition != null && !actionsWithSpecialCondition.contains(step.action)) {
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
    
    // Send watchdog heartbeat before action execution
    watchdogHeartbeatCallback?.call(context.process.id);
    
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
        // Handle try/catch/finally directly in ProcessExecutor
        await _executeTry(action, context);
        return;
        
      case 'break':
        throw BreakException();
        
      case 'continue':
        throw ContinueException();
    }

    // Execute regular action with timeout and retry
    final timeout = action.timeout != null
        ? Duration(milliseconds: action.timeout!)
        : null;

    final startTime = DateTime.now();
    
    try {
      final result = await _executeWithRetry(
        () => _actionExecutor.execute(action, context),
        retry: action.retry,
        timeout: timeout,
        context: context,
      );

      final executionTime = DateTime.now().difference(startTime);

      // Bind result if requested
      if (action.bindTo != null && result != null) {
        // If the variable is defined in state, set it globally via state manager
        if (stateManager.hasVariable(action.bindTo!)) {
          await stateManager.set(action.bindTo!, result);
          // Also update context's globalState to keep it in sync
          context.globalState[action.bindTo!] = result;
        } else {
          // Store in process-local variables
          context.setVariable(action.bindTo!, result);
        }
      }

      // Success recorded via action count at line 210
    } catch (error, stackTrace) {
      final executionTime = DateTime.now().difference(startTime);
      _logger.warning('Action failed: ${action.action}', error, stackTrace);

      rethrow;
    }
  }

  /// Execute with retry logic
  Future<T> _executeWithRetry<T>(
    Future<T> Function() fn, {
    RetryConfig? retry,
    Duration? timeout,
    ExecutionContext? context,
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

    while (attempts < retry.count) {
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

        if (attempts >= retry.count) {
          break;
        }

        // Check retry conditions
        if (retry.retryConditions != null && context != null) {
          bool shouldRetry = false;
          for (final condition in retry.retryConditions!) {
            try {
              // Add error context for condition evaluation
              context.process.localContext['retryError'] = {
                'message': error.toString(),
                'type': error.runtimeType.toString(),
                'attempt': attempts,
              };
              
              final result = await _actionExecutor.evaluateCondition(condition, context);
              if (result) {
                shouldRetry = true;
                break;
              }
            } catch (e) {
              _logger.warning('Failed to evaluate retry condition: $e');
            } finally {
              // Clean up error context
              context.process.localContext.remove('retryError');
            }
          }
          
          if (!shouldRetry && retry.retryConditions!.isNotEmpty) {
            _logger.fine('Retry conditions not met, stopping retry');
            break;
          }
        }

        // Check stop conditions
        if (retry.stopConditions != null && context != null) {
          bool shouldStop = false;
          for (final condition in retry.stopConditions!) {
            try {
              // Add error context for condition evaluation
              context.process.localContext['retryError'] = {
                'message': error.toString(),
                'type': error.runtimeType.toString(),
                'attempt': attempts,
              };
              
              final result = await _actionExecutor.evaluateCondition(condition, context);
              if (result) {
                shouldStop = true;
                _logger.fine('Stop condition met, stopping retry');
                break;
              }
            } catch (e) {
              _logger.warning('Failed to evaluate stop condition: $e');
            } finally {
              // Clean up error context
              context.process.localContext.remove('retryError');
            }
          }
          
          if (shouldStop) {
            break;
          }
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
    // Check for condition at top level first (per spec), then fallback to params
    final condition = action.condition ?? action.params?['condition'] as String?;
    if (condition == null) {
      throw ProcessExecutionError(
        'If action requires condition',
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
    // Check for condition at top level first (per spec), then fallback to params
    final condition = action.condition ?? action.params?['condition'] as String?;
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

    while (true) {
      // Send watchdog heartbeat for long-running loop
      watchdogHeartbeatCallback?.call(context.process.id);
      
      // Refresh global state from state manager before evaluating condition
      context.globalState.clear();
      context.globalState.addAll(stateManager.toMap());
      
      // Evaluate condition with fresh state
      if (!await _actionExecutor.evaluateCondition(condition, context)) {
        break;
      }
      
      if (iterations >= maxIterations) {
        throw ProcessExecutionError(
          'While loop exceeded maximum iterations ($maxIterations)',
          processId: context.process.id,
          actionType: 'while',
        );
      }

      try {
        await _executeSteps(action.do$!, context);
      } on BreakException {
        break;
      } on ContinueException {
        // Continue to next iteration
      }
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
         step > 0 ? i <= to : i >= to; 
         i += step) {
      // Send watchdog heartbeat for long-running loop
      watchdogHeartbeatCallback?.call(context.process.id);
      
      // Set loop variable in global scope so expressions can access it
      context.setVariable(variable, i, global: true);
      try {
        await _executeSteps(action.do$!, context);
      } on BreakException {
        break;
      } on ContinueException {
        // Continue to next iteration
      }
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

    // Strip the = prefix if present (per spec)
    final valueExpr = action.value.toString();
    final expr = valueExpr.startsWith('=') ? valueExpr.substring(1) : valueExpr;
    final value = await _actionExecutor.evaluateExpression(
      expr,
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
    // Support both 'branches' from ActionDefinition and direct array format from params
    final branches = action.branches;
    final paramBranches = action.params?['branches'] as List<dynamic>?;
    
    if (branches == null && paramBranches == null) {
      return;
    }

    final futures = <Future<void>>[];
    
    if (branches != null) {
      // Use typed branches from ActionDefinition
      for (final branch in branches) {
        final branchContext = context.createChildContext(
          additionalVars: {'branchId': branch.id},
        );
        futures.add(_executeSteps(branch.steps, branchContext));
      }
    } else if (paramBranches != null) {
      // Support simple array of steps arrays (for testing compatibility)
      for (int i = 0; i < paramBranches.length; i++) {
        final branchSteps = paramBranches[i];
        if (branchSteps is List) {
          final branchContext = context.createChildContext(
            additionalVars: {'branchId': 'branch_$i'},
          );
          // Convert to ActionDefinition list
          final steps = branchSteps.map((step) {
            if (step is Map<String, dynamic>) {
              return ActionDefinition.fromJson(step);
            }
            return step as ActionDefinition;
          }).toList();
          futures.add(_executeSteps(steps, branchContext));
        }
      }
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
    // Use the new try/catch/finally fields
    final trySteps = action.try$ ?? action.do$;
    final catchSteps = action.catch$ ?? action.else$;
    final finallySteps = action.finally$;
    
    if (trySteps == null) {
      return;
    }

    try {
      // Execute try steps
      await _executeSteps(trySteps, context);
    } catch (error) {
      
      if (action.params?['catchVar'] != null) {
        // Bind error to variable
        final errorVar = action.params!['catchVar'] as String;
        context.setVariable(errorVar, error.toString());
      }
      
      // Make error info available to catch block
      context.process.localContext['catchError'] = {
        'message': error.toString(),
        'type': error.runtimeType.toString(),
      };

      if (catchSteps != null) {
        // Execute catch steps
        await _executeSteps(catchSteps, context);
        // Clean up error variable
        context.process.localContext.remove('catchError');
      } else {
        rethrow;
      }
    } finally {
      if (finallySteps != null) {
        // Execute finally steps
        await _executeSteps(finallySteps, context);
      }
    }
  }

  /// Handle action errors based on error handling configuration
  Future<void> _handleActionError(
    ActionDefinition action,
    dynamic error,
    ExecutionContext context,
  ) async {
    try {
      // Log error details
      _logger.warning('Handling error for action ${action.action}: $error');
      
      // Basic error handling (simplified implementation)
      _logger.info('Error handling applied for action ${action.action}');
      
    } catch (e) {
      _logger.severe('Failed to handle error for action ${action.action}: $e');
      throw Exception('Error handling failed: $e');
    }
  }
}

/// Exception for process abort
class ProcessAbortException implements Exception {
  final String message;
  ProcessAbortException(this.message);
  
  @override
  String toString() => 'ProcessAbortException: $message';
}