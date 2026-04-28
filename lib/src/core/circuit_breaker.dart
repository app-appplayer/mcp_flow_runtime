/// Circuit breaker pattern implementation for MCP Flow DSL
/// 
/// Implements circuit breaker to prevent cascading failures
import 'dart:async';
import 'package:logging/logging.dart';

enum CircuitBreakerState {
  closed,    // Normal operation
  open,      // Failure threshold exceeded, rejecting calls
  halfOpen,  // Testing if service recovered
}

class CircuitBreakerConfig {
  final int failureThreshold;
  final Duration openDuration;
  final Duration resetTimeout;
  final bool monitorTimeout;
  
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.openDuration = const Duration(seconds: 60),
    this.resetTimeout = const Duration(seconds: 120),
    this.monitorTimeout = true,
  });
}

class CircuitBreaker {
  final String name;
  final CircuitBreakerConfig config;
  final Logger _logger;
  
  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _openedAt;
  Timer? _halfOpenTimer;
  Timer? _resetTimer;
  
  // Metrics
  int _totalCalls = 0;
  int _totalFailures = 0;
  int _totalSuccesses = 0;
  int _rejectedCalls = 0;
  
  CircuitBreaker({
    required this.name,
    CircuitBreakerConfig? config,
  }) : config = config ?? const CircuitBreakerConfig(),
       _logger = Logger('CircuitBreaker.$name');
  
  CircuitBreakerState get state => _state;
  
  int get failureCount => _failureCount;
  int get successCount => _successCount;
  
  Map<String, dynamic> get metrics => {
    'state': _state.name,
    'failureCount': _failureCount,
    'successCount': _successCount,
    'totalCalls': _totalCalls,
    'totalFailures': _totalFailures,
    'totalSuccesses': _totalSuccesses,
    'rejectedCalls': _rejectedCalls,
    'lastFailureTime': _lastFailureTime?.toIso8601String(),
    'openedAt': _openedAt?.toIso8601String(),
  };
  
  /// Execute a function with circuit breaker protection
  Future<T> execute<T>(Future<T> Function() action) async {
    _totalCalls++;
    
    // Check if circuit is open
    if (_state == CircuitBreakerState.open) {
      // Check if we should transition to half-open
      if (_shouldTransitionToHalfOpen()) {
        _transitionToHalfOpen();
      } else {
        _rejectedCalls++;
        throw CircuitBreakerOpenException(
          'Circuit breaker is open for $name',
          openedAt: _openedAt,
          willRetryAt: _openedAt?.add(config.openDuration),
        );
      }
    }
    
    try {
      // Execute the action
      final result = await action();
      _onSuccess();
      return result;
    } catch (e, stackTrace) {
      _onFailure(e, stackTrace);
      rethrow;
    }
  }
  
  /// Record a successful call
  void _onSuccess() {
    _totalSuccesses++;
    _successCount++;
    
    if (_state == CircuitBreakerState.halfOpen) {
      // Success in half-open state transitions to closed
      _logger.info('Circuit breaker $name closing after successful half-open test');
      _transitionToClosed();
    } else if (_state == CircuitBreakerState.closed) {
      // Reset failure count after success in closed state
      if (_failureCount > 0) {
        _failureCount = 0;
      }
      
      // Reset the reset timer
      _resetTimer?.cancel();
      _resetTimer = Timer(config.resetTimeout, () {
        if (_failureCount > 0) {
          _failureCount = 0;
          _logger.fine('Circuit breaker $name failure count reset after timeout');
        }
      });
    }
  }
  
