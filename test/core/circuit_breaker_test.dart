import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/core/circuit_breaker.dart';

void main() {
  group('TC-046: execute - closed state', () {
    late CircuitBreaker breaker;

    setUp(() {
      breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(
          failureThreshold: 5,
          openDuration: Duration(milliseconds: 100),
        ),
      );
    });

    tearDown(() => breaker.dispose());

    test('TC-046a: success in closed state', () async {
      final result = await breaker.execute(() async => 'ok');
      expect(result, equals('ok'));
      expect(breaker.state, equals(CircuitBreakerState.closed));
      expect(breaker.metrics['totalCalls'], equals(1));
      expect(breaker.metrics['totalSuccesses'], equals(1));
      expect(breaker.failureCount, equals(0));
    });

    test('TC-046b: threshold-1 failures stays closed', () async {
      for (var i = 0; i < 4; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(breaker.state, equals(CircuitBreakerState.closed));
      expect(breaker.failureCount, equals(4));
    });

    test('TC-046c: threshold reached transitions to open', () async {
      for (var i = 0; i < 5; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(breaker.state, equals(CircuitBreakerState.open));
    });
  });

  group('TC-047: execute - open state', () {
    late CircuitBreaker breaker;

    setUp(() async {
      breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(
          failureThreshold: 3,
          openDuration: Duration(milliseconds: 200),
        ),
      );
      // Open the circuit
      for (var i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
    });

    tearDown(() => breaker.dispose());

    test('TC-047a: rejects calls when open', () {
      expect(breaker.state, equals(CircuitBreakerState.open));
      expect(
        () => breaker.execute(() async => 'should not run'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('TC-047b: rejects before openDuration elapses', () async {
      await Future.delayed(Duration(milliseconds: 50));
      expect(
        () => breaker.execute(() async => 'nope'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('TC-047c: CircuitBreakerOpenException has correct fields', () async {
      try {
        await breaker.execute(() async => 'nope');
        fail('Should have thrown');
      } on CircuitBreakerOpenException catch (e) {
        expect(e.toString(), contains('open'));
      }
    });
  });

  group('TC-048: execute - halfOpen state', () {
    late CircuitBreaker breaker;

    setUp(() async {
      breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(
          failureThreshold: 3,
          openDuration: Duration(milliseconds: 100),
        ),
      );
      for (var i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
    });

    tearDown(() => breaker.dispose());

    test('TC-048a: success in halfOpen transitions to closed', () async {
      await Future.delayed(Duration(milliseconds: 150));
      final result = await breaker.execute(() async => 'recovered');
      expect(result, equals('recovered'));
      expect(breaker.state, equals(CircuitBreakerState.closed));
      expect(breaker.failureCount, equals(0));
    });

    test('TC-048b: failure in halfOpen returns to open', () async {
      await Future.delayed(Duration(milliseconds: 150));
      try {
        await breaker.execute(() async => throw Exception('still failing'));
      } catch (_) {}
      expect(breaker.state, equals(CircuitBreakerState.open));
    });

    test('TC-048c: auto transition timing after openDuration', () async {
      await Future.delayed(Duration(milliseconds: 150));
      // Should be able to execute (halfOpen)
      final result = await breaker.execute(() async => 'ok');
      expect(result, equals('ok'));
    });
  });

  group('TC-049: reset', () {
    test('TC-049a: reset from open state', () async {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 3),
      );
      for (var i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(breaker.state, equals(CircuitBreakerState.open));

      breaker.reset();
      expect(breaker.state, equals(CircuitBreakerState.closed));
      expect(breaker.failureCount, equals(0));
      expect(breaker.metrics['totalCalls'], equals(0));
      breaker.dispose();
    });

    test('TC-049b: reset from closed state', () async {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 5),
      );
      await breaker.execute(() async => 'ok');
      breaker.reset();
      expect(breaker.state, equals(CircuitBreakerState.closed));
      expect(breaker.metrics['totalCalls'], equals(0));
      breaker.dispose();
    });

    test('TC-049c: execute works after reset', () async {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 3),
      );
      for (var i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
      breaker.reset();
      final result = await breaker.execute(() async => 'after reset');
      expect(result, equals('after reset'));
      breaker.dispose();
    });
  });

  group('TC-050: dispose', () {
    test('TC-050a: disposes timers', () async {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(
          failureThreshold: 3,
          openDuration: Duration(milliseconds: 100),
        ),
      );
      for (var i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
      breaker.dispose();
      // Should not throw
    });

    test('TC-050b: dispose without active timers', () {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 5),
      );
      breaker.dispose();
    });

    test('TC-050c: execute after dispose still works (no timer transitions)',
        () async {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 5),
      );
      breaker.dispose();
      // Can still execute — dispose only cleans timers
      final result = await breaker.execute(() async => 'ok');
      expect(result, equals('ok'));
    });
  });

  group('TC-051: metrics', () {
    test('TC-051a: initial metrics', () {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 5),
      );
      final m = breaker.metrics;
      expect(m['state'], equals('closed'));
      expect(m['failureCount'], equals(0));
      expect(m['totalCalls'], equals(0));
      breaker.dispose();
    });

    test('TC-051b: metrics after multiple calls', () async {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 20),
      );
      for (var i = 0; i < 10; i++) {
        await breaker.execute(() async => 'ok');
      }
      for (var i = 0; i < 5; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
      final m = breaker.metrics;
      expect(m['totalCalls'], equals(15));
      expect(m['totalSuccesses'], equals(10));
      expect(m['totalFailures'], equals(5));
      breaker.dispose();
    });

    test('TC-051c: open state metrics', () async {
      final breaker = CircuitBreaker(
        name: 'test',
        config: CircuitBreakerConfig(failureThreshold: 3),
      );
      for (var i = 0; i < 3; i++) {
        try {
          await breaker.execute(() async => throw Exception('fail'));
        } catch (_) {}
      }
      expect(breaker.metrics['state'], equals('open'));
      breaker.dispose();
    });
  });

  group('TC-052: CircuitBreakerManager.get', () {
    late CircuitBreakerManager manager;
    setUp(() => manager = CircuitBreakerManager());
    tearDown(() => manager.dispose());

    test('TC-052a: creates new breaker with config', () {
      final breaker = manager.get('api_weather',
          config: CircuitBreakerConfig(failureThreshold: 3));
      expect(breaker, isNotNull);
      expect(breaker.config.failureThreshold, equals(3));
    });

    test('TC-052b: same name returns same instance', () {
      final b1 = manager.get('svc');
      final b2 = manager.get('svc');
      expect(identical(b1, b2), isTrue);
    });

    test('TC-052c: default config when not provided', () {
      final breaker = manager.get('default_svc');
      expect(breaker.config.failureThreshold, equals(5));
    });
  });

  group('TC-053: CircuitBreakerManager.all', () {
    late CircuitBreakerManager manager;
    setUp(() => manager = CircuitBreakerManager());
    tearDown(() => manager.dispose());

    test('TC-053a: returns all breakers', () {
      manager.get('a');
      manager.get('b');
      manager.get('c');
      expect(manager.all.length, equals(3));
    });

    test('TC-053b: returns unmodifiable view', () {
      manager.get('a');
      expect(
        () => manager.all['new'] = CircuitBreaker(
            name: 'x', config: CircuitBreakerConfig()),
        throwsUnsupportedError,
      );
    });

    test('TC-053c: empty when none created', () {
      expect(manager.all, isEmpty);
    });
  });

  group('TC-054: CircuitBreakerManager.reset / resetAll', () {
    late CircuitBreakerManager manager;
    setUp(() => manager = CircuitBreakerManager());
    tearDown(() => manager.dispose());

    test('TC-054a: reset specific breaker', () async {
      final breaker = manager.get('svc');
      await breaker.execute(() async => 'ok');
      manager.reset('svc');
      expect(breaker.metrics['totalCalls'], equals(0));
    });

    test('TC-054b: resetAll resets all breakers', () async {
      final b1 = manager.get('s1');
      final b2 = manager.get('s2');
      await b1.execute(() async => 'ok');
      await b2.execute(() async => 'ok');
      manager.resetAll();
      expect(b1.metrics['totalCalls'], equals(0));
      expect(b2.metrics['totalCalls'], equals(0));
    });

    test('TC-054c: reset nonexistent name is safe', () {
      manager.reset('nonexistent');
    });
  });

  group('TC-055: CircuitBreakerManager.metrics / dispose', () {
    late CircuitBreakerManager manager;
    setUp(() => manager = CircuitBreakerManager());

    test('TC-055a: aggregated metrics', () async {
      final b1 = manager.get('s1');
      await b1.execute(() async => 'ok');
      final m = manager.metrics;
      expect(m.containsKey('s1'), isTrue);
      expect(m['s1']!['totalCalls'], equals(1));
      manager.dispose();
    });

    test('TC-055b: dispose clears all', () {
      manager.get('s1');
      manager.get('s2');
      manager.dispose();
      expect(manager.all, isEmpty);
    });

    test('TC-055c: get after dispose creates new breaker', () {
      manager.get('s1');
      manager.dispose();
      final newBreaker = manager.get('s1');
      expect(newBreaker, isNotNull);
      expect(newBreaker.metrics['totalCalls'], equals(0));
      manager.dispose();
    });
  });
}
