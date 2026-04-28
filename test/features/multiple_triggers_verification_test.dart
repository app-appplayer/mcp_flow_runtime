import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Multiple Triggers Verification', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('basic multiple triggers work correctly', () async {
      // The implementation supports only singular 'trigger' per process (TD-010).
      // To test multiple trigger types, use separate processes that modify the same state.
      final flow = {
        'version': '1.0.0',
        'state': {
          'counter': {'type': 'number', 'initial': 0}
        },
        'processes': [
          {
            'id': 'startup_trigger',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'stateSet',
              'params': {
                'key': 'counter',
                'value': '= counter + 1'
              }
            }]
          },
          {
            'id': 'event_trigger',
            'trigger': {'type': 'event', 'event': 'increment'},
            'steps': [{
              'action': 'stateSet',
              'params': {
                'key': 'counter',
                'value': '= counter + 1'
              }
            }]
          }
        ]
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Wait for startup trigger
      await Future.delayed(Duration(milliseconds: 100));
      expect(runtime.getState('counter'), equals(1));

      // Trigger via event
      runtime.emitEvent('increment');
      await Future.delayed(Duration(milliseconds: 100));
      expect(runtime.getState('counter'), equals(2));

      // Trigger again
      runtime.emitEvent('increment');
      await Future.delayed(Duration(milliseconds: 100));
      expect(runtime.getState('counter'), equals(3));
    });
  });
}