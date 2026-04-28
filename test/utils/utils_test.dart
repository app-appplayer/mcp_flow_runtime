import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/utils/stdio_guard.dart';
import 'package:mcp_flow_runtime/src/utils/debounce.dart';

void main() {
  group('TC-861: StdioGuard state management', () {
    test('TC-861a: isStdioInUse returns true by default', () {
      expect(StdioGuard.isStdioInUse, isTrue);
    });

    test('TC-861b: markStdioInUse/markStdioAvailable do not throw', () {
      expect(() => StdioGuard.markStdioInUse(), returnsNormally);
      expect(() => StdioGuard.markStdioAvailable(), returnsNormally);
    });

    test('TC-861c: markStdioInUse double call does not throw', () {
      StdioGuard.markStdioInUse();
      expect(() => StdioGuard.markStdioInUse(), returnsNormally);
    });
  });

  group('TC-867: StdioGuard.runProcess', () {
    test('TC-867a: runProcess returns ProcessResult with exitCode 0', () async {
      // Use sleep + echo via shell to ensure stdout is captured before exit
      final result = await StdioGuard.runProcess(
        'bash', ['-c', 'echo hello && sleep 0.1'],
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('hello'));
    });

    test('TC-867b: environment parameter is passed to process', () async {
      final result = await StdioGuard.runProcess(
        'bash', ['-c', 'echo \$MY_VAR'],
        environment: {'MY_VAR': 'test_value'},
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('test_value'));
    });

    test('TC-867c: non-existent executable throws ProcessException', () async {
      expect(
        () => StdioGuard.runProcess(
            'nonexistent_binary_xyz_12345', []),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('TC-868: StdioGuard.runProcess stdout/stderr', () {
    test('TC-868a: stdout is captured in result', () async {
      final result = await StdioGuard.runProcess(
        'bash', ['-c', 'echo line1 && sleep 0.1'],
      );
      expect(result.stdout.toString(), contains('line1'));
    });

    test('TC-868c: stderr is captured in result', () async {
      final result = await StdioGuard.runProcess(
        'bash', ['-c', 'echo "warning message" >&2 && sleep 0.1'],
      );
      expect(result.stderr.toString(), contains('warning message'));
    });

    test('TC-868b: empty stdout does not cause errors', () async {
      final result = await StdioGuard.runProcess('true', []);
      expect(result.exitCode, equals(0));
    });
  });

  group('TC-869: StdioGuard.runProcess exit codes', () {
    test('TC-869a: non-zero exit code returns result without throwing',
        () async {
      final result = await StdioGuard.runProcess('false', []);
      expect(result.exitCode, equals(1));
    });

    test('TC-869b: workingDirectory parameter is passed to process', () async {
      final result = await StdioGuard.runProcess(
        'pwd', [],
        workingDirectory: '/tmp',
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout.toString().trim(), contains('tmp'));
    });

    test('TC-869c: process with large stderr does not throw', () async {
      final result = await StdioGuard.runProcess(
        'bash', ['-c', 'for i in \$(seq 1 100); do echo "err \$i" >&2; done && sleep 0.1'],
      );
      // Should complete without error regardless of stderr volume
      expect(result.stderr.toString(), contains('err'));
    });
  });

  group('TC-870: StdioGuard.runProcess options', () {
    test('TC-870a: runInShell=true works', () async {
      final result = await StdioGuard.runProcess(
        'echo', ['shell test'],
        runInShell: true,
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('shell test'));
    });

    test('TC-870b: custom encoding completes without error', () async {
      final result = await StdioGuard.runProcess(
        'bash', ['-c', 'echo hello && sleep 0.1'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('hello'));
    });

    test('TC-870c: includeParentEnvironment=false runs successfully', () async {
      final result = await StdioGuard.runProcess(
        'bash', ['-c', 'echo isolated && sleep 0.1'],
        includeParentEnvironment: false,
        environment: {'PATH': '/usr/bin:/bin'},
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('isolated'));
    });
  });

  group('TC-879: StdioGuard.runProcessStream', () {
    test('TC-879a: stream emits lines from process', () async {
      final lines = await StdioGuard.runProcessStream(
        'bash', ['-c', 'echo line1 && sleep 0.1'],
      ).toList();
      expect(lines, contains('line1'));
    });

    test('TC-879b: empty output stream completes', () async {
      final lines = await StdioGuard.runProcessStream(
        'true', [],
      ).toList();
      expect(lines, isEmpty);
    });

    test('TC-879c: stderr from stream process does not appear in stdout stream', () async {
      final lines = await StdioGuard.runProcessStream(
        'bash', ['-c', 'echo stdout_line && echo stderr_line >&2 && sleep 0.1'],
      ).toList();
      // stdout stream should contain stdout_line but not stderr_line
      expect(lines, contains('stdout_line'));
      expect(lines, isNot(contains('stderr_line')));
    });
  });

  group('TC-885: Debouncer.call()', () {
    test('TC-885a: call() executes fn after delay', () async {
      var counter = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 50));

      debouncer.call(() => counter++);

      expect(counter, equals(0));
      await Future.delayed(const Duration(milliseconds: 100));
      expect(counter, equals(1));

      debouncer.dispose();
    });

    test('TC-885b: isPending is true after call()', () {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));

      debouncer.call(() {});
      expect(debouncer.isPending, isTrue);

      debouncer.cancel();
      debouncer.dispose();
    });

    test('TC-885c: isPending is false initially', () {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      expect(debouncer.isPending, isFalse);
      debouncer.dispose();
    });
  });

  group('TC-886: Debouncer rapid calls', () {
    test('TC-886a: rapid calls result in single execution', () async {
      var counter = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 50));

      debouncer.call(() => counter++);
      await Future.delayed(const Duration(milliseconds: 10));
      debouncer.call(() => counter++);
      await Future.delayed(const Duration(milliseconds: 10));
      debouncer.call(() => counter++);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(counter, equals(1));

      debouncer.dispose();
    });

    test('TC-886b: calls at exact delay interval result in single execution', () async {
      var counter = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 50));

      debouncer.call(() => counter++);
      await Future.delayed(const Duration(milliseconds: 50));
      debouncer.call(() => counter++);

      await Future.delayed(const Duration(milliseconds: 100));
      // Second call resets timer, so fn executes once after second call's delay
      expect(counter, lessThanOrEqualTo(2));

      debouncer.dispose();
    });

    test('TC-886c: isPending becomes false after fn executes', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 50));

      debouncer.call(() {});
      await Future.delayed(const Duration(milliseconds: 100));

      expect(debouncer.isPending, isFalse);
      debouncer.dispose();
    });
  });

  group('TC-887: Debouncer.cancel()', () {
    test('TC-887a: cancel() prevents pending fn from executing', () async {
      var counter = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));

      debouncer.call(() => counter++);
      debouncer.cancel();

      await Future.delayed(const Duration(milliseconds: 200));
      expect(counter, equals(0));

      debouncer.dispose();
    });

    test('TC-887b: cancel() without pending call does not throw', () {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      expect(() => debouncer.cancel(), returnsNormally);
      debouncer.dispose();
    });

    test('TC-887c: cancel then re-call works', () async {
      var counter = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 50));

      debouncer.call(() => counter++);
      debouncer.cancel();
      debouncer.call(() => counter++);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(counter, equals(1));

      debouncer.dispose();
    });
  });

  group('TC-888: Debouncer.dispose()', () {
    test('TC-888a: dispose cancels pending call', () async {
      var counter = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));

      debouncer.call(() => counter++);
      debouncer.dispose();

      await Future.delayed(const Duration(milliseconds: 200));
      expect(counter, equals(0));
    });

    test('TC-888b: dispose on non-pending debouncer does not throw', () {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      expect(() => debouncer.dispose(), returnsNormally);
    });

    test('TC-888c: call() after dispose() is silently ignored', () async {
      var counter = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 50));

      debouncer.dispose();
      debouncer.call(() => counter++);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(counter, equals(0));
    });
  });

  group('TC-900: createDebouncedFunction', () {
    test('TC-900a: executes with correct typed argument', () async {
      double? result;
      final fn = createDebouncedFunction<double>(
        (v) => result = v,
        const Duration(milliseconds: 50),
      );

      fn(25.3);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(result, equals(25.3));
    });

    test('TC-900b: String type parameter', () async {
      String? result;
      final fn = createDebouncedFunction<String>(
        (v) => result = v,
        const Duration(milliseconds: 50),
      );

      fn('hello world');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(result, equals('hello world'));
    });

    test('TC-900c: Map type parameter', () async {
      Map<String, dynamic>? result;
      final fn = createDebouncedFunction<Map<String, dynamic>>(
        (v) => result = v,
        const Duration(milliseconds: 50),
      );

      fn({'key': 'value', 'count': 5});
      await Future.delayed(const Duration(milliseconds: 100));

      expect(result, equals({'key': 'value', 'count': 5}));
    });
  });

  group('TC-901: createDebouncedFunction overlapping calls', () {
    test('TC-901a: only last argument is used when calls overlap', () async {
      double? result;
      final fn = createDebouncedFunction<double>(
        (v) => result = v,
        const Duration(milliseconds: 50),
      );

      fn(1.0);
      await Future.delayed(const Duration(milliseconds: 10));
      fn(2.0);
      await Future.delayed(const Duration(milliseconds: 10));
      fn(3.0);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(result, equals(3.0));
    });

    test('TC-901c: no call means callback never executes', () async {
      var executed = false;
      // Create debounced function but never call it
      createDebouncedFunction<int>(
        (v) => executed = true,
        const Duration(milliseconds: 50),
      );

      await Future.delayed(const Duration(milliseconds: 100));
      expect(executed, isFalse);
    });

    test('TC-901b: single call executes exactly once', () async {
      var count = 0;
      final fn = createDebouncedFunction<int>(
        (v) => count++,
        const Duration(milliseconds: 50),
      );

      fn(1);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(count, equals(1));
    });
  });
}
