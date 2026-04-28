/// Test cases TC-056 through TC-065 for ProcessWatchdog and RuntimeWatchdog
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/core/watchdog.dart';

void main() {
  group('TC-056: ProcessWatchdog.startMonitoring', () {
    test('TC-056a: starts monitoring with enabled config', () {
      final timeouts = <String>[];
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) => timeouts.add(id),
      );
      wd.startMonitoring('p1');
      // Should not throw, timer registered
      wd.dispose();
    });

    test('TC-056b: no-op when enabled=false', () {
      final timeouts = <String>[];
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: false, timeoutMs: 500),
        onTimeout: (id, action) => timeouts.add(id),
      );
      wd.startMonitoring('p1');
      // No timer should be registered
      wd.dispose();
    });

    test('TC-056c: duplicate start replaces timer', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) {},
      );
      wd.startMonitoring('p1');
      wd.startMonitoring('p1'); // Should replace, not throw
      wd.dispose();
    });
  });

  group('TC-057: ProcessWatchdog.heartbeat', () {
    test('TC-057a: regular heartbeat prevents timeout', () async {
      final timeouts = <String>[];
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 200),
        onTimeout: (id, action) => timeouts.add(id),
      );
      wd.startMonitoring('p1');
      // Send heartbeats faster than timeout
      for (var i = 0; i < 5; i++) {
        await Future.delayed(Duration(milliseconds: 50));
        wd.heartbeat('p1');
      }
      expect(timeouts, isEmpty);
      wd.dispose();
    });

    test('TC-057b: heartbeat is no-op when disabled', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: false),
        onTimeout: (id, action) {},
      );
      wd.heartbeat('unknown'); // Should not throw
      wd.dispose();
    });

    test('TC-057c: heartbeat for unregistered process updates activity', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) {},
      );
      wd.heartbeat('unknown_proc'); // Should not throw
      wd.dispose();
    });
  });

  group('TC-058: ProcessWatchdog timeout', () {
    test('TC-058a: timeout triggers callback', () async {
      final timeouts = <String>[];
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 100),
        onTimeout: (id, action) => timeouts.add(id),
      );
      wd.startMonitoring('p1');
      // Wait longer than timeout
      await Future.delayed(Duration(milliseconds: 250));
      expect(timeouts, contains('p1'));
      wd.dispose();
    });

    test('TC-058b: heartbeat just before timeout prevents trigger', () async {
      final timeouts = <String>[];
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 200),
        onTimeout: (id, action) => timeouts.add(id),
      );
      wd.startMonitoring('p1');
      await Future.delayed(Duration(milliseconds: 150));
      wd.heartbeat('p1');
      await Future.delayed(Duration(milliseconds: 100));
      expect(timeouts, isEmpty);
      wd.dispose();
    });

    test('TC-058c: critical process gets restart_runtime action', () async {
      final actions = <String>[];
      final wd = ProcessWatchdog(
        config: WatchdogConfig(
          enabled: true,
          timeoutMs: 100,
          criticalProcesses: ['main_loop'],
        ),
        onTimeout: (id, action) => actions.add(action),
      );
      wd.startMonitoring('main_loop');
      await Future.delayed(Duration(milliseconds: 250));
      expect(actions, contains('restart_runtime'));
      wd.dispose();
    });
  });

  group('TC-059: ProcessWatchdog.stopMonitoring', () {
    test('TC-059a: stops monitoring and removes timer', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) {},
      );
      wd.startMonitoring('p1');
      wd.stopMonitoring('p1');
      wd.dispose();
    });

    test('TC-059b: stop unregistered process is safe', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) {},
      );
      wd.stopMonitoring('nonexistent'); // Should not throw
      wd.dispose();
    });

    test('TC-059c: no timeout after stopMonitoring', () async {
      final timeouts = <String>[];
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 100),
        onTimeout: (id, action) => timeouts.add(id),
      );
      wd.startMonitoring('p1');
      wd.stopMonitoring('p1');
      await Future.delayed(Duration(milliseconds: 250));
      expect(timeouts, isEmpty);
      wd.dispose();
    });
  });

  group('TC-060: ProcessWatchdog.dispose', () {
    test('TC-060a: disposes all timers', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) {},
      );
      for (var i = 0; i < 5; i++) {
        wd.startMonitoring('p_$i');
      }
      wd.dispose();
    });

    test('TC-060b: dispose empty watchdog', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) {},
      );
      wd.dispose();
    });

    test('TC-060c: startMonitoring after dispose works', () {
      final wd = ProcessWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onTimeout: (id, action) {},
      );
      wd.dispose();
      wd.startMonitoring('p1'); // Should work since dispose just clears
      wd.dispose();
    });
  });

  group('TC-061: RuntimeWatchdog.start', () {
    test('TC-061a: starts monitoring', () {
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 1000),
        onSystemTimeout: (action) {},
      );
      wd.start();
      wd.dispose();
    });

    test('TC-061b: no-op when disabled', () {
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: false),
        onSystemTimeout: (action) {},
      );
      wd.start(); // Should not start timer
      wd.dispose();
    });

    test('TC-061c: double start replaces timer', () {
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 1000),
        onSystemTimeout: (action) {},
      );
      wd.start();
      wd.start(); // Should replace
      wd.dispose();
    });
  });

  group('TC-062: RuntimeWatchdog.heartbeat', () {
    test('TC-062a: regular heartbeat prevents timeout', () async {
      final timeouts = <String>[];
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 100),
        onSystemTimeout: (action) => timeouts.add(action),
      );
      wd.start();
      for (var i = 0; i < 5; i++) {
        await Future.delayed(Duration(milliseconds: 30));
        wd.heartbeat();
      }
      expect(timeouts, isEmpty);
      wd.dispose();
    });

    test('TC-062b: heartbeat no-op when disabled', () {
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: false),
        onSystemTimeout: (action) {},
      );
      wd.heartbeat(); // Should not throw
      wd.dispose();
    });
  });

  group('TC-063: RuntimeWatchdog system timeout', () {
    test('TC-063a: regular heartbeats prevent system timeout', () async {
      final timeouts = <String>[];
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 100),
        onSystemTimeout: (action) => timeouts.add(action),
      );
      wd.start();
      for (var i = 0; i < 10; i++) {
        await Future.delayed(Duration(milliseconds: 30));
        wd.heartbeat();
      }
      expect(timeouts, isEmpty);
      wd.dispose();
    });

    test('TC-063b: 3 missed heartbeats triggers system timeout', () async {
      final timeouts = <String>[];
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 60),
        onSystemTimeout: (action) => timeouts.add(action),
      );
      wd.start();
      // Wait for 3 check intervals to miss (each check is timeoutMs/3 = 20ms)
      // Need timeout exceeded 3 times: 60ms timeout, check every 20ms
      // After ~180ms+ with no heartbeat, 3 missed checks
      await Future.delayed(Duration(milliseconds: 300));
      expect(timeouts, isNotEmpty);
      wd.dispose();
    });

    test('TC-063c: recovery before 3 misses prevents timeout', () async {
      final timeouts = <String>[];
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 100),
        onSystemTimeout: (action) => timeouts.add(action),
      );
      wd.start();
      // Let 2 checks miss, then heartbeat
      await Future.delayed(Duration(milliseconds: 100));
      wd.heartbeat(); // Reset missed count
      await Future.delayed(Duration(milliseconds: 50));
      expect(timeouts, isEmpty);
      wd.dispose();
    });
  });

  group('TC-064: RuntimeWatchdog.stop', () {
    test('TC-064a: stops monitoring', () {
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onSystemTimeout: (action) {},
      );
      wd.start();
      wd.stop();
    });

    test('TC-064b: stop without start is safe', () {
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onSystemTimeout: (action) {},
      );
      wd.stop(); // Should not throw
    });

    test('TC-064c: no timeout after stop', () async {
      final timeouts = <String>[];
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 60),
        onSystemTimeout: (action) => timeouts.add(action),
      );
      wd.start();
      wd.stop();
      await Future.delayed(Duration(milliseconds: 300));
      expect(timeouts, isEmpty);
    });
  });

  group('TC-065: WatchdogConfig / dispose', () {
    test('TC-065a: WatchdogConfig.fromJson parses all fields', () {
      final config = WatchdogConfig.fromJson({
        'enabled': true,
        'timeoutMs': 5000,
        'action': 'restart_process',
        'criticalProcesses': ['main'],
      });
      expect(config.enabled, isTrue);
      expect(config.timeoutMs, equals(5000));
      expect(config.action, equals('restart_process'));
      expect(config.criticalProcesses, equals(['main']));
    });

    test('TC-065b: WatchdogConfig defaults', () {
      final config = WatchdogConfig.fromJson({});
      expect(config.enabled, isFalse);
      expect(config.timeoutMs, equals(30000));
      expect(config.action, equals('restart_process'));
      expect(config.criticalProcesses, isEmpty);
    });

    test('TC-065c: RuntimeWatchdog.dispose calls stop', () {
      final wd = RuntimeWatchdog(
        config: WatchdogConfig(enabled: true, timeoutMs: 500),
        onSystemTimeout: (action) {},
      );
      wd.start();
      wd.dispose(); // Should call stop internally
    });
  });
}
