import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

/// Tests for fork, join, and channelPublish actions
void main() {
  group('Process Control Actions', () {
    late McpFlowRuntime runtime;

    setUp(() {
      runtime = McpFlowRuntime();
    });

    tearDown(() async {
      if (runtime.status == RuntimeStatus.running) {
        await runtime.stop();
      }
    });

    group('fork Action', () {
      test('fork starts a new process asynchronously', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'forked': {'type': 'boolean', 'initial': false},
            'main_done': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'main',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'fork',
                  'params': {
                    'processId': 'background',
                    'args': {'value': 42}
                  },
                  'bindTo': 'handle'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'main_done', 'value': true}
                }
              ]
            },
            {
              'id': 'background',
              'trigger': {'type': 'manual'},
              'steps': [
                {
                  'action': 'wait',
                  'params': {'durationMs': 50}
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'forked', 'value': true}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Main should complete immediately
        await Future.delayed(Duration(milliseconds: 20));
        expect(runtime.getState('main_done'), isTrue);
        
        // Forked process should complete after delay
        expect(runtime.getState('forked'), isFalse);
        await Future.delayed(Duration(milliseconds: 100));
        expect(runtime.getState('forked'), isTrue);
      });
    });

    group('join Action', () {
      test('join waits for process completion', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'joined': {'type': 'boolean', 'initial': false},
          },
          'processes': [
            {
              'id': 'waiter',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'fork',
                  'params': {'processId': 'worker'},
                  'bindTo': 'handle'
                },
                {
                  'action': 'join',
                  'params': {
                    'processHandle': '{{handle}}',
                    'timeout': 200
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'joined', 'value': true}
                }
              ]
            },
            {
              'id': 'worker',
              'trigger': {'type': 'manual'},
              'steps': [
                {'action': 'wait', 'params': {'durationMs': 100}}
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        // Should not be joined immediately
        await Future.delayed(Duration(milliseconds: 50));
        expect(runtime.getState('joined'), isFalse);
        
        // Should be joined after timeout
        await Future.delayed(Duration(milliseconds: 250));
        expect(runtime.getState('joined'), isTrue);
      });
    });

    group('channelPublish Action', () {
      test('channelPublish broadcasts to channel', () async {
        final flow = {
          'version': '1.0.0',
          'channels': {
            'events': {'type': 'pubsub', 'capacity': 10}
          },
          'state': {
            'received1': {'type': 'any', 'initial': null},
            'received2': {'type': 'any', 'initial': null},
          },
          'processes': [
            {
              'id': 'publisher',
              'trigger': {'type': 'startup'},
              'steps': [
                // Small delay to ensure receivers are ready
                {'action': 'wait', 'params': {'durationMs': 20}},
                {
                  'action': 'channelPublish',
                  'params': {
                    'channel': 'events',
                    'data': {'event': 'test', 'value': 123},
                    'broadcast': true
                  }
                }
              ]
            },
            {
              'id': 'subscriber1',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'channelReceive',
                  'params': {'channel': 'events', 'timeout': 200},
                  'bindTo': 'msg1'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'received1', 'value': '{{msg1}}'}
                }
              ]
            },
            {
              'id': 'subscriber2',
              'trigger': {'type': 'startup'},
              'steps': [
                {
                  'action': 'channelReceive',
                  'params': {'channel': 'events', 'timeout': 200},
                  'bindTo': 'msg2'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'received2', 'value': '{{msg2}}'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 150));
        
        // Both subscribers should receive the broadcast
        final received1 = runtime.getState('received1');
        final received2 = runtime.getState('received2');
        
        expect(received1, isNotNull);
        expect(received2, isNotNull);
        
        // Check the data structure
        if (received1 is Map) {
          expect(received1['data'], equals({'event': 'test', 'value': 123}));
          expect(received1['broadcast'], isTrue);
        }
      });
    });

    group('memoryAllocate Action', () {
      test('memoryAllocate creates memory regions', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'allocated': {'type': 'boolean', 'initial': false},
            'written': {'type': 'boolean', 'initial': false},
            'readValue': {'type': 'any', 'initial': null},
          },
          'processes': [
            {
              'id': 'memory_test',
              'trigger': {'type': 'startup'},
              'steps': [
                // Allocate memory
                {
                  'action': 'memoryAllocate',
                  'params': {
                    'name': 'test_buffer',
                    'size': 100,
                    'type': 'uint8'
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'allocated', 'value': true}
                },
                // Write to allocated memory
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'test_buffer',
                    'offset': 0,
                    'data': [1, 2, 3, 4, 5]
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'written', 'value': true}
                },
                // Read from allocated memory
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'test_buffer',
                    'offset': 0,
                    'length': 5
                  },
                  'bindTo': 'data'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'readValue', 'value': '{{data}}'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('allocated'), isTrue);
        expect(runtime.getState('written'), isTrue);
        expect(runtime.getState('readValue'), equals([1, 2, 3, 4, 5]));
      });

      test('memoryAllocate with different types', () async {
        final flow = {
          'version': '1.0.0',
          'state': {
            'float_written': {'type': 'boolean', 'initial': false},
            'float_value': {'type': 'any', 'initial': null},
          },
          'processes': [
            {
              'id': 'float_test',
              'trigger': {'type': 'startup'},
              'steps': [
                // Allocate float32 memory
                {
                  'action': 'memoryAllocate',
                  'params': {
                    'name': 'float_buffer',
                    'size': 10,
                    'type': 'float32'
                  }
                },
                // Write float values
                {
                  'action': 'memoryWrite',
                  'params': {
                    'region': 'float_buffer',
                    'offset': 0,
                    'data': [3.14, 2.71, 1.41]
                  }
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'float_written', 'value': true}
                },
                // Read float values
                {
                  'action': 'memoryRead',
                  'params': {
                    'region': 'float_buffer',
                    'offset': 0,
                    'length': 3
                  },
                  'bindTo': 'floats'
                },
                {
                  'action': 'stateSet',
                  'params': {'key': 'float_value', 'value': '{{floats}}'}
                }
              ]
            }
          ]
        };

        await runtime.loadFlow(flow);
        await runtime.start();
        
        await Future.delayed(Duration(milliseconds: 100));
        
        expect(runtime.getState('float_written'), isTrue);
        
        final floatValue = runtime.getState('float_value');
        expect(floatValue, isNotNull);
        if (floatValue is List) {
          expect(floatValue.length, equals(3));
          // Check approximate values due to float precision
          expect(floatValue[0], closeTo(3.14, 0.01));
          expect(floatValue[1], closeTo(2.71, 0.01));
          expect(floatValue[2], closeTo(1.41, 0.01));
        }
      });
    });
  });
}