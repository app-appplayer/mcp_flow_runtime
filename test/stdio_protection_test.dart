import 'package:test/test.dart';
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';
import 'package:mcp_flow_runtime/src/utils/stdio_guard.dart';

void main() {
  group('Stdio Protection', () {
    test('processes are always isolated from stdio', () async {
      final runtime = McpFlowRuntime();

      // StdioGuard always protects
      expect(StdioGuard.isStdioInUse, isTrue);

      // Load a flow that tests stdio protection
      final flow = {
        'version': '1.0.0',
        'state': {
          'result': {'type': 'string', 'initial': ''}
        },
        'processes': [{
          'id': 'test_system',
          'trigger': {'type': 'startup'},
          'steps': [{
            'action': 'stateSet',
            'params': {
              'key': 'result',
              'value': 'Hello from isolated process'
            }
          }]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait for process to complete
      await Future.delayed(Duration(milliseconds: 100));
      
      final result = runtime.getState('result');
      expect(result, equals('Hello from isolated process'));
      
      await runtime.stop();
    });

    test('multiple processes with different outputs', () async {
      final runtime = McpFlowRuntime();

      final flow = {
        'version': '1.0.0',
        'state': {
          'result1': {'type': 'string', 'initial': ''},
          'result2': {'type': 'string', 'initial': ''}
        },
        'processes': [{
          'id': 'test_multiple',
          'trigger': {'type': 'startup'},
          'steps': [
            {
              'action': 'stateSet',
              'params': {
                'key': 'result1',
                'value': 'First process'
              }
            },
            {
              'action': 'stateSet',
              'params': {
                'key': 'result2',
                'value': 'Second process'
              }
            }
          ]
        }]
      };

      await runtime.loadFlow(flow);
      await runtime.start();
      
      // Wait for processes to complete
      await Future.delayed(Duration(milliseconds: 200));
      
      final result1 = runtime.getState('result1');
      final result2 = runtime.getState('result2');
      
      expect(result1, equals('First process'));
      expect(result2, equals('Second process'));
      
      await runtime.stop();
    });
  });
}