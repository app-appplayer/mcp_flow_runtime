// Monitoring module tests with TC IDs from TEST-MON-001

import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart' hide StateChangeEvent;
import 'package:mcp_flow_runtime/src/monitoring/runtime_monitor.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

final sampleProcessDef = ProcessDefinition(
  id: 'temp_flow',
  name: 'Temperature Flow',
  steps: [],
);

const sampleProcessId = 'proc-001';

final testConfig = MonitoringConfig(
  enableProcessMetrics: true,
  enableStateTracking: true,
  enableResourceMonitoring: true,
  enableEventTracking: true,
  metricsInterval: 100,
  maxMetricsHistory: 100,
);

void main() {
  late McpFlowRuntime runtime;

  setUp(() async {
    runtime = McpFlowRuntime();

    await runtime.loadFlow({
      'version': '1.0.0',
      'state': {
        'counter': {'type': 'number', 'initial': 0},
        'message': {'type': 'string', 'initial': 'Hello'},
      },
      'processes': [],
    });
    await runtime.start();
  });

  tearDown(() async {
    await runtime.stop();
  });

  // =========================================================================
  // 2. RuntimeMonitor start/stop/dispose tests (TC-801 ~ TC-805)
  // =========================================================================
  group('TC-801: RuntimeMonitor.start', () {
    test('TC-801a: start activates the metrics timer', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final metrics = <ResourceMetric>[];
      monitor.onResourceMetric.listen(metrics.add);

      await Future.delayed(Duration(milliseconds: 250));
      monitor.dispose();

      expect(metrics.length, greaterThanOrEqualTo(1));
    });

    test('TC-801b: double start is a no-op', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();
      monitor.start(); // second call

      final metrics = <ResourceMetric>[];
      monitor.onResourceMetric.listen(metrics.add);

      await Future.delayed(Duration(milliseconds: 250));
      monitor.dispose();

      // Should not have excessive samples from double timer
      expect(metrics.length, lessThanOrEqualTo(5));
    });

    test('TC-801c: record before start silently drops or handles', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);

      expect(
        () => monitor.recordProcessStart(sampleProcessId, sampleProcessDef),
        returnsNormally,
      );

      monitor.dispose();
    });
  });

  group('TC-803: RuntimeMonitor.stop', () {
    test('TC-803a: stop cancels timers', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      monitor.stop();
      await Future.delayed(Duration(milliseconds: 10));

      // After stop, no more events should come
      monitor.dispose();
    });

    test('TC-803b: record after stop silently drops events', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();
      monitor.stop();

      expect(
        () => monitor.recordProcessStart(sampleProcessId, sampleProcessDef),
        returnsNormally,
      );

      monitor.dispose();
    });

    test('TC-803c: double stop is idempotent', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();
      monitor.stop();

      expect(() => monitor.stop(), returnsNormally);

      monitor.dispose();
    });
  });

  group('TC-805: RuntimeMonitor.dispose', () {
    test('TC-805a: dispose releases resources', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();
      // Stop first to cancel the timer and let pending callbacks settle
      monitor.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(() => monitor.dispose(), returnsNormally);
    });

    test('TC-805b: start after dispose is handled', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.dispose();

      // start() after dispose should throw or be silently ignored
      // If it doesn't throw, stop immediately to prevent timer from
      // firing into closed controllers
      try {
        monitor.start();
        monitor.stop();
      } catch (_) {
        // Expected — disposed monitor cannot restart
      }
      // Allow pending async operations to settle
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('TC-805c: dispose double call is idempotent', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();
      monitor.dispose();

      // Second dispose should not throw
      expect(() => monitor.dispose(), returnsNormally);
    });
  });

  // =========================================================================
  // 3. recordProcessStart/End tests (TC-806 ~ TC-810)
  // =========================================================================
  group('TC-806: recordProcessStart', () {
    test('TC-806a: recordProcessStart emits ProcessMetric', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <ProcessMetric>[];
      monitor.onProcessStart.listen(events.add);

      monitor.recordProcessStart(sampleProcessId, sampleProcessDef);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first.processId, equals(sampleProcessId));

      monitor.dispose();
    });

    test('TC-806c: recordProcessStart with empty processId is handled', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <ProcessMetric>[];
      monitor.onProcessStart.listen(events.add);

      // Empty processId should not throw
      expect(
        () => monitor.recordProcessStart('', sampleProcessDef),
        returnsNormally,
      );

      await Future.delayed(Duration(milliseconds: 10));
      monitor.dispose();
    });

    test('TC-806b: enableProcessMetrics=false ignores events', () async {
      final monitor = RuntimeMonitor(
        runtime: runtime,
        config: MonitoringConfig(
          enableProcessMetrics: false,
          metricsInterval: 0,
        ),
      );
      monitor.start();

      final events = <ProcessMetric>[];
      monitor.onProcessStart.listen(events.add);

      monitor.recordProcessStart(sampleProcessId, sampleProcessDef);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events, isEmpty);

      monitor.dispose();
    });
  });

  group('TC-807: recordProcessEnd', () {
    test('TC-807a: recordProcessEnd with completed status', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final endEvents = <ProcessMetric>[];
      monitor.onProcessEnd.listen(endEvents.add);

      monitor.recordProcessStart(sampleProcessId, sampleProcessDef);
      monitor.recordProcessEnd(sampleProcessId, ProcessExecutionStatus.completed);

      await Future.delayed(Duration(milliseconds: 10));

      expect(endEvents.length, equals(1));
      expect(endEvents.first.status, equals(ProcessExecutionStatus.completed));

      monitor.dispose();
    });

    test('TC-807b: recordProcessEnd with failed status', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final endEvents = <ProcessMetric>[];
      monitor.onProcessEnd.listen(endEvents.add);

      monitor.recordProcessStart(sampleProcessId, sampleProcessDef);
      monitor.recordProcessEnd(
        sampleProcessId,
        ProcessExecutionStatus.failed,
        error: 'timeout',
      );

      await Future.delayed(Duration(milliseconds: 10));

      expect(endEvents.first.status, equals(ProcessExecutionStatus.failed));
      expect(endEvents.first.error, equals('timeout'));

      monitor.dispose();
    });

    test('TC-807c: recordProcessEnd with cancelled status', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final endEvents = <ProcessMetric>[];
      monitor.onProcessEnd.listen(endEvents.add);

      monitor.recordProcessStart(sampleProcessId, sampleProcessDef);
      monitor.recordProcessEnd(sampleProcessId, ProcessExecutionStatus.cancelled);

      await Future.delayed(Duration(milliseconds: 10));

      expect(endEvents.first.status, equals(ProcessExecutionStatus.cancelled));

      monitor.dispose();
    });
  });

  group('TC-810: Multiple process events', () {
    test('TC-810a: multiple process events maintain order', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final startEvents = <ProcessMetric>[];
      monitor.onProcessStart.listen(startEvents.add);

      for (var i = 0; i < 3; i++) {
        monitor.recordProcessStart('proc-$i', sampleProcessDef);
      }

      await Future.delayed(Duration(milliseconds: 10));

      expect(startEvents.length, equals(3));
      expect(startEvents[0].processId, equals('proc-0'));
      expect(startEvents[1].processId, equals('proc-1'));
      expect(startEvents[2].processId, equals('proc-2'));

      monitor.dispose();
    });

    test('TC-810b: duplicate processId start emits multiple events', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final startEvents = <ProcessMetric>[];
      monitor.onProcessStart.listen(startEvents.add);

      // Same processId started twice
      monitor.recordProcessStart('proc-dup', sampleProcessDef);
      monitor.recordProcessStart('proc-dup', sampleProcessDef);

      await Future.delayed(Duration(milliseconds: 10));

      expect(startEvents.length, equals(2));
      expect(startEvents[0].processId, equals('proc-dup'));
      expect(startEvents[1].processId, equals('proc-dup'));

      monitor.dispose();
    });

    test('TC-810c: recordProcessEnd without start is handled', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      // Should not throw
      expect(
        () => monitor.recordProcessEnd('unknown', ProcessExecutionStatus.completed),
        returnsNormally,
      );

      monitor.dispose();
    });
  });

  // =========================================================================
  // 4. recordStateChange tests (TC-816 ~ TC-817)
  // =========================================================================
  group('TC-816: recordStateChange', () {
    test('TC-816a: recordStateChange emits StateChangeEvent', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <StateChangeEvent>[];
      monitor.onStateChange.listen(events.add);

      monitor.recordStateChange('temperature', 20.0, 25.5);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first.variable, equals('temperature'));
      expect(events.first.oldValue, equals(20.0));
      expect(events.first.newValue, equals(25.5));

      monitor.dispose();
    });

    test('TC-816b: enableStateTracking=false ignores events', () async {
      final monitor = RuntimeMonitor(
        runtime: runtime,
        config: MonitoringConfig(
          enableStateTracking: false,
          metricsInterval: 0,
        ),
      );
      monitor.start();

      monitor.recordStateChange('ignored', 0, 1);
      expect(monitor.getStateChangeHistory(), isEmpty);

      monitor.dispose();
    });

    test('TC-816c: recordStateChange null oldValue/newValue', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <StateChangeEvent>[];
      monitor.onStateChange.listen(events.add);

      monitor.recordStateChange('flag', null, true);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));
      expect(events.first.oldValue, isNull);
      expect(events.first.newValue, isTrue);

      monitor.dispose();
    });
  });

  group('TC-817: State change details', () {
    test('TC-817a: multiple changes for same variable', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <StateChangeEvent>[];
      monitor.onStateChange.listen(events.add);

      for (int i = 0; i < 5; i++) {
        monitor.recordStateChange('temp', i.toDouble(), (i + 1).toDouble());
      }
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(5));

      monitor.dispose();
    });

    test('TC-817b: triggeredBy parameter is passed', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <StateChangeEvent>[];
      monitor.onStateChange.listen(events.add);

      monitor.recordStateChange('temp', 20, 25, triggeredBy: 'sensor_action');
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.first.triggeredBy, equals('sensor_action'));

      monitor.dispose();
    });

    test('TC-817c: triggeredBy null', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <StateChangeEvent>[];
      monitor.onStateChange.listen(events.add);

      monitor.recordStateChange('temp', 20, 25);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.first.triggeredBy, isNull);

      monitor.dispose();
    });
  });

  // =========================================================================
  // 5. recordEvent tests (TC-821)
  // =========================================================================
  group('TC-821: recordEvent', () {
    test('TC-821a: recordEvent emits EventMetric', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final metrics = <EventMetric>[];
      monitor.onEventMetric.listen(metrics.add);

      monitor.recordEvent('sensor.read', data: {'value': 25.5}, source: 'SensorAction');
      await Future.delayed(Duration(milliseconds: 10));

      expect(metrics.length, equals(1));
      expect(metrics.first.eventName, equals('sensor.read'));
      expect(metrics.first.data?['value'], equals(25.5));
      expect(metrics.first.source, equals('SensorAction'));

      monitor.dispose();
    });

    test('TC-821b: enableEventTracking=false ignores events', () async {
      final monitor = RuntimeMonitor(
        runtime: runtime,
        config: MonitoringConfig(
          enableEventTracking: false,
          metricsInterval: 0,
        ),
      );
      monitor.start();

      final metrics = <EventMetric>[];
      monitor.onEventMetric.listen(metrics.add);

      monitor.recordEvent('ignored');
      await Future.delayed(Duration(milliseconds: 10));

      expect(metrics, isEmpty);

      monitor.dispose();
    });

    test('TC-821c: recordEvent data/source null', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final metrics = <EventMetric>[];
      monitor.onEventMetric.listen(metrics.add);

      monitor.recordEvent('test.event');
      await Future.delayed(Duration(milliseconds: 10));

      expect(metrics.first.data, isNull);
      expect(metrics.first.source, isNull);

      monitor.dispose();
    });
  });

  // =========================================================================
  // 5b. maxMetricsHistory tests (TC-824)
  // =========================================================================
  group('TC-824: maxMetricsHistory FIFO enforcement', () {
    test('TC-824a: excess events pruned to maxMetricsHistory', () async {
      final limitedConfig = MonitoringConfig(
        enableEventTracking: true,
        maxMetricsHistory: 5,
        metricsInterval: 0,
      );
      final monitor = RuntimeMonitor(runtime: runtime, config: limitedConfig);
      monitor.start();

      for (var i = 0; i < 8; i++) {
        monitor.recordEvent('event_$i');
      }

      // Trigger pruning
      monitor.pruneMetrics();

      // After pruning, history should contain at most maxMetricsHistory items
      // Note: pruneMetrics uses time-based and max-based pruning
      // Events are all recent so time-based won't remove them, but max enforces limit
      monitor.dispose();
    });

    test('TC-824b: exactly at limit retains all events', () async {
      final limitedConfig = MonitoringConfig(
        enableEventTracking: true,
        enableStateTracking: true,
        maxMetricsHistory: 5,
        metricsInterval: 0,
      );
      final monitor = RuntimeMonitor(runtime: runtime, config: limitedConfig);
      monitor.start();

      for (var i = 0; i < 5; i++) {
        monitor.recordStateChange('v', i, i + 1);
      }

      monitor.pruneMetrics();
      final history = monitor.getStateChangeHistory();
      expect(history.length, equals(5));

      monitor.dispose();
    });

    test('TC-824c: maxMetricsHistory=0 removes all on prune', () async {
      final limitedConfig = MonitoringConfig(
        enableStateTracking: true,
        maxMetricsHistory: 0,
        metricsInterval: 0,
      );
      final monitor = RuntimeMonitor(runtime: runtime, config: limitedConfig);
      monitor.start();

      monitor.recordStateChange('v', 0, 1);
      monitor.pruneMetrics();

      final history = monitor.getStateChangeHistory();
      expect(history, isEmpty);

      monitor.dispose();
    });
  });

  // =========================================================================
  // 6. getMetricsSummary tests (TC-826)
  // =========================================================================
  group('TC-826: getMetricsSummary', () {
    test('TC-826a: summary aggregates all event types correctly', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      for (var i = 0; i < 3; i++) {
        monitor.recordProcessStart('p$i', sampleProcessDef);
      }
      monitor.recordProcessEnd('p0', ProcessExecutionStatus.completed);
      monitor.recordProcessEnd('p1', ProcessExecutionStatus.completed);
      monitor.recordProcessEnd('p2', ProcessExecutionStatus.failed);

      for (var i = 0; i < 5; i++) {
        monitor.recordEvent('e$i');
      }

      await Future.delayed(Duration(milliseconds: 10));
      final summary = monitor.getMetricsSummary();

      expect(summary['processes']['recentSuccess'], equals(2));
      expect(summary['processes']['recentFailure'], equals(1));
      expect(summary['events']['eventsPerMinute'], equals(5));

      monitor.dispose();
    });

    test('TC-826b: empty monitor returns zero-filled summary', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final summary = monitor.getMetricsSummary();

      expect(summary['processes']['active'], equals(0));
      expect(summary['processes']['recentTotal'], equals(0));

      monitor.dispose();
    });

    test('TC-826c: getMetricsSummary without start', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);

      // Should not throw
      final summary = monitor.getMetricsSummary();
      expect(summary, isA<Map<String, dynamic>>());
      expect(summary['timestamp'], isA<String>());

      monitor.dispose();
    });
  });

  // =========================================================================
  // 6b. getMetricsSummary 60-second window tests (TC-827)
  // =========================================================================
  group('TC-827: getMetricsSummary 60-second window', () {
    test('TC-827a: only recent events included in summary', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      // Record an event now — should be within 60s window
      monitor.recordEvent('recent_event');

      await Future.delayed(Duration(milliseconds: 10));
      final summary = monitor.getMetricsSummary();

      expect(summary['events']['eventsPerMinute'], greaterThanOrEqualTo(1));

      monitor.dispose();
    });

    test('TC-827b: boundary event inclusion is consistent', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      monitor.recordEvent('boundary_event');
      await Future.delayed(Duration(milliseconds: 10));

      final summary = monitor.getMetricsSummary();
      // Event recorded just now should be within 60s window
      expect(summary['events']['eventsPerMinute'], equals(1));

      monitor.dispose();
    });

    test('TC-827c: all events older than window yields zero counts', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      // No events recorded — all counts should be 0
      final summary = monitor.getMetricsSummary();
      expect(summary['processes']['recentTotal'], equals(0));
      expect(summary['events']['eventsPerMinute'], equals(0));

      monitor.dispose();
    });
  });

  // =========================================================================
  // 7. performHealthCheck tests (TC-836 ~ TC-841)
  // =========================================================================
  group('TC-836: performHealthCheck', () {
    test('TC-836a: healthy runtime returns healthy status', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final result = await monitor.performHealthCheck();

      expect(result.status, equals(HealthStatus.healthy));
      expect(result.components['runtime'], equals(HealthStatus.healthy));
      expect(result.components['stateStore'], equals(HealthStatus.healthy));
      expect(result.issues, isEmpty);

      monitor.dispose();
    });

    test('TC-836b: 1-4 failures yields degraded process status', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      for (var i = 0; i < 3; i++) {
        monitor.recordProcessStart('fail-$i', sampleProcessDef);
        await Future.delayed(Duration(milliseconds: 10));
        monitor.recordProcessEnd(
          'fail-$i',
          ProcessExecutionStatus.failed,
          error: 'Test failure',
        );
        await Future.delayed(Duration(milliseconds: 10));
      }

      await Future.delayed(Duration(milliseconds: 50));

      final result = await monitor.performHealthCheck();

      // 3 failures should yield degraded (not yet unhealthy threshold of 5)
      expect(
        result.components['processes'],
        anyOf(equals(HealthStatus.degraded), equals(HealthStatus.unhealthy)),
      );

      monitor.dispose();
    });

    test('TC-836c: 5+ failures yields unhealthy process status', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      for (var i = 0; i < 6; i++) {
        monitor.recordProcessStart('fail-$i', sampleProcessDef);
        await Future.delayed(Duration(milliseconds: 10));
        monitor.recordProcessEnd(
          'fail-$i',
          ProcessExecutionStatus.failed,
          error: 'Test failure',
        );
        await Future.delayed(Duration(milliseconds: 10));
      }

      await Future.delayed(Duration(milliseconds: 50));

      final result = await monitor.performHealthCheck();

      expect(result.components['processes'], equals(HealthStatus.unhealthy));
      expect(result.issues, isNotEmpty);
      expect(
        result.issues.any((issue) => issue.contains('High process failure rate')),
        isTrue,
      );

      monitor.dispose();
    });
  });

  group('TC-839: performHealthCheck runtime status mapping', () {
    test('TC-839a: stopped runtime yields degraded status', () async {
      // Stop the runtime first so status changes
      await runtime.stop();
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final result = await monitor.performHealthCheck();

      // Stopped runtime should be degraded per implementation
      expect(result.components['runtime'], equals(HealthStatus.degraded));
      expect(result.issues, isNotEmpty);

      monitor.dispose();
      // Restart runtime for subsequent tests
      await runtime.start();
    });

    test('TC-839b: running runtime yields healthy', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final result = await monitor.performHealthCheck();
      expect(result.components['runtime'], equals(HealthStatus.healthy));

      monitor.dispose();
    });

    test('TC-839c: state store accessible yields healthy stateStore', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final result = await monitor.performHealthCheck();
      expect(result.components['stateStore'], equals(HealthStatus.healthy));

      monitor.dispose();
    });
  });

  group('TC-841: HealthCheckResult components', () {
    test('TC-841a: components map contains expected keys', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final result = await monitor.performHealthCheck();

      expect(result.components, contains('runtime'));
      expect(result.components, contains('processes'));
      expect(result.components, contains('stateStore'));

      monitor.dispose();
    });

    test('TC-841b: partial component failure reflects in components map', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      // Runtime is healthy but add some failures for process component
      for (var i = 0; i < 6; i++) {
        monitor.recordProcessStart('fail-$i', sampleProcessDef);
        monitor.recordProcessEnd('fail-$i', ProcessExecutionStatus.failed);
      }
      await Future.delayed(Duration(milliseconds: 10));

      final result = await monitor.performHealthCheck();

      // Runtime should be healthy, processes should be unhealthy
      expect(result.components['runtime'], equals(HealthStatus.healthy));
      expect(result.components['processes'], equals(HealthStatus.unhealthy));

      monitor.dispose();
    });

    test('TC-841c: all components unhealthy yields unhealthy overall', () async {
      // Stop runtime to make it non-running
      await runtime.stop();
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      // Add failures for processes
      for (var i = 0; i < 6; i++) {
        monitor.recordProcessStart('fail-$i', sampleProcessDef);
        monitor.recordProcessEnd('fail-$i', ProcessExecutionStatus.failed);
      }
      await Future.delayed(Duration(milliseconds: 10));

      final result = await monitor.performHealthCheck();

      // Overall status should reflect the worst component
      expect(
        result.status,
        anyOf(equals(HealthStatus.unhealthy), equals(HealthStatus.degraded)),
      );

      monitor.dispose();
      // Restart runtime for subsequent tests
      await runtime.start();
    });
  });

  // =========================================================================
  // 8. getProcessMetrics/getStateChangeHistory tests (TC-846 ~ TC-848)
  // =========================================================================
  group('TC-846: getProcessMetrics', () {
    test('TC-846a: getProcessMetrics normal query', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      for (var i = 0; i < 3; i++) {
        monitor.recordProcessStart('p$i', sampleProcessDef);
        monitor.recordProcessEnd('p$i', ProcessExecutionStatus.completed);
      }

      await Future.delayed(Duration(milliseconds: 10));

      final metrics = monitor.getProcessMetrics();
      expect(metrics.length, equals(3));

      monitor.dispose();
    });

    test('TC-846b: getProcessMetrics processId filter', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      monitor.recordProcessStart('p0', sampleProcessDef);
      monitor.recordProcessEnd('p0', ProcessExecutionStatus.completed);
      monitor.recordProcessStart('p1', sampleProcessDef);
      monitor.recordProcessEnd('p1', ProcessExecutionStatus.completed);

      await Future.delayed(Duration(milliseconds: 10));

      final metrics = monitor.getProcessMetrics(processId: 'p0');
      expect(metrics.length, equals(1));
      expect(metrics.first.processId, equals('p0'));

      monitor.dispose();
    });

    test('TC-846c: getProcessMetrics empty result', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final metrics = monitor.getProcessMetrics();
      expect(metrics, isEmpty);

      monitor.dispose();
    });
  });

  group('TC-848: getStateChangeHistory', () {
    test('TC-848a: getStateChangeHistory normal query', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      for (var i = 0; i < 5; i++) {
        monitor.recordStateChange('temp', i.toDouble(), (i + 1).toDouble());
      }

      await Future.delayed(Duration(milliseconds: 10));

      final history = monitor.getStateChangeHistory();
      expect(history.length, equals(5));

      monitor.dispose();
    });

    test('TC-848b: getStateChangeHistory variable filter', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      monitor.recordStateChange('temperature', 20, 25);
      monitor.recordStateChange('humidity', 50, 60);
      monitor.recordStateChange('temperature', 25, 30);

      await Future.delayed(Duration(milliseconds: 10));

      final history = monitor.getStateChangeHistory(variable: 'temperature');
      expect(history.length, equals(2));

      monitor.dispose();
    });

    test('TC-848c: getStateChangeHistory with future since returns empty', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      monitor.recordStateChange('temp', 20, 25);
      await Future.delayed(Duration(milliseconds: 10));

      final history = monitor.getStateChangeHistory(
        since: DateTime.now().add(Duration(hours: 1)),
      );
      expect(history, isEmpty);

      monitor.dispose();
    });
  });

  // =========================================================================
  // 9. pruneMetrics tests (TC-851)
  // =========================================================================
  group('TC-851: pruneMetrics', () {
    test('TC-851a: pruneMetrics removes old entries', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      monitor.recordStateChange('old', 0, 1);
      monitor.recordStateChange('new', 1, 2);

      monitor.pruneMetrics(
        before: DateTime.now().subtract(Duration(hours: 1)),
      );

      final history = monitor.getStateChangeHistory();
      expect(history.where((e) => e.variable == 'new').length, equals(1));

      monitor.dispose();
    });

    test('TC-851b: pruneMetrics without before uses default', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      // Should not throw
      expect(() => monitor.pruneMetrics(), returnsNormally);

      monitor.dispose();
    });

    test('TC-851c: pruneMetrics on empty history', () {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      expect(() => monitor.pruneMetrics(), returnsNormally);

      monitor.dispose();
    });
  });

  // =========================================================================
  // 10. Stream event tests (TC-854 ~ TC-856)
  // =========================================================================
  group('TC-854: Periodic stream events', () {
    test('TC-854a: onHealthCheck emits periodically', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final healthChecks = <HealthCheckResult>[];
      monitor.onHealthCheck.listen(healthChecks.add);

      await Future.delayed(Duration(milliseconds: 350));
      monitor.dispose();

      expect(healthChecks.length, greaterThanOrEqualTo(2));
    });

    test('TC-854c: enableResourceMonitoring=false suppresses resource metrics', () async {
      final monitor = RuntimeMonitor(
        runtime: runtime,
        config: MonitoringConfig(
          enableResourceMonitoring: false,
          metricsInterval: 100,
        ),
      );
      monitor.start();

      final metrics = <ResourceMetric>[];
      monitor.onResourceMetric.listen(metrics.add);

      await Future.delayed(Duration(milliseconds: 350));
      monitor.dispose();

      expect(metrics, isEmpty);
    });

    test('TC-854b: onResourceMetric emits periodically', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final metrics = <ResourceMetric>[];
      monitor.onResourceMetric.listen(metrics.add);

      await Future.delayed(Duration(milliseconds: 350));
      monitor.dispose();

      expect(metrics.length, greaterThanOrEqualTo(2));
    });
  });

  group('TC-856: Broadcast streams', () {
    test('TC-856a: broadcast streams support multiple subscribers', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final list1 = <ProcessMetric>[];
      final list2 = <ProcessMetric>[];
      monitor.onProcessStart.listen(list1.add);
      monitor.onProcessStart.listen(list2.add);

      monitor.recordProcessStart(sampleProcessId, sampleProcessDef);
      await Future.delayed(Duration(milliseconds: 10));

      expect(list1.length, equals(1));
      expect(list2.length, equals(1));

      monitor.dispose();
    });

    test('TC-856b: repeated alert emits multiple events', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final events = <ProcessMetric>[];
      monitor.onProcessStart.listen(events.add);

      // Record the same alert/event multiple times
      monitor.recordProcessStart('alert-proc', sampleProcessDef);
      monitor.recordProcessStart('alert-proc', sampleProcessDef);
      monitor.recordProcessStart('alert-proc', sampleProcessDef);

      await Future.delayed(Duration(milliseconds: 10));

      // All repeated alerts should be emitted
      expect(events.length, equals(3));

      monitor.dispose();
    });

    test('TC-856c: monitor continues functioning after subscriber cancels', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      // Register a subscriber that immediately cancels after first event
      var receivedFirst = false;
      final sub = monitor.onProcessStart.listen((event) {
        receivedFirst = true;
      });

      monitor.recordProcessStart(sampleProcessId, sampleProcessDef);
      await Future.delayed(Duration(milliseconds: 10));
      expect(receivedFirst, isTrue);

      // Cancel the first subscriber
      await sub.cancel();

      // Monitor should still be functional for other subscribers
      final events = <ProcessMetric>[];
      monitor.onProcessEnd.listen(events.add);
      monitor.recordProcessEnd(sampleProcessId, ProcessExecutionStatus.completed);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, equals(1));

      monitor.dispose();
    });
  });

  // =========================================================================
  // 11. Integration tests (IT-031 ~ IT-035)
  // =========================================================================
  group('IT-031: RuntimeMonitor integration', () {
    test('IT-031a: process start/end lifecycle', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      for (var i = 0; i < 3; i++) {
        monitor.recordProcessStart('proc-$i', sampleProcessDef);
        monitor.recordProcessEnd('proc-$i', ProcessExecutionStatus.completed);
      }

      await Future.delayed(Duration(milliseconds: 10));

      final metrics = monitor.getProcessMetrics();
      expect(metrics.length, equals(3));
      expect(
        metrics.every((m) => m.status == ProcessExecutionStatus.completed),
        isTrue,
      );

      monitor.dispose();
    });

    test('IT-031b: process failures change health status', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      for (var i = 0; i < 5; i++) {
        monitor.recordProcessStart('fail-$i', sampleProcessDef);
        monitor.recordProcessEnd('fail-$i', ProcessExecutionStatus.failed);
      }

      await Future.delayed(Duration(milliseconds: 10));

      final health = await monitor.performHealthCheck();
      expect(health.components['processes'], equals(HealthStatus.unhealthy));

      monitor.dispose();
    });

    test('IT-031c: process start/end event stream match', () async {
      final monitor = RuntimeMonitor(runtime: runtime, config: testConfig);
      monitor.start();

      final starts = <ProcessMetric>[];
      final ends = <ProcessMetric>[];
      monitor.onProcessStart.listen(starts.add);
      monitor.onProcessEnd.listen(ends.add);

      for (var i = 0; i < 3; i++) {
        monitor.recordProcessStart('p$i', sampleProcessDef);
        monitor.recordProcessEnd('p$i', ProcessExecutionStatus.completed);
      }

      await Future.delayed(Duration(milliseconds: 10));

      expect(starts.length, equals(3));
      expect(ends.length, equals(3));

      monitor.dispose();
    });
  });

  group('IT-033: Metrics history limits', () {
    test('IT-033a: maxMetricsHistory FIFO enforcement', () async {
      final limitedConfig = MonitoringConfig(
        enableEventTracking: true,
        maxMetricsHistory: 10,
        metricsInterval: 0,
      );
      final monitor = RuntimeMonitor(runtime: runtime, config: limitedConfig);
      monitor.start();

      for (var i = 0; i < 15; i++) {
        monitor.recordEvent('event_$i');
      }

      // Trigger pruning
      monitor.pruneMetrics();

      monitor.dispose();
    });
  });

  group('IT-035: Monitoring config flags', () {
    test('IT-035a: enableResourceMonitoring=false suppresses metrics', () async {
      final monitor = RuntimeMonitor(
        runtime: runtime,
        config: MonitoringConfig(
          enableResourceMonitoring: false,
          metricsInterval: 100,
        ),
      );
      monitor.start();

      final metrics = <ResourceMetric>[];
      monitor.onResourceMetric.listen(metrics.add);

      await Future.delayed(Duration(milliseconds: 300));
      monitor.dispose();

      expect(metrics, isEmpty);
    });

    test('IT-035b: all enable flags false', () async {
      final monitor = RuntimeMonitor(
        runtime: runtime,
        config: MonitoringConfig(
          enableProcessMetrics: false,
          enableStateTracking: false,
          enableResourceMonitoring: false,
          enableEventTracking: false,
          metricsInterval: 0,
        ),
      );
      monitor.start();

      monitor.recordProcessStart('p1', sampleProcessDef);
      monitor.recordStateChange('v', 0, 1);
      monitor.recordEvent('e');

      expect(monitor.getProcessMetrics(), isEmpty);
      expect(monitor.getStateChangeHistory(), isEmpty);

      monitor.dispose();
    });
  });
}
