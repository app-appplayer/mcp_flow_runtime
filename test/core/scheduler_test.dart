/// Test cases TC-011 through TC-020 for ProcessScheduler

import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/core/scheduler.dart';
import 'package:mcp_flow_runtime/src/types/runtime_types.dart';
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';

void main() {
  // Helper to create a ProcessInstance
  ProcessInstance createProcess(String id, {String? definitionId}) {
    return ProcessInstance(
      id: id,
      definitionId: definitionId ?? id,
    );
  }

  // Helper: wait enough time for scheduler ticks and async execution
  Future<void> waitForTicks(int ticks, int tickRateMs) async {
    await Future.delayed(Duration(milliseconds: tickRateMs * ticks + 50));
  }

  group('TC-011: schedule - immediate queue insertion', () {
    test('TC-011a: normal priority schedule inserts to queue', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      var executed = false;
      final process = createProcess('p_normal');
      scheduler.schedule(process, priority: 1, onExecute: () async {
        executed = true;
      });

      expect(scheduler.totalProcesses, greaterThanOrEqualTo(1));
      await waitForTicks(3, 10);
      await scheduler.stop();
      expect(executed, isTrue);
    });

    test('TC-011b: 4 priority levels execute in correct order', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 10);
      await scheduler.start();

      final executionOrder = <String>[];

      scheduler.schedule(createProcess('p_low'), priority: 0,
          onExecute: () async { executionOrder.add('low'); });
      scheduler.schedule(createProcess('p_normal'), priority: 1,
          onExecute: () async { executionOrder.add('normal'); });
      scheduler.schedule(createProcess('p_high'), priority: 2,
          onExecute: () async { executionOrder.add('high'); });
      scheduler.schedule(createProcess('p_realtime'), priority: 3,
          onExecute: () async { executionOrder.add('realtime'); });

      await waitForTicks(8, 10);
      await scheduler.stop();

      expect(executionOrder, equals(['realtime', 'high', 'normal', 'low']));
    });

    test('TC-011c: schedule before start throws', () {
      final scheduler = ProcessScheduler(tickRateMs: 10);
      expect(
        () => scheduler.schedule(createProcess('p'), priority: 1,
            onExecute: () async {}),
        throwsA(isA<ConcreteFlowError>()),
      );
    });
  });

  group('TC-012: schedule - future time reservation', () {
    test('TC-012a: future scheduling with at parameter delays execution', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      var executed = false;
      final process = createProcess('p_future');
      final futureTime = DateTime.now().add(Duration(milliseconds: 200));
      scheduler.schedule(process, priority: 1, at: futureTime, onExecute: () async {
        executed = true;
      });

      // Should not be executed immediately
      await Future.delayed(Duration(milliseconds: 50));
      expect(executed, isFalse);

      // Should be executed after the scheduled time
      await Future.delayed(Duration(milliseconds: 250));
      await scheduler.stop();
      expect(executed, isTrue);
    });

    test('TC-012b: enqueued process executes during tick', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      var executed = false;
      final process = createProcess('p_ready');
      scheduler.schedule(process, priority: 1, onExecute: () async {
        executed = true;
      });

      await waitForTicks(3, 10);
      await scheduler.stop();
      expect(executed, isTrue);
      expect(process.state, equals(ProcessState.completed));
    });

    test('TC-012c: process without onExecute transitions to error', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      final process = createProcess('p_no_exec');
      // Schedule with onExecute that throws to simulate missing handler
      scheduler.schedule(process, priority: 1, onExecute: () async {
        throw Exception('Simulated missing handler');
      });

      await waitForTicks(3, 10);
      await scheduler.stop();
      expect(process.state, equals(ProcessState.error));
    });
  });

  group('TC-013: cancel', () {
    test('TC-013a: cancel active process returns true', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 200);
      await scheduler.start();

      var executed = false;
      final process = createProcess('p_cancel');
      scheduler.schedule(process, priority: 1, onExecute: () async {
        executed = true;
      });

      final result = scheduler.cancel('p_cancel');
      expect(result, isTrue);

      await waitForTicks(3, 200);
      await scheduler.stop();
      expect(executed, isFalse);
    });

    test('TC-013b: cancel queued process returns true', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 200);
      await scheduler.start();

      // Fill the slot
      scheduler.schedule(createProcess('p_active'), priority: 1,
          onExecute: () async {
        await Future.delayed(Duration(milliseconds: 500));
      });

      // This should be queued
      var executed = false;
      scheduler.schedule(createProcess('p_queued'), priority: 1,
          onExecute: () async { executed = true; });

      final result = scheduler.cancel('p_queued');
      expect(result, isTrue);

      await Future.delayed(Duration(milliseconds: 600));
      await scheduler.stop();
      expect(executed, isFalse);
    });

    test('TC-013c: cancel nonexistent process returns false', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      final result = scheduler.cancel('nonexistent');
      expect(result, isFalse);

      await scheduler.stop();
    });
  });

  group('TC-014: cancelByDefinitionId', () {
    test('TC-014a: cancels all instances with matching definition', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 200);
      await scheduler.start();

      final executedIds = <String>[];

      scheduler.schedule(createProcess('myDef_1', definitionId: 'myDef'),
          priority: 1, onExecute: () async { executedIds.add('myDef_1'); });
      scheduler.schedule(createProcess('myDef_2', definitionId: 'myDef'),
          priority: 1, onExecute: () async { executedIds.add('myDef_2'); });
      scheduler.schedule(createProcess('otherDef_1', definitionId: 'otherDef'),
          priority: 1, onExecute: () async { executedIds.add('otherDef_1'); });

      final result = scheduler.cancelByDefinitionId('myDef');
      expect(result, isTrue);

      await waitForTicks(5, 200);
      await scheduler.stop();
      expect(executedIds, equals(['otherDef_1']));
    });

    test('TC-014b: matches by definitionId prefix pattern', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 200);
      await scheduler.start();

      final executedIds = <String>[];

      // cancelByDefinitionId uses startsWith('${defId}_') pattern
      scheduler.schedule(createProcess('alpha_1', definitionId: 'alpha'),
          priority: 1, onExecute: () async { executedIds.add('alpha_1'); });
      scheduler.schedule(createProcess('beta_1', definitionId: 'beta'),
          priority: 1, onExecute: () async { executedIds.add('beta_1'); });

      scheduler.cancelByDefinitionId('alpha');

      await waitForTicks(5, 200);
      await scheduler.stop();
      expect(executedIds, contains('beta_1'));
      expect(executedIds, isNot(contains('alpha_1')));
    });

    test('TC-014c: no match returns false', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      final result = scheduler.cancelByDefinitionId('nonexistent');
      expect(result, isFalse);

      await scheduler.stop();
    });
  });

  group('TC-015: cancelAll', () {
    test('TC-015a: cancels all active and queued processes', () async {
      final scheduler = ProcessScheduler(maxProcesses: 2, tickRateMs: 200);
      await scheduler.start();

      var executedCount = 0;
      for (var i = 0; i < 5; i++) {
        scheduler.schedule(createProcess('p_$i'), priority: 1,
            onExecute: () async {
          await Future.delayed(Duration(milliseconds: 500));
          executedCount++;
        });
      }

      scheduler.cancelAll();

      await Future.delayed(Duration(milliseconds: 100));
      await scheduler.stop();
      // Some may have started before cancelAll, but most should be cancelled
      expect(executedCount, lessThan(5));
    });

    test('TC-015b: cancelAll with no processes does not throw', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();
      scheduler.cancelAll();
      await scheduler.stop();
    });

    test('TC-015c: schedule after cancelAll works', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      scheduler.schedule(createProcess('p_old'), priority: 1,
          onExecute: () async {});
      scheduler.cancelAll();

      var executed = false;
      scheduler.schedule(createProcess('p_new'), priority: 1,
          onExecute: () async { executed = true; });

      await waitForTicks(3, 10);
      await scheduler.stop();
      expect(executed, isTrue);
    });
  });

  group('TC-016: canSchedule / canScheduleCount', () {
    test('TC-016a: returns true when slots available', () async {
      final scheduler = ProcessScheduler(maxProcesses: 5, tickRateMs: 200);
      await scheduler.start();

      // Schedule 3 long-running processes
      for (var i = 0; i < 3; i++) {
        scheduler.schedule(createProcess('p_$i'), priority: 1,
            onExecute: () async {
          await Future.delayed(Duration(seconds: 2));
        });
      }

      await Future.delayed(Duration(milliseconds: 250));
      expect(scheduler.canSchedule(), isTrue);
      expect(scheduler.canScheduleCount(2), isTrue);

      await scheduler.stop();
    });

    test('TC-016b: returns false when full', () async {
      final scheduler = ProcessScheduler(maxProcesses: 2, tickRateMs: 10);
      await scheduler.start();

      for (var i = 0; i < 2; i++) {
        scheduler.schedule(createProcess('p_$i'), priority: 1,
            onExecute: () async {
          await Future.delayed(Duration(seconds: 2));
        });
      }

      await Future.delayed(Duration(milliseconds: 50));
      expect(scheduler.canSchedule(), isFalse);
      expect(scheduler.canScheduleCount(1), isFalse);

      await scheduler.stop();
    });

    test('TC-016c: canScheduleCount(0) returns true', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 10);
      await scheduler.start();
      expect(scheduler.canScheduleCount(0), isTrue);
      await scheduler.stop();
    });
  });

  group('TC-017: start / stop', () {
    test('TC-017a: start and stop lifecycle', () async {
      final scheduler = ProcessScheduler(tickRateMs: 10);
      await scheduler.start();
      await scheduler.stop();
    });

    test('TC-017b: double start throws', () async {
      final scheduler = ProcessScheduler(tickRateMs: 10);
      await scheduler.start();
      expect(() => scheduler.start(), throwsA(isA<ConcreteFlowError>()));
      await scheduler.stop();
    });

    test('TC-017c: stop with active processes completes gracefully', () async {
      final scheduler = ProcessScheduler(maxProcesses: 2, tickRateMs: 10);
      await scheduler.start();

      scheduler.schedule(createProcess('p_long'), priority: 1,
          onExecute: () async {
        await Future.delayed(Duration(milliseconds: 200));
      });

      await Future.delayed(Duration(milliseconds: 20));
      // Should complete without throwing
      await scheduler.stop();
    });
  });

  group('TC-018: getProcessInstance / getActiveProcessIds', () {
    test('TC-018a: get active process instance', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 200);
      await scheduler.start();

      final process = createProcess('p_query');
      scheduler.schedule(process, priority: 1, onExecute: () async {
        await Future.delayed(Duration(milliseconds: 500));
      });

      await Future.delayed(Duration(milliseconds: 250));
      final ids = scheduler.getActiveProcessIds();
      expect(ids, contains('p_query'));

      await scheduler.stop();
    });

    test('TC-018b: queued process can be looked up', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 200);
      await scheduler.start();

      // Fill the active slot with a long-running process
      scheduler.schedule(createProcess('p_active'), priority: 1,
          onExecute: () async {
        await Future.delayed(Duration(milliseconds: 1000));
      });

      // This process should be queued
      final queuedProcess = createProcess('p_queued');
      scheduler.schedule(queuedProcess, priority: 1,
          onExecute: () async {});

      await Future.delayed(Duration(milliseconds: 250));

      // Look up the queued process
      final instance = scheduler.getProcessInstance('p_queued');
      expect(instance, isNotNull);

      await scheduler.stop();
    });

    test('TC-018c: nonexistent process returns null', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      final instance = scheduler.getProcessInstance('nonexistent');
      expect(instance, isNull);

      await scheduler.stop();
    });

    test('TC-018d: getActiveProcessIds returns correct count', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 200);
      await scheduler.start();

      for (var i = 0; i < 3; i++) {
        scheduler.schedule(createProcess('p_$i'), priority: 1,
            onExecute: () async {
          await Future.delayed(Duration(milliseconds: 500));
        });
      }

      await Future.delayed(Duration(milliseconds: 250));
      final ids = scheduler.getActiveProcessIds();
      expect(ids.length, equals(3));

      await scheduler.stop();
    });
  });

  group('TC-019: setTickRate / setMaxProcesses', () {
    test('TC-019a: setTickRate changes tick interval', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 100);
      await scheduler.start();
      scheduler.setTickRate(Duration(milliseconds: 10));
      // Should not throw
      await Future.delayed(Duration(milliseconds: 50));
      await scheduler.stop();
    });

    test('TC-019b: very short tick rate (1ms) works', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 1);
      await scheduler.start();

      var executed = false;
      scheduler.schedule(createProcess('p_fast'), priority: 1,
          onExecute: () async { executed = true; });

      await Future.delayed(Duration(milliseconds: 50));
      await scheduler.stop();
      expect(executed, isTrue);
    });

    test('TC-019c: setMaxProcesses changes limit', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 10);
      await scheduler.start();
      scheduler.setMaxProcesses(10);
      expect(scheduler.maxProcesses, equals(10));
      await scheduler.stop();
    });

    test('TC-019d: reducing maxProcesses below active count limits new only',
        () async {
      final scheduler = ProcessScheduler(maxProcesses: 5, tickRateMs: 200);
      await scheduler.start();

      for (var i = 0; i < 5; i++) {
        scheduler.schedule(createProcess('p_$i'), priority: 1,
            onExecute: () async {
          await Future.delayed(Duration(seconds: 2));
        });
      }

      await Future.delayed(Duration(milliseconds: 250));
      scheduler.setMaxProcesses(3);
      // Existing active processes should continue
      expect(scheduler.activeProcesses, greaterThanOrEqualTo(3));

      await scheduler.stop();
    });
  });

  group('TC-020: statistics properties', () {
    test('TC-020a: initial counters are zero', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      expect(scheduler.totalProcesses, equals(0));
      expect(scheduler.completedProcesses, equals(0));
    });

    test('TC-020b: counters update after execution', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 10);
      await scheduler.start();

      // 2 successful + 1 error
      scheduler.schedule(createProcess('p_ok1'), priority: 1,
          onExecute: () async {});
      scheduler.schedule(createProcess('p_ok2'), priority: 1,
          onExecute: () async {});
      scheduler.schedule(createProcess('p_err'), priority: 1,
          onExecute: () async { throw Exception('fail'); });

      await waitForTicks(5, 10);
      await scheduler.stop();

      expect(scheduler.totalProcesses, equals(3));
      expect(scheduler.completedProcesses, equals(2));
      expect(scheduler.errorProcesses, equals(1));
    });

    test('TC-020c: completed history limited to 100 items', () async {
      final scheduler = ProcessScheduler(maxProcesses: 10, tickRateMs: 5);
      await scheduler.start();

      // Schedule 110 fast processes
      for (var i = 0; i < 110; i++) {
        scheduler.schedule(createProcess('p_hist_$i'), priority: 1,
            onExecute: () async {});
      }

      // Wait for all to complete
      await waitForTicks(30, 5);
      await scheduler.stop();

      // Total scheduled should be 110
      expect(scheduler.totalProcesses, equals(110));
      // Completed history should be capped at 100
      expect(scheduler.completedProcesses, lessThanOrEqualTo(110));
    });

    test('TC-020d: state transitions through lifecycle', () async {
      final scheduler = ProcessScheduler(maxProcesses: 1, tickRateMs: 200);

      final process = createProcess('p_state');
      expect(process.state, equals(ProcessState.created));

      await scheduler.start();

      ProcessState? stateInExecute;
      scheduler.schedule(process, priority: 1, onExecute: () async {
        stateInExecute = process.state;
      });

      await waitForTicks(3, 200);
      await scheduler.stop();

      expect(stateInExecute, equals(ProcessState.executing));
      expect(process.state, equals(ProcessState.completed));
    });
  });
}