  /// Record a failed call
  void _onFailure(dynamic error, StackTrace stackTrace) {
    _totalFailures++;
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    _logger.warning(
      'Circuit breaker $name recorded failure $_failureCount/${config.failureThreshold}',
      error,
      stackTrace,
    );
    
    if (_state == CircuitBreakerState.halfOpen) {
      // Failure in half-open state immediately opens the circuit
      _logger.warning('Circuit breaker $name opening after half-open test failure');
      _transitionToOpen();
    } else if (_state == CircuitBreakerState.closed) {
      // Check if we've exceeded the failure threshold
      if (_failureCount >= config.failureThreshold) {
        _logger.warning(
          'Circuit breaker $name opening after $_failureCount failures',
        );
        _transitionToOpen();
      }
    }
  }
  
  /// Check if we should transition to half-open state
  bool _shouldTransitionToHalfOpen() {
    if (_state != CircuitBreakerState.open || _openedAt == null) {
      return false;
    }
    
    final now = DateTime.now();
    return now.difference(_openedAt!).compareTo(config.openDuration) >= 0;
  }
  
  /// Transition to closed state
  void _transitionToClosed() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _successCount = 0;
    _openedAt = null;
    _halfOpenTimer?.cancel();
    _halfOpenTimer = null;
  }
  
  /// Transition to open state
  void _transitionToOpen() {
    _state = CircuitBreakerState.open;
    _openedAt = DateTime.now();
    _successCount = 0;
    
    // Schedule transition to half-open
    _halfOpenTimer?.cancel();
    _halfOpenTimer = Timer(config.openDuration, () {
      if (_state == CircuitBreakerState.open) {
        _logger.info('Circuit breaker $name transitioning to half-open');
        _transitionToHalfOpen();
      }
    });
  }
  
  /// Transition to half-open state
  void _transitionToHalfOpen() {
    _state = CircuitBreakerState.halfOpen;
    _successCount = 0;
    _failureCount = 0;
  }
  
  /// Reset the circuit breaker
  void reset() {
    _logger.info('Circuit breaker $name reset');
    _transitionToClosed();
    _totalCalls = 0;
    _totalFailures = 0;
    _totalSuccesses = 0;
    _rejectedCalls = 0;
    _lastFailureTime = null;
    _resetTimer?.cancel();
    _resetTimer = null;
  }
  
  /// Dispose of resources
  void dispose() {
    _halfOpenTimer?.cancel();
    _resetTimer?.cancel();
  }
}

/// Exception thrown when circuit breaker is open
class CircuitBreakerOpenException implements Exception {
  final String message;
  final DateTime? openedAt;
  final DateTime? willRetryAt;
  
  CircuitBreakerOpenException(
    this.message, {
    this.openedAt,
    this.willRetryAt,
  });
  
  @override
  String toString() {
    var msg = message;
    if (openedAt != null) {
      msg += ' (opened at ${openedAt!.toIso8601String()})';
    }
    if (willRetryAt != null) {
      msg += ' (will retry at ${willRetryAt!.toIso8601String()})';
    }
    return 'CircuitBreakerOpenException: $msg';
  }
}

/// Circuit breaker manager for managing multiple circuit breakers
class CircuitBreakerManager {
  final Map<String, CircuitBreaker> _breakers = {};
  final Logger _logger = Logger('CircuitBreakerManager');
  
  /// Get or create a circuit breaker
  CircuitBreaker get(String name, {CircuitBreakerConfig? config}) {
    return _breakers.putIfAbsent(
      name,
      () {
        _logger.info('Creating circuit breaker: $name');
        return CircuitBreaker(name: name, config: config);
      },
    );
  }
  
  /// Get all circuit breakers
  Map<String, CircuitBreaker> get all => Map.unmodifiable(_breakers);
  
  /// Get metrics for all circuit breakers
  Map<String, Map<String, dynamic>> get metrics => {
    for (final entry in _breakers.entries)
      entry.key: entry.value.metrics,
  };
  
  /// Reset a specific circuit breaker
  void reset(String name) {
    _breakers[name]?.reset();
  }
  
  /// Reset all circuit breakers
  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }
  
  /// Dispose all circuit breakers
  void dispose() {
    for (final breaker in _breakers.values) {
      breaker.dispose();
    }
    _breakers.clear();
  }
}