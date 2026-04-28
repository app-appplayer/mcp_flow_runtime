import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('Trigger Context', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('event trigger passes correct context', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'event_name': {'type': 'string', 'initial': ''},
          'has_trigger': {'type': 'boolean', 'initial': false}
        },
        'processes': [{
          'id': 'event_process',
          'trigger': {
            'type': 'event',
            'event': 'test_event'
          },
          'steps': [
            {
              'action': 'stateSet',
              'params': {
                'key': 'has_trigger',
                'value': '= trigger != null'
              }
            },
            {
              'action': 'stateSet',
              'params': {
                'key': 'event_name',
                'value': '= trigger.event'
              }
            }
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      runtime.emitEvent('test_event');
      await Future.delayed(Duration(milliseconds: 100));

      expect(runtime.getState('has_trigger'), isTrue);
      expect(runtime.getState('event_name'), equals('test_event'));
    });

    test('startup trigger passes correct context', () async {
      final flow = {
        'version': '1.0.0',
        'state': {
          'trigger_type': {'type': 'string', 'initial': ''},
          'has_trigger': {'type': 'boolean', 'initial': false}
        },
        'processes': [{
          'id': 'startup_process',
          'trigger': {
            'type': 'startup'
          },
          'steps': [
            {
              'action': 'stateSet',
              'params': {
                'key': 'has_trigger',
                'value': '= trigger != null'
              }
            },
            {
              'action': 'stateSet',
              'params': {
                'key': 'trigger_type',
                'value': '= trigger.type'
              }
            }
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      await Future.delayed(Duration(milliseconds: 100));

      expect(runtime.getState('has_trigger'), isTrue);
      expect(runtime.getState('trigger_type'), equals('startup'));
    });

    test('multiple triggers with different contexts', () async {
      // The implementation supports only singular 'trigger' per process (TD-010).
      // To test multiple trigger types, use separate processes.
      final flow = {
        'version': '1.0.0',
        'state': {
          'last_trigger': {'type': 'string', 'initial': ''}
        },
        'processes': [
          {
            'id': 'startup_trigger',
            'trigger': {'type': 'startup'},
            'steps': [{
              'action': 'stateSet',
              'params': {
                'key': 'last_trigger',
                'value': '= trigger.type'
              }
            }]
          },
          {
            'id': 'event_trigger',
            'trigger': {'type': 'event', 'event': 'my_event'},
            'steps': [{
              'action': 'stateSet',
              'params': {
                'key': 'last_trigger',
                'value': '= trigger.type'
              }
            }]
          }
        ]
      };

      await runtime.loadFlow(flow);
      await runtime.start();

      // Wait for startup trigger
      await Future.delayed(Duration(milliseconds: 100));
      expect(runtime.getState('last_trigger'), equals('startup'));

      // Trigger event
      runtime.emitEvent('my_event');
      await Future.delayed(Duration(milliseconds: 100));
      expect(runtime.getState('last_trigger'), equals('event'));
    });
  });
}