import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart' hide StateChangeEvent;
import 'package:mcp_flow_runtime/src/monitoring/runtime_monitor.dart';

void main() {
  group('RuntimeMonitor Simple Tests', () {
    late McpFlowRuntime runtime;
    late RuntimeMonitor monitor;
    
    setUp(() async {
      runtime = McpFlowRuntime();
      monitor = RuntimeMonitor(runtime: runtime);
      
      // Load a minimal flow
      await runtime.loadFlow({
        'version': '1.0.0',
        'state': {
          'counter': {'type': 'number', 'initial': 0},
        },
        'processes': []
      });
      await runtime.start();
    });
    
    tearDown(() async {
      monitor.dispose();
      await runtime.stop();
    });
    
    test('should start and stop monitoring', () {
      expect(() => monitor.start(), returnsNormally);
      expect(() => monitor.stop(), returnsNormally);
    });
    
    test('should collect basic metrics summary', () {
      monitor.start();
      
      final summary = monitor.getMetricsSummary();
      expect(summary, isA<Map<String, dynamic>>());
      expect(summary['timestamp'], isA<String>());
      expect(summary['processes'], isNotNull);
      expect(summary['state']['totalVariables'], greaterThanOrEqualTo(1));
    });
    
    test('should perform health checks', () async {
      monitor.start();
      
      final result = await monitor.performHealthCheck();
      
      expect(result.status, equals(HealthStatus.healthy));
      expect(result.components['runtime'], equals(HealthStatus.healthy));
      expect(result.components['stateStore'], equals(HealthStatus.healthy));
      expect(result.issues, isEmpty);
    });
    
    test('should track state changes with monitor API', () async {
      monitor.start();
      
      final changes = <StateChangeEvent>[];
      monitor.onStateChange.listen(changes.add);
      
      // Record a state change
      monitor.recordStateChange('counter', 0, 1);
      
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(changes.length, equals(1));
      expect(changes.first.variable, equals('counter'));
      expect(changes.first.newValue, equals(1));
    });
    
    test('should track events', () async {
      monitor.start();
      
      final events = <EventMetric>[];
      monitor.onEventMetric.listen(events.add);
      
      monitor.recordEvent('test_event', data: {'value': 42});
      
      await Future.delayed(Duration(milliseconds: 10));
      
      expect(events.length, equals(1));
      expect(events.first.eventName, equals('test_event'));
      expect(events.first.data?['value'], equals(42));
    });
    
    test('should respect monitoring configuration', () {
      final customMonitor = RuntimeMonitor(
        runtime: runtime,
        config: MonitoringConfig(
          enableProcessMetrics: false,
          enableStateTracking: false,
          metricsInterval: 0,
        ),
      );
      
      customMonitor.start();
      
      // These should be ignored due to config
      customMonitor.recordStateChange('ignored', 0, 1);
      
      expect(customMonitor.getStateChangeHistory(), isEmpty);
      
      customMonitor.dispose();
    });
  });
}