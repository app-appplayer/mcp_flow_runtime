import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Integration test for cron-based scheduling
void main() {
  group('Cron Schedule Integration Tests', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('cron expression executes every second', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'execution_count': {'type': 'number', 'initial': 0},
          'last_execution': {'type': 'number', 'initial': 0}
        },
        'processes': [{
          'id': 'cron_every_second',
          'trigger': {
            'type': 'schedule',
            'cron': '* * * * * *' // Every second
          },
          'steps': [
            {'action': 'stateSet', 'params': {'key': 'execution_count', 'value': '=execution_count + 1'}},
            {'action': 'stateSet', 'params': {'key': 'last_execution', 'value': '=Date.now()'}}
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait for 3.5 seconds, should execute 3-4 times
      await Future.delayed(Duration(milliseconds: 3500));
      
      final count = runtime.getState('execution_count');
      expect(count, greaterThanOrEqualTo(3));
      expect(count, lessThanOrEqualTo(4));
    });

    test('cron expression with initial delay', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'execution_count': {'type': 'number', 'initial': 0}
        },
        'processes': [{
          'id': 'cron_with_delay',
          'trigger': {
            'type': 'schedule',
            'cron': '* * * * * *', // Every second
            'delay': 2000 // 2 second initial delay
          },
          'steps': [
            {'action': 'stateSet', 'params': {'key': 'execution_count', 'value': '=execution_count + 1'}}
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Check immediately - should not have executed
      expect(runtime.getState('execution_count'), equals(0));
      
      // Wait 1.5 seconds - still should not have executed
      await Future.delayed(Duration(milliseconds: 1500));
      expect(runtime.getState('execution_count'), equals(0));
      
      // Wait another 1.5 seconds (total 3s) - should have executed once
      await Future.delayed(Duration(milliseconds: 1500));
      expect(runtime.getState('execution_count'), greaterThanOrEqualTo(1));
    });

    test('complex cron expression (every 2 seconds)', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'execution_count': {'type': 'number', 'initial': 0}
        },
        'processes': [{
          'id': 'cron_every_2_seconds',
          'trigger': {
            'type': 'schedule',
            'cron': '*/2 * * * * *' // Every 2 seconds
          },
          'steps': [
            {'action': 'stateSet', 'params': {'key': 'execution_count', 'value': '=execution_count + 1'}}
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait for 5 seconds, should execute 2-3 times
      await Future.delayed(Duration(seconds: 5));
      
      final count = runtime.getState('execution_count');
      expect(count, greaterThanOrEqualTo(2));
      expect(count, lessThanOrEqualTo(3));
    });

    test('multiple cron jobs running concurrently', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'fast_count': {'type': 'number', 'initial': 0},
          'slow_count': {'type': 'number', 'initial': 0}
        },
        'processes': [
          {
            'id': 'fast_cron',
            'trigger': {
              'type': 'schedule',
              'cron': '* * * * * *' // Every second
            },
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'fast_count', 'value': '=fast_count + 1'}}
            ]
          },
          {
            'id': 'slow_cron',
            'trigger': {
              'type': 'schedule',
              'cron': '*/3 * * * * *' // Every 3 seconds
            },
            'steps': [
              {'action': 'stateSet', 'params': {'key': 'slow_count', 'value': '=slow_count + 1'}}
            ]
          }
        ]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait for 7 seconds
      await Future.delayed(Duration(seconds: 7));
      
      final fastCount = runtime.getState('fast_count');
      final slowCount = runtime.getState('slow_count');
      
      // Fast should execute 6-7 times
      expect(fastCount, greaterThanOrEqualTo(6));
      expect(fastCount, lessThanOrEqualTo(8));
      
      // Slow should execute 2-3 times
      expect(slowCount, greaterThanOrEqualTo(2));
      expect(slowCount, lessThanOrEqualTo(3));
    });

    test('cron job stops when runtime stops', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'execution_count': {'type': 'number', 'initial': 0}
        },
        'processes': [{
          'id': 'cron_stop_test',
          'trigger': {
            'type': 'schedule',
            'cron': '* * * * * *' // Every second
          },
          'steps': [
            {'action': 'stateSet', 'params': {'key': 'execution_count', 'value': '=execution_count + 1'}}
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait for 2 seconds
      await Future.delayed(Duration(seconds: 2));
      
      final countBeforeStop = runtime.getState('execution_count');
      expect(countBeforeStop, greaterThanOrEqualTo(1));
      
      // Stop runtime
      await runtime.stop();
      
      // Wait another 2 seconds
      await Future.delayed(Duration(seconds: 2));
      
      // Count should not have increased after stop
      expect(runtime.getState('execution_count'), equals(countBeforeStop));
    });

    test('invalid cron expression logs warning', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'execution_count': {'type': 'number', 'initial': 0}
        },
        'processes': [{
          'id': 'invalid_cron',
          'trigger': {
            'type': 'schedule',
            'cron': 'invalid cron expression'
          },
          'steps': [
            {'action': 'stateSet', 'params': {'key': 'execution_count', 'value': '=execution_count + 1'}}
          ]
        }]
      };

      await runtime.loadFlow(flow);
      
      // Should not throw, just log warning
      await runtime.start();
      
      // Wait a bit
      await Future.delayed(Duration(seconds: 1));
      
      // Should not execute due to invalid cron
      expect(runtime.getState('execution_count'), equals(0));
    });
  });
}