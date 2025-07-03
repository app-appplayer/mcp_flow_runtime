import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main() {
  group('McpFlowRuntime', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    test('initializes with stopped status', () {
      expect(runtime.status, equals(RuntimeStatus.stopped));
    });

    test('loads valid flow definition', () async {
      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'processes': []
      };

      await runtime.loadFlow(flowJson);
      // Should complete without error
    });

    test('throws on invalid flow version', () {
      final flowJson = {
        'version': 'invalid',
        'resources': {},
        'state': {},
        'processes': []
      };

      expect(
        () => runtime.loadFlow(flowJson),
        throwsException,
      );
    });

    test('starts and stops correctly', () async {
      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'processes': []
      };

      await runtime.loadFlow(flowJson);
      
      expect(runtime.status, equals(RuntimeStatus.stopped));
      
      await runtime.start();
      expect(runtime.status, equals(RuntimeStatus.running));
      
      await runtime.stop();
      expect(runtime.status, equals(RuntimeStatus.stopped));
    });

    test('manages state variables', () async {
      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {
          'counter': {
            'type': 'number',
            'initial': 0
          },
          'message': {
            'type': 'string',
            'initial': 'hello'
          }
        },
        'processes': []
      };

      await runtime.loadFlow(flowJson);
      await runtime.start();

      expect(runtime.getState('counter'), equals(0));
      expect(runtime.getState('message'), equals('hello'));

      await runtime.setState('counter', 42);
      expect(runtime.getState('counter'), equals(42));

      await runtime.setState('message', 'world');
      expect(runtime.getState('message'), equals('world'));
    });

    test('emits state change events', () async {
      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {
          'value': {
            'type': 'number',
            'initial': 0
          }
        },
        'processes': []
      };

      await runtime.loadFlow(flowJson);
      await runtime.start();

      final events = <StateChangeEvent>[];
      runtime.stateEventBus.on<StateChangeEvent>().listen(events.add);

      await runtime.setState('value', 10);
      await runtime.setState('value', 20);

      await Future.delayed(Duration(milliseconds: 100)); // Allow events to propagate

      expect(events, hasLength(2));
      expect(events[0].variable, equals('value'));
      expect(events[0].newValue, equals(10));
      expect(events[1].variable, equals('value'));
      expect(events[1].newValue, equals(20));
    });

    test('executes startup process', () async {
      bool processExecuted = false;

      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {
          'started': {
            'type': 'boolean',
            'initial': false
          }
        },
        'processes': [
          {
            'id': 'startup_process',
            'trigger': {
              'type': 'startup'
            },
            'steps': [
              {
                'action': 'setState',
                'params': {
                  'variable': 'started',
                  'value': true
                }
              }
            ]
          }
        ]
      };

      await runtime.loadFlow(flowJson);
      
      // Listen for state change
      runtime.stateEventBus.on<StateChangeEvent>()
          .where((event) => event.variable == 'started')
          .listen((event) {
        processExecuted = true;
      });

      await runtime.start();
      
      // Wait for process to execute
      await Future.delayed(Duration(milliseconds: 500));

      expect(processExecuted, isTrue);
      expect(runtime.getState('started'), equals(true));
    });

    test('handles channels correctly', () async {
      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'channels': {
          'events': {
            'type': 'pubsub'
          },
          'queue': {
            'type': 'queue'
          }
        },
        'processes': []
      };

      await runtime.loadFlow(flowJson);
      await runtime.start();

      final receivedEvents = <dynamic>[];
      runtime.getChannelStream('events')?.listen(receivedEvents.add);

      await runtime.sendToChannel('events', {'type': 'test', 'value': 1});
      await runtime.sendToChannel('events', {'type': 'test', 'value': 2});

      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvents, hasLength(2));
      expect(receivedEvents[0]['value'], equals(1));
      expect(receivedEvents[1]['value'], equals(2));
    });

    test('provides runtime statistics', () async {
      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'processes': [
          {
            'id': 'test_process',
            'trigger': {'type': 'startup'},
            'steps': []
          }
        ]
      };

      await runtime.loadFlow(flowJson);
      await runtime.start();

      final stats = runtime.getStatistics();
      
      expect(stats.status, equals(RuntimeStatus.running));
      expect(stats.totalProcesses, greaterThan(0));
      expect(stats.uptime, isA<Duration>());
    });

    test('throws when starting already running runtime', () async {
      final flowJson = {
        'version': '1.0.0',
        'resources': {},
        'state': {},
        'processes': []
      };

      await runtime.loadFlow(flowJson);
      await runtime.start();

      expect(
        () => runtime.start(),
        throwsException,
      );
    });

    test('handles missing flow on start', () async {
      // Don't load any flow
      expect(runtime.status, equals(RuntimeStatus.stopped));
      
      // Should still start successfully
      await runtime.start();
      expect(runtime.status, equals(RuntimeStatus.running));
    });
  });
}