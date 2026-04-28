import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Fix Multiple Triggers', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('trigger context updates correctly', () async {
      // The implementation supports only singular 'trigger' per process (TD-010).
      // Use separate processes for each trigger type.
      final steps = [
        {
          'action': 'stateSet',
          'params': {
            'key': 'counter',
            'value': '= counter + 1'
          }
        },
        {
          'action': 'if',
          'params': {
            'condition': 'trigger'
          },
          'then': [
            {
              'action': 'stateSet',
              'params': {
                'key': 'last_trigger_type',
                'value': '= trigger.type'
              }
            },
            {
              'action': 'if',
              'params': {
                'condition': 'trigger.event'
              },
              'then': [{
                'action': 'stateSet',
                'params': {
                  'key': 'last_trigger_data',
                  'value': '= trigger.event'
                }
              }]
            }
          ]
        }
      ];

      final flow = {
        'version': '1.0.0',
        'state': {
          'counter': {'type': 'number', 'initial': 0},
          'last_trigger_type': {'type': 'string', 'initial': ''},
          'last_trigger_data': {'type': 'string', 'initial': ''}
        },
        'processes': [
          {
            'id': 'startup_process',
            'trigger': {'type': 'startup'},
            'steps': steps,
          },
          {
            'id': 'event_process',
            'trigger': {'type': 'event', 'event': 'test_event'},
            'steps': steps,
          },
        ]
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Wait for startup trigger
      await Future.delayed(Duration(milliseconds: 100));

      expect(runtime.getState('counter'), equals(1));
      expect(runtime.getState('last_trigger_type'), equals('startup'));
      expect(runtime.getState('last_trigger_data'), equals(''));

      // Trigger via event
      runtime.emitEvent('test_event');
      await Future.delayed(Duration(milliseconds: 200));

      expect(runtime.getState('counter'), equals(2));
      expect(runtime.getState('last_trigger_type'), equals('event'));
      expect(runtime.getState('last_trigger_data'), equals('test_event'));
    });
  });
}