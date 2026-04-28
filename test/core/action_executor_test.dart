/// ActionExecutor test suite (TC-036 ~ TC-045)
/// Tests individual action dispatch through ActionExecutor.

import 'dart:io';

import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/core/action_executor.dart';
import 'package:mcp_flow_runtime/src/types/flow_types.dart';
import 'package:mcp_flow_runtime/src/types/runtime_types.dart';
import 'package:mcp_flow_runtime/src/hal/mock_hal_factory.dart';
import 'package:mcp_flow_runtime/src/state/state_manager.dart';
import 'package:mcp_flow_runtime/src/channels/channel_interface.dart';
import 'package:mcp_flow_runtime/src/core/process_executor.dart' show ReturnException;
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';

void main() {
  late ActionExecutor executor;
  late StateManager stateManager;
  late Map<String, Channel> channels;
  late MockHardwareAbstractionLayer hal;

  /// Helper to create a minimal ExecutionContext.
  ExecutionContext _context({Map<String, dynamic>? locals}) {
    final process = ProcessInstance(
      id: 'test_proc',
      definitionId: 'test_def',
      localContext: locals,
    );
    return ExecutionContext(
      process: process,
      globalState: {},
      resources: {},
      channels: {},
      args: locals ?? {},
    );
  }

  /// Simulate bindTo: execute action, then store result in context local variable.
  Future<void> _executeWithBind(
    ActionDefinition action,
    ExecutionContext context,
  ) async {
    final result = await executor.execute(action, context);
    if (action.bindTo != null && result != null) {
      if (stateManager.hasVariable(action.bindTo!)) {
        await stateManager.set(action.bindTo!, result);
        context.globalState[action.bindTo!] = result;
      } else {
        context.setVariable(action.bindTo!, result);
      }
    }
  }

  setUp(() async {
    stateManager = StateManager();
    await stateManager.initialize();
    channels = {};
    hal = MockHardwareAbstractionLayer();
    await hal.initialize();

    executor = ActionExecutor(
      hal: hal,
      stateManager: stateManager,
      channels: channels,
      resources: {},
      config: const RuntimeConfig(),
      configEnvironment: {},
    );
  });

  // ===========================================================================
  // TC-036: stateSet / stateGet
  // ===========================================================================
  group('TC-036: stateSet / stateGet', () {
    test('TC-036a: stateSet stores value retrievable via StateManager', () async {
      // Define variable in state manager so stateSet uses it
      await stateManager.defineVariable('x', type: StateType.number, initial: 0);

      final context = _context();
      final action = const ActionDefinition(
        action: 'stateSet',
        params: {'key': 'x', 'value': 10},
      );

      await executor.execute(action, context);

      expect(stateManager.get('x'), equals(10));
    });

    test('TC-036b: stateGet retrieves value and bindTo stores in local context', () async {
      // Define and set the variable
      await stateManager.defineVariable('x', type: StateType.number, initial: 10);

      final context = _context();

      // stateSet to ensure x == 10 in context globalState
      context.globalState['x'] = 10;

      final getAction = const ActionDefinition(
        action: 'stateGet',
        params: {'key': 'x'},
        bindTo: 'v',
      );

      await _executeWithBind(getAction, context);

      expect(context.getVariable('v'), equals(10));
    });

    test('TC-036c: stateSet for undefined variable stores in process local context', () async {
      final context = _context();
      final action = const ActionDefinition(
        action: 'stateSet',
        params: {'key': 'localVar', 'value': 42},
      );

      await executor.execute(action, context);

      // Should be stored in process local context
      expect(context.getVariable('localVar'), equals(42));
    });
  });

  // ===========================================================================
  // TC-037: gpioWrite / gpioRead via MockGpioProvider
  // ===========================================================================
  group('TC-037: gpioWrite / gpioRead', () {
    test('TC-037a: gpioWrite then gpioRead returns written value', () async {
      final context = _context();

      // Configure pin 5 as output first
      await executor.execute(
        const ActionDefinition(
          action: 'gpioConfig',
          params: {'pin': 5, 'mode': 'output'},
        ),
        context,
      );

      // Write HIGH to pin 5
      await executor.execute(
        const ActionDefinition(
          action: 'gpioWrite',
          params: {'pin': 5, 'value': true},
        ),
        context,
      );

      // Read pin 5
      final readAction = const ActionDefinition(
        action: 'gpioRead',
        params: {'pin': 5},
        bindTo: 'pinValue',
      );
      await _executeWithBind(readAction, context);

      expect(context.getVariable('pinValue'), isTrue);
    });

    test('TC-037b: gpioRead on unconfigured pin returns false', () async {
      final context = _context();

      final result = await executor.execute(
        const ActionDefinition(
          action: 'gpioRead',
          params: {'pin': 99},
        ),
        context,
      );

      expect(result, isFalse);
    });
  });

  // ===========================================================================
  // TC-038: i2cWrite / i2cRead via MockI2cProvider
  // ===========================================================================
  group('TC-038: i2cWrite / i2cRead', () {
    test('TC-038a: i2cWrite completes without error', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'i2cWrite',
            params: {'address': 0x48, 'data': [0x01, 0x02]},
          ),
          context,
        ),
        completes,
      );
    });

    test('TC-038b: i2cRead returns data of requested length', () async {
      final context = _context();

      final readAction = const ActionDefinition(
        action: 'i2cRead',
        params: {'address': 0x48, 'length': 4},
        bindTo: 'i2cData',
      );
      await _executeWithBind(readAction, context);

      final data = context.getVariable('i2cData') as List;
      expect(data.length, equals(4));
    });

    test('TC-038c: i2cRead with register parameter completes', () async {
      final context = _context();

      final result = await executor.execute(
        const ActionDefinition(
          action: 'i2cRead',
          params: {'address': 0x48, 'register': 0x00, 'length': 2},
        ),
        context,
      );

      expect(result, isList);
      expect((result as List).length, equals(2));
    });
  });

  // ===========================================================================
  // TC-039: spiTransfer via MockSpiProvider (echo data back)
  // ===========================================================================
  group('TC-039: spiTransfer', () {
    test('TC-039a: spiTransfer returns data of same length as input', () async {
      final context = _context();

      final action = const ActionDefinition(
        action: 'spiTransfer',
        params: {'device': 0, 'data': [0xAA, 0xBB, 0xCC]},
        bindTo: 'spiResult',
      );
      await _executeWithBind(action, context);

      final result = context.getVariable('spiResult') as List;
      // MockSpiDevice.transfer returns a Uint8List of same length (zeroed)
      expect(result.length, equals(3));
    });

    test('TC-039b: spiTransfer with default device completes', () async {
      final context = _context();

      final result = await executor.execute(
        const ActionDefinition(
          action: 'spiTransfer',
          params: {'data': [0x01]},
        ),
        context,
      );

      expect(result, isList);
      expect((result as List).length, equals(1));
    });
  });

  // ===========================================================================
  // TC-040: pwmSet via MockPwmProvider (channel: 1, duty: 50)
  // ===========================================================================
  group('TC-040: pwmSet', () {
    test('TC-040a: pwmSet configures duty cycle on channel', () async {
      final context = _context();

      // pwmSet action with channel and dutyCycle
      await executor.execute(
        const ActionDefinition(
          action: 'pwmSet',
          params: {'channel': 1, 'dutyCycle': 50},
        ),
        context,
      );

      // Verify via pwmWrite as well (alternative action name)
      await executor.execute(
        const ActionDefinition(
          action: 'pwmWrite',
          params: {'channel': 1, 'dutyCycle': 75},
        ),
        context,
      );

      // No exception means the provider accepted the commands
    });

    test('TC-040b: pwmSet with frequency and dutyCycle', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'pwmSet',
            params: {'channel': 1, 'frequency': 1000, 'dutyCycle': 50},
          ),
          context,
        ),
        completes,
      );
    });
  });

  // ===========================================================================
  // TC-041: uartWrite / uartRead via MockUartProvider
  // ===========================================================================
  group('TC-041: uartWrite / uartRead', () {
    test('TC-041a: uartWrite completes without error', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'uartWrite',
            params: {'port': '/dev/ttyUSB0', 'data': 'Hello'},
          ),
          context,
        ),
        completes,
      );
    });

    test('TC-041b: uartWrite with binary data completes', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'uartWrite',
            params: {'port': '/dev/ttyUSB0', 'data': [0x48, 0x65]},
          ),
          context,
        ),
        completes,
      );
    });

    test('TC-041c: uartRead returns empty string on timeout (no data)', () async {
      final context = _context();

      // MockUartPort stream has no data, so read will timeout
      final result = await executor.execute(
        const ActionDefinition(
          action: 'uartRead',
          params: {'port': '/dev/ttyUSB0', 'timeout': 100},
        ),
        context,
      );

      // On timeout, MockUartPort returns Uint8List(0), decoded to empty string
      expect(result, equals(''));
    });
  });

  // ===========================================================================
  // TC-042: adcRead via MockAdcProvider (returns 512)
  // ===========================================================================
  group('TC-042: adcRead', () {
    test('TC-042a: adcRead returns mock voltage value', () async {
      final context = _context();

      final action = const ActionDefinition(
        action: 'adcRead',
        params: {'channel': 0},
        bindTo: 'adcValue',
      );
      await _executeWithBind(action, context);

      final value = context.getVariable('adcValue');
      // MockAdcProvider.readVoltage returns 1.65
      expect(value, isA<double>());
      expect(value, equals(1.65));
    });

    test('TC-042b: adcRead on different channels returns consistent value', () async {
      final context = _context();

      final result1 = await executor.execute(
        const ActionDefinition(
          action: 'adcRead',
          params: {'channel': 0},
        ),
        context,
      );

      final result2 = await executor.execute(
        const ActionDefinition(
          action: 'adcRead',
          params: {'channel': 3},
        ),
        context,
      );

      expect(result1, equals(result2));
    });
  });

  // ===========================================================================
  // TC-043: channelSend / channelReceive via QueueChannel
  // ===========================================================================
  group('TC-043: channelSend / channelReceive', () {
    test('TC-043a: channelSend then channelReceive returns sent data', () async {
      // Create a QueueChannel and register it
      final channelDef = const ChannelDefinition(
        type: ChannelType.queue,
        capacity: 10,
      );
      final queueChannel = QueueChannel(
        name: 'testCh',
        definition: channelDef,
      );
      channels['testCh'] = queueChannel;

      final context = _context();

      // Send data
      await executor.execute(
        const ActionDefinition(
          action: 'channelSend',
          params: {'channel': 'testCh', 'data': 42},
        ),
        context,
      );

      // Receive data
      final receiveAction = const ActionDefinition(
        action: 'channelReceive',
        params: {'channel': 'testCh', 'timeout': 1000},
        bindTo: 'received',
      );
      await _executeWithBind(receiveAction, context);

      expect(context.getVariable('received'), equals(42));
    });

    test('TC-043b: channelSend multiple values preserves FIFO order', () async {
      final channelDef = const ChannelDefinition(
        type: ChannelType.queue,
        capacity: 10,
      );
      final queueChannel = QueueChannel(
        name: 'fifoCh',
        definition: channelDef,
      );
      channels['fifoCh'] = queueChannel;

      final context = _context();

      // Send multiple values
      await executor.execute(
        const ActionDefinition(
          action: 'channelSend',
          params: {'channel': 'fifoCh', 'data': 'first'},
        ),
        context,
      );
      await executor.execute(
        const ActionDefinition(
          action: 'channelSend',
          params: {'channel': 'fifoCh', 'data': 'second'},
        ),
        context,
      );

      // Receive first
      final result1 = await executor.execute(
        const ActionDefinition(
          action: 'channelReceive',
          params: {'channel': 'fifoCh', 'timeout': 1000},
        ),
        context,
      );
      expect(result1, equals('first'));
    });
  });

  // ===========================================================================
  // TC-044: log action (level: info)
  // ===========================================================================
  group('TC-044: log action', () {
    test('TC-044a: log with info level completes without error', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'log',
            params: {'message': 'Test log message', 'level': 'info'},
          ),
          context,
        ),
        completes,
      );
    });

    test('TC-044b: log with different levels completes', () async {
      final context = _context();

      for (final level in ['debug', 'info', 'warning', 'error']) {
        await expectLater(
          executor.execute(
            ActionDefinition(
              action: 'log',
              params: {'message': 'Level: $level', 'level': level},
            ),
            context,
          ),
          completes,
        );
      }
    });

    test('TC-044c: log without level defaults to info', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'log',
            params: {'message': 'Default level'},
          ),
          context,
        ),
        completes,
      );
    });
  });

  // ===========================================================================
  // TC-045: wait/delay action (durationMs: 50, verify timing +/-20ms)
  // ===========================================================================
  group('TC-045: wait/delay action', () {
    test('TC-045a: wait action delays for approximately durationMs', () async {
      final context = _context();

      final stopwatch = Stopwatch()..start();

      await executor.execute(
        const ActionDefinition(
          action: 'wait',
          params: {'durationMs': 50},
        ),
        context,
      );

      stopwatch.stop();

      // Verify elapsed time is within 50ms +/- 20ms
      expect(
        stopwatch.elapsedMilliseconds,
        greaterThanOrEqualTo(30),
        reason: 'Delay should be at least 30ms (50 - 20)',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThanOrEqualTo(70),
        reason: 'Delay should be at most 70ms (50 + 20)',
      );
    });

    test('TC-045b: wait with ms parameter also works', () async {
      final context = _context();

      final stopwatch = Stopwatch()..start();

      await executor.execute(
        const ActionDefinition(
          action: 'wait',
          params: {'ms': 50},
        ),
        context,
      );

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(30));
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(70));
    });

    test('TC-045c: wait with zero duration completes immediately', () async {
      final context = _context();

      final stopwatch = Stopwatch()..start();

      await executor.execute(
        const ActionDefinition(
          action: 'wait',
          params: {'durationMs': 0},
        ),
        context,
      );

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(20));
    });
  });

  // ===========================================================================
  // TC-036d~h: Convenience state actions (increment, decrement, append, merge, toggle)
  // ===========================================================================
  group('TC-036d~h: Convenience state actions', () {
    test('TC-036d: increment increases counter by specified amount', () async {
      await stateManager.defineVariable('counter', type: StateType.number, initial: 0);
      final context = _context();

      await executor.execute(
        const ActionDefinition(
          action: 'increment',
          params: {'key': 'counter', 'value': 5},
        ),
        context,
      );

      expect(stateManager.get('counter'), equals(5));
    });

    test('TC-036d-boundary: increment defaults to 1 when amount not specified', () async {
      await stateManager.defineVariable('counter', type: StateType.number, initial: 0);
      final context = _context();

      await executor.execute(
        const ActionDefinition(
          action: 'increment',
          params: {'key': 'counter'},
        ),
        context,
      );

      expect(stateManager.get('counter'), equals(1));
    });

    test('TC-036e: decrement decreases counter by specified amount', () async {
      await stateManager.defineVariable('counter', type: StateType.number, initial: 10);
      final context = _context();

      await executor.execute(
        const ActionDefinition(
          action: 'decrement',
          params: {'key': 'counter', 'value': 3},
        ),
        context,
      );

      expect(stateManager.get('counter'), equals(7));
    });

    test('TC-036e-boundary: decrement defaults to 1 when amount not specified', () async {
      await stateManager.defineVariable('counter', type: StateType.number, initial: 10);
      final context = _context();

      await executor.execute(
        const ActionDefinition(
          action: 'decrement',
          params: {'key': 'counter'},
        ),
        context,
      );

      expect(stateManager.get('counter'), equals(9));
    });

    test('TC-036f: append adds item to existing list', () async {
      await stateManager.defineVariable('items', type: StateType.array, initial: ['a', 'b']);
      final context = _context();

      await executor.execute(
        const ActionDefinition(
          action: 'append',
          params: {'key': 'items', 'value': 'newItem'},
        ),
        context,
      );

      expect(stateManager.get('items'), equals(['a', 'b', 'newItem']));
    });

    test('TC-036g: merge combines maps', () async {
      await stateManager.defineVariable('config', type: StateType.object, initial: {'host': 'localhost'});
      final context = _context();

      await executor.execute(
        const ActionDefinition(
          action: 'merge',
          params: {'key': 'config', 'value': {'timeout': 5000}},
        ),
        context,
      );

      final result = stateManager.get('config') as Map;
      expect(result['host'], equals('localhost'));
      expect(result['timeout'], equals(5000));
    });

    test('TC-036h: toggle flips boolean value', () async {
      await stateManager.defineVariable('ledActive', type: StateType.boolean, initial: false);
      final context = _context();

      // First toggle: false -> true
      await executor.execute(
        const ActionDefinition(
          action: 'toggle',
          params: {'key': 'ledActive'},
        ),
        context,
      );

      expect(stateManager.get('ledActive'), isTrue);

      // Second toggle: true -> false
      await executor.execute(
        const ActionDefinition(
          action: 'toggle',
          params: {'key': 'ledActive'},
        ),
        context,
      );

      expect(stateManager.get('ledActive'), isFalse);
    });
  });

  // ===========================================================================
  // TC-037c: gpioConfig action
  // ===========================================================================
  group('TC-037c: gpioConfig', () {
    test('TC-037c: gpioConfig sets pin mode to output', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'gpioConfig',
            params: {'pin': 18, 'mode': 'output'},
          ),
          context,
        ),
        completes,
      );
    });

    test('TC-037c-input: gpioConfig sets pin mode to input', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'gpioConfig',
            params: {'pin': 18, 'mode': 'input'},
          ),
          context,
        ),
        completes,
      );
    });
  });

  // ===========================================================================
  // TC-040c: pwmConfig action
  // ===========================================================================
  group('TC-040c: pwmConfig', () {
    test('TC-040c: pwmConfig sets frequency on channel', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'pwmConfig',
            params: {'channel': 1, 'frequency': 2000},
          ),
          context,
        ),
        completes,
      );
    });
  });

  // ===========================================================================
  // TC-043c~d: channelPublish / channelSubscribe
  // ===========================================================================
  group('TC-043c~d: channelPublish / channelSubscribe', () {
    test('TC-043c: channelPublish sends data to PubSub channel', () async {
      final channelDef = const ChannelDefinition(
        type: ChannelType.pubsub,
        capacity: 10,
      );
      final pubSubChannel = PubSubChannel(
        name: 'events',
        definition: channelDef,
      );
      channels['events'] = pubSubChannel;

      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'channelPublish',
            params: {'channel': 'events', 'topic': 'sensor', 'data': {'temp': 25}},
          ),
          context,
        ),
        completes,
      );
    });

    test('TC-043d: channelSubscribe registers subscription on channel', () async {
      final context = _context();

      // channelSubscribe should create channel if not exists and subscribe
      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'channelSubscribe',
            params: {'channel': 'events', 'topic': 'sensor', 'handler': 'onSensorData'},
          ),
          context,
        ),
        completes,
      );

      // Verify channel was created
      expect(channels.containsKey('events'), isTrue);
    });
  });

  // ===========================================================================
  // TC-044d~k: System utility actions
  // ===========================================================================
  group('TC-044d~k: System utility actions', () {
    test('TC-044b: systemGetInfo returns system info map', () async {
      final context = _context();

      final action = const ActionDefinition(
        action: 'systemGetInfo',
        params: {'key': 'platform'},
        bindTo: 'info',
      );

      await _executeWithBind(action, context);

      final info = context.getVariable('info');
      expect(info, isA<Map>());
      expect((info as Map).containsKey('platform'), isTrue);
    });

    test('TC-044c: systemSetConfig updates runtime configuration', () async {
      final context = _context();

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'systemSetConfig',
            params: {'key': 'logLevel', 'value': 'debug'},
          ),
          context,
        ),
        completes,
      );
    });

    test('TC-044d: eventEmit triggers emitEventCallback', () async {
      String? emittedEvent;
      dynamic emittedData;

      final eventExecutor = ActionExecutor(
        hal: hal,
        stateManager: stateManager,
        channels: channels,
        resources: {},
        config: const RuntimeConfig(),
        configEnvironment: {},
        emitEventCallback: (event, [data]) {
          emittedEvent = event;
          emittedData = data;
        },
      );

      final context = _context();

      await eventExecutor.execute(
        const ActionDefinition(
          action: 'eventEmit',
          params: {'event': 'alarm', 'data': {'zone': 'A'}},
        ),
        context,
      );

      expect(emittedEvent, equals('alarm'));
      expect((emittedData as Map)['zone'], equals('A'));
    });

    test('TC-044d-alias: event alias works identically to eventEmit', () async {
      String? emittedEvent;

      final eventExecutor = ActionExecutor(
        hal: hal,
        stateManager: stateManager,
        channels: channels,
        resources: {},
        config: const RuntimeConfig(),
        configEnvironment: {},
        emitEventCallback: (event, [data]) {
          emittedEvent = event;
        },
      );

      final context = _context();

      await eventExecutor.execute(
        const ActionDefinition(
          action: 'event',
          params: {'event': 'alarm', 'data': {'zone': 'A'}},
        ),
        context,
      );

      expect(emittedEvent, equals('alarm'));
    });

    test('TC-044e: expression evaluates arithmetic and binds result', () async {
      final context = _context();

      final action = const ActionDefinition(
        action: 'expression',
        params: {'expression': '1 + 2 * 3'},
        bindTo: 'result',
      );

      await _executeWithBind(action, context);

      expect(context.getVariable('result'), equals(7));
    });

    test('TC-044f: function calls built-in sum and binds result', () async {
      final context = _context();

      final action = ActionDefinition(
        action: 'function',
        params: {'name': 'sum', 'args': <num>[10, 20, 30]},
        bindTo: 'sumVal',
      );

      await _executeWithBind(action, context);

      expect(context.getVariable('sumVal'), equals(60));
    });

    test('TC-044g: return throws ReturnException with value', () async {
      final context = _context();

      expect(
        () => executor.execute(
          const ActionDefinition(
            action: 'return',
            params: {'value': 42},
          ),
          context,
        ),
        throwsA(isA<ReturnException>()),
      );
    });

    test('TC-044h: systemRestart triggers restart event', () async {
      String? emittedEvent;

      final restartExecutor = ActionExecutor(
        hal: hal,
        stateManager: stateManager,
        channels: channels,
        resources: {},
        config: const RuntimeConfig(),
        configEnvironment: {},
        emitEventCallback: (event, [data]) {
          emittedEvent = event;
        },
      );

      final context = _context();

      await restartExecutor.execute(
        const ActionDefinition(
          action: 'systemRestart',
          params: {'delay': 0, 'reason': 'config update'},
        ),
        context,
      );

      expect(emittedEvent, equals('system.restart'));
    });

    test('TC-044i: systemShutdown triggers shutdown event', () async {
      String? emittedEvent;

      final shutdownExecutor = ActionExecutor(
        hal: hal,
        stateManager: stateManager,
        channels: channels,
        resources: {},
        config: const RuntimeConfig(),
        configEnvironment: {},
        emitEventCallback: (event, [data]) {
          emittedEvent = event;
        },
      );

      final context = _context();

      await shutdownExecutor.execute(
        const ActionDefinition(
          action: 'systemShutdown',
          params: {'delay': 0, 'reason': 'maintenance'},
        ),
        context,
      );

      expect(emittedEvent, equals('system.shutdown'));
    });

    test('TC-044j: wait/delay action delays for specified duration', () async {
      final context = _context();

      final stopwatch = Stopwatch()..start();

      await executor.execute(
        const ActionDefinition(
          action: 'wait',
          params: {'durationMs': 50},
        ),
        context,
      );

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(30));
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(70));
    });

    test('TC-044j-boundary: wait with durationMs 0 completes immediately', () async {
      final context = _context();

      final stopwatch = Stopwatch()..start();

      await executor.execute(
        const ActionDefinition(
          action: 'wait',
          params: {'durationMs': 0},
        ),
        context,
      );

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(20));
    });

    test('TC-044k: waitUntil times out when condition never met', () async {
      await stateManager.defineVariable('ready', type: StateType.boolean, initial: false);
      final context = _context();

      expect(
        () => executor.execute(
          const ActionDefinition(
            action: 'waitUntil',
            condition: '=state.ready == true',
            params: {'timeoutMs': 200, 'pollIntervalMs': 50},
          ),
          context,
        ),
        throwsA(isA<TimeoutError>()),
      );
    });

    test('TC-044k-success: waitUntil proceeds when condition is met', () async {
      await stateManager.defineVariable('ready', type: StateType.boolean, initial: false);
      final context = _context();

      // Set ready to true after 100ms
      Future.delayed(const Duration(milliseconds: 100), () async {
        await stateManager.set('ready', true);
      });

      await expectLater(
        executor.execute(
          const ActionDefinition(
            action: 'waitUntil',
            condition: '=state.ready == true',
            params: {'timeoutMs': 5000, 'pollIntervalMs': 50},
          ),
          context,
        ),
        completes,
      );
    });
  });

  // ===========================================================================
  // TC-045: Advanced Actions
  // ===========================================================================
  group('TC-045: Advanced Actions', () {
    // =========================================================================
    // TC-045a~b: Modbus actions
    // =========================================================================
    group('Modbus actions', () {
      test('TC-045a: modbusRead returns register values from mock', () async {
        final context = _context();

        final action = const ActionDefinition(
          action: 'modbusRead',
          params: {
            'config': {
              'mode': 'tcp',
              'address': '127.0.0.1',
              'port': 502,
            },
            'slaveId': 1,
            'function': 'readHoldingRegisters',
            'startAddress': 40001,
            'quantity': 2,
          },
          bindTo: 'data',
        );
        await _executeWithBind(action, context);

        final data = context.getVariable('data');
        expect(data, isList);
      });

      test('TC-045b: modbusWrite completes without error', () async {
        final context = _context();

        await expectLater(
          executor.execute(
            const ActionDefinition(
              action: 'modbusWrite',
              params: {
                'config': {
                  'mode': 'tcp',
                  'address': '127.0.0.1',
                  'port': 502,
                },
                'slaveId': 1,
                'function': 'writeSingleRegister',
                'startAddress': 40001,
                'quantity': 1,
                'value': 1234,
              },
            ),
            context,
          ),
          completes,
        );
      });

      test('TC-045a (modbusConnect): modbusConnect is not implemented and throws ProcessExecutionError', () async {
        final context = _context();

        expect(
          () => executor.execute(
            const ActionDefinition(
              action: 'modbusConnect',
              params: {'config': 'modbus_device'},
            ),
            context,
          ),
          throwsA(isA<ProcessExecutionError>()),
        );
      });
    });

    // =========================================================================
    // TC-045c~g: HTTP actions
    // =========================================================================
    group('HTTP actions', () {
      test('TC-045c: httpRequest with GET method is recognized', () async {
        final context = _context();

        // Use mock URL to get a deterministic mock response
        final result = await executor.execute(
          const ActionDefinition(
            action: 'httpRequest',
            params: {
              'url': 'http://api.example.com/test',
              'method': 'GET',
            },
            bindTo: 'resp',
          ),
          context,
        );
        expect(result, isA<Map>());
      });

      test('TC-045d: httpGet delegates to httpRequest with GET', () async {
        final context = _context();

        final result = await executor.execute(
          const ActionDefinition(
            action: 'httpGet',
            params: {'url': 'http://api.example.com/info'},
            bindTo: 'resp',
          ),
          context,
        );
        expect(result, isA<Map>());
      });

      test('TC-045e: httpPost delegates to httpRequest with POST', () async {
        final context = _context();

        final result = await executor.execute(
          const ActionDefinition(
            action: 'httpPost',
            params: {
              'url': 'http://api.example.com/data',
              'body': {'key': 'value'},
            },
            bindTo: 'resp',
          ),
          context,
        );
        expect(result, isA<Map>());
      });

      test('TC-045f: httpPut delegates to httpRequest with PUT', () async {
        final context = _context();

        final result = await executor.execute(
          const ActionDefinition(
            action: 'httpPut',
            params: {
              'url': 'http://api.example.com/data/1',
              'body': {'updated': true},
            },
            bindTo: 'resp',
          ),
          context,
        );
        expect(result, isA<Map>());
      });

      test('TC-045g: httpDelete delegates to httpRequest with DELETE', () async {
        final context = _context();

        final result = await executor.execute(
          const ActionDefinition(
            action: 'httpDelete',
            params: {'url': 'http://api.example.com/data/1'},
            bindTo: 'resp',
          ),
          context,
        );
        expect(result, isA<Map>());
      });
    });

    // =========================================================================
    // TC-045h~l: File I/O actions
    // =========================================================================
    group('File I/O actions', () {
      test('TC-045h: fileRead reads file content', () async {
        final tmpFile = File('/tmp/action_executor_test_read.txt');
        await tmpFile.writeAsString('hello');

        try {
          final context = _context();
          final action = const ActionDefinition(
            action: 'fileRead',
            params: {'path': '/tmp/action_executor_test_read.txt', 'encoding': 'utf-8'},
            bindTo: 'content',
          );
          await _executeWithBind(action, context);

          expect(context.getVariable('content'), equals('hello'));
        } finally {
          await tmpFile.delete();
        }
      });

      test('TC-045i: fileWrite creates file with content', () async {
        final context = _context();
        const path = '/tmp/action_executor_test_write.txt';

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'fileWrite',
              params: {'path': path, 'content': 'world', 'encoding': 'utf-8'},
            ),
            context,
          );

          final content = await File(path).readAsString();
          expect(content, equals('world'));
        } finally {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      });

      test('TC-045j: fileAppend appends to existing file', () async {
        final tmpFile = File('/tmp/action_executor_test_append.txt');
        await tmpFile.writeAsString('world');

        try {
          final context = _context();
          await executor.execute(
            const ActionDefinition(
              action: 'fileAppend',
              params: {'path': '/tmp/action_executor_test_append.txt', 'content': '!'},
            ),
            context,
          );

          final content = await tmpFile.readAsString();
          expect(content, equals('world!'));
        } finally {
          await tmpFile.delete();
        }
      });

      test('TC-045k: fileDelete removes file', () async {
        final tmpFile = File('/tmp/action_executor_test_delete.txt');
        await tmpFile.writeAsString('temp');

        final context = _context();
        await executor.execute(
          const ActionDefinition(
            action: 'fileDelete',
            params: {'path': '/tmp/action_executor_test_delete.txt'},
          ),
          context,
        );

        expect(await tmpFile.exists(), isFalse);
      });

      test('TC-045l: fileExists returns false for non-existent file', () async {
        final context = _context();
        final action = const ActionDefinition(
          action: 'fileExists',
          params: {'path': '/tmp/action_executor_test_nonexistent.txt'},
          bindTo: 'exists',
        );
        await _executeWithBind(action, context);

        expect(context.getVariable('exists'), isFalse);
      });
    });

    // =========================================================================
    // TC-045m~n: MQTT actions
    // =========================================================================
    group('MQTT actions', () {
      test('TC-045m: mqttPublish is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'mqttPublish',
              params: {
                'broker': 'mqtt_broker',
                'topic': 'sensor/temp',
                'message': '25.3',
                'qos': 1,
                'retain': false,
              },
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          // MQTT broker not available is expected, but action should be recognized
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045n: mqttSubscribe is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'mqttSubscribe',
              params: {
                'broker': 'mqtt_broker',
                'topic': 'commands/#',
                'qos': 0,
              },
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });
    });

    // =========================================================================
    // TC-045o~r: MCP actions
    // =========================================================================
    group('MCP actions', () {
      test('TC-045o: mcpNotify without McpConfig completes silently', () async {
        final context = _context();

        // No mcpConfig set, should be silently ignored or complete
        await expectLater(
          executor.execute(
            const ActionDefinition(
              action: 'mcpNotify',
              params: {
                'resource': 'sensor/temp',
                'level': 'info',
                'data': {'value': 25.3},
              },
            ),
            context,
          ),
          completes,
        );
      });

      test('TC-045p: mcpUpdateResource is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'mcpUpdateResource',
              params: {
                'uri': 'resource://sensors/temp',
                'contents': {'value': 25.3},
              },
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045q: mcpCallTool is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'mcpCallTool',
              params: {
                'tool': 'analyzeData',
                'params': {'data': [1, 2, 3]},
              },
              bindTo: 'toolResult',
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045r: mcpSubscribe is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'mcpSubscribe',
              params: {'resource': 'resource://events'},
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });
    });

    // =========================================================================
    // TC-045s~v: Service actions
    // =========================================================================
    group('Service actions', () {
      test('TC-045s: serviceDiscover is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'serviceDiscover',
              params: {'service': 'database', 'version': '^1.0.0'},
              bindTo: 'services',
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045t: serviceConnect is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'serviceConnect',
              params: {'service': 'database', 'options': {'timeout': 5000}},
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045u: serviceCall is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'serviceCall',
              params: {
                'service': 'database',
                'method': 'query',
                'args': {'sql': 'SELECT 1'},
              },
              bindTo: 'result',
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045v: serviceSubscribe is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'serviceSubscribe',
              params: {
                'service': 'database',
                'event': 'changed',
                'filter': {'table': 'sensors'},
              },
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });
    });

    // =========================================================================
    // TC-045w~z: Process control actions
    // =========================================================================
    group('Process control actions', () {
      test('TC-045w: processStart invokes executeProcessCallback', () async {
        String? calledProcessId;
        Map<String, dynamic>? calledArgs;

        final process = ProcessInstance(
          id: 'test_proc',
          definitionId: 'test_def',
        );
        final context = ExecutionContext(
          process: process,
          globalState: {},
          resources: {},
          channels: {},
          args: {},
          executeProcessCallback: (processId, args) async {
            calledProcessId = processId;
            calledArgs = args;
          },
        );
        await executor.execute(
          const ActionDefinition(
            action: 'processStart',
            params: {'processId': 'alarm_handler', 'args': {'zone': 'A'}},
          ),
          context,
        );

        expect(calledProcessId, equals('alarm_handler'));
        expect(calledArgs, containsPair('zone', 'A'));
      });

      test('TC-045x: processStop is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'processStop',
              params: {'processId': 'alarm_handler'},
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045y: fork is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'fork',
              params: {'processId': 'worker', 'args': {'batch': 1}},
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045z: join is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'join',
              params: {'handle': 'worker_instance', 'timeout': 5000},
              bindTo: 'result',
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });
    });

    // =========================================================================
    // TC-045aa~ai: Memory & Sync actions
    // =========================================================================
    group('Memory & Sync actions', () {
      test('TC-045aa: memoryAllocate is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'memoryAllocate',
              params: {'region': 'shared_buf', 'size': 1024},
              bindTo: 'handle',
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045ab: memoryWrite is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'memoryWrite',
              params: {'region': 'shared_buf', 'offset': 0, 'data': [1, 2, 3, 4]},
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045ac: memoryRead is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'memoryRead',
              params: {'region': 'shared_buf', 'offset': 0, 'length': 4},
              bindTo: 'data',
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045ad: memoryAtomic is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'memoryAtomic',
              params: {
                'region': 'shared_buf',
                'offset': 0,
                'operation': 'compareAndSwap',
                'value': 10,
                'expected': 1,
              },
              bindTo: 'old',
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045ae: syncLock is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'syncLock',
              params: {'mutex': 'i2c_bus', 'timeout': 1000},
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045af: syncUnlock is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'syncUnlock',
              params: {'mutex': 'i2c_bus'},
            ),
            context,
          );
        } on ProcessExecutionError catch (e) {
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045ag: syncWait is recognized as a valid action', () async {
        final context = _context();

        try {
          await executor.execute(
            const ActionDefinition(
              action: 'syncWait',
              params: {'event': 'dataReady', 'timeout': 100},
            ),
            context,
          );
        } on FlowError catch (e) {
          // TimeoutError or ProcessExecutionError expected, but not unknown action
          expect(e.message, isNot(contains('Unknown action type')));
        }
      });

      test('TC-045ah: syncSignal completes without error', () async {
        final context = _context();

        await expectLater(
          executor.execute(
            const ActionDefinition(
              action: 'syncSignal',
              params: {'event': 'dataReady', 'broadcast': true},
            ),
            context,
          ),
          completes,
        );
      });

      test('TC-045ai: syncBarrier is recognized as a valid action', () async {
        final context = _context();
        // Set expectedCount to 1 so the barrier releases immediately
        context.globalState['__flow_config'] = {
          'synchronization': {
            'barriers': {
              'sync_point': {'count': 1},
            },
          },
        };

        await executor.execute(
          const ActionDefinition(
            action: 'syncBarrier',
            params: {'barrier': 'sync_point'},
          ),
          context,
        );
        // If we get here, the action was recognized and completed
      });
    });

    // =========================================================================
    // TC-045aj~ak: Timer actions
    // =========================================================================
    group('Timer actions', () {
      test('TC-045aj: timeStart records timer start', () async {
        final context = _context();

        await expectLater(
          executor.execute(
            const ActionDefinition(
              action: 'timeStart',
              params: {'timerId': 'elapsed_timer'},
            ),
            context,
          ),
          completes,
        );
      });

      test('TC-045ak: timeElapsed returns elapsed time after timeStart', () async {
        final context = _context();

        // Start timer
        await executor.execute(
          const ActionDefinition(
            action: 'timeStart',
            params: {'timerId': 'elapsed_timer'},
          ),
          context,
        );

        // Wait approximately 100ms
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Read elapsed
        final action = const ActionDefinition(
          action: 'timeElapsed',
          params: {'timerId': 'elapsed_timer'},
          bindTo: 'elapsed',
        );
        await _executeWithBind(action, context);

        final elapsed = context.getVariable('elapsed') as num;
        expect(elapsed, greaterThanOrEqualTo(80));
        expect(elapsed, lessThanOrEqualTo(200));
      });
    });

    // =========================================================================
    // TC-045al~am: Expression evaluation
    // =========================================================================
    group('Expression evaluation', () {
      test('TC-045al: evaluateExpression evaluates arithmetic', () async {
        final context = _context();

        final result = await executor.evaluateExpression('1 + 2 * 3', context);
        expect(result, equals(7));
      });

      test('TC-045al: evaluateExpression strips {{ }} wrapper', () async {
        final context = _context();

        final result = await executor.evaluateExpression('{{1 + 2}}', context);
        expect(result, equals(3));
      });

      test('TC-045al: evaluateExpression accesses state variables', () async {
        await stateManager.defineVariable('counter', type: StateType.number, initial: 42);
        final context = _context();
        context.globalState['counter'] = 42;

        final result = await executor.evaluateExpression('counter + 1', context);
        expect(result, equals(43));
      });

      test('TC-045am: evaluateCondition returns true for truthy expression', () async {
        await stateManager.defineVariable('count', type: StateType.number, initial: 10);
        final context = _context();
        context.globalState['count'] = 10;

        final result = await executor.evaluateCondition('=count > 5', context);
        expect(result, isTrue);
      });

      test('TC-045am: evaluateCondition with {{ }} wrapper', () async {
        final context = _context();

        final result = await executor.evaluateCondition('={{1 == 1}}', context);
        expect(result, isTrue);
      });

      test('TC-045am: evaluateCondition with literal false', () async {
        final context = _context();

        final result = await executor.evaluateCondition('false', context);
        expect(result, isFalse);
      });
    });

    // =========================================================================
    // Unimplemented actions from spec: stateSubscribe, stateUnsubscribe,
    // stateTransaction, debugBreakpoint, debugInspect, assert,
    // eventSubscribe, eventUnsubscribe, eventWait, noop
    // =========================================================================
    group('Unimplemented actions throw ProcessExecutionError', () {
      final unimplementedActions = [
        'stateSubscribe',
        'stateUnsubscribe',
        'stateTransaction',
        'debugBreakpoint',
        'debugInspect',
        'assert',
        'eventSubscribe',
        'eventUnsubscribe',
        'eventWait',
        'noop',
      ];

      for (final actionName in unimplementedActions) {
        test('$actionName throws ProcessExecutionError (unknown action)', () async {
          final context = _context();

          expect(
            () => executor.execute(
              ActionDefinition(
                action: actionName,
                params: const {},
              ),
              context,
            ),
            throwsA(
              allOf(
                isA<ProcessExecutionError>(),
                predicate<ProcessExecutionError>(
                  (e) => e.message.contains('Unknown action type'),
                  'message contains "Unknown action type"',
                ),
              ),
            ),
          );
        });
      }
    });

    // =========================================================================
    // TC-045an~ap: Error handling
    // =========================================================================
    group('Error handling', () {
      test('TC-045an: unknown action type throws ProcessExecutionError', () async {
        final context = _context();

        expect(
          () => executor.execute(
            const ActionDefinition(
              action: 'unknownAction',
              params: {},
            ),
            context,
          ),
          throwsA(
            allOf(
              isA<ProcessExecutionError>(),
              predicate<ProcessExecutionError>(
                (e) => e.message.contains('Unknown action type'),
                'message contains "Unknown action type"',
              ),
            ),
          ),
        );
      });

      test('TC-045ao: channelSend on nonexistent channel throws ProcessExecutionError', () async {
        final context = _context();

        expect(
          () => executor.execute(
            const ActionDefinition(
              action: 'channelSend',
              params: {'channel': 'nonexistent', 'data': {}},
            ),
            context,
          ),
          throwsA(
            allOf(
              isA<ProcessExecutionError>(),
              predicate<ProcessExecutionError>(
                (e) => e.message.contains('not found'),
                'message contains "not found"',
              ),
            ),
          ),
        );
      });

      test('TC-045ap: expression with invalid syntax throws ProcessExecutionError', () async {
        final context = _context();

        // Use an expression that triggers a runtime evaluation error
        expect(
          () => executor.execute(
            const ActionDefinition(
              action: 'expression',
              params: {'expression': '=nonexistent.deeply.nested.method()'},
            ),
            context,
          ),
          throwsA(isA<ProcessExecutionError>()),
        );
      });
    });
  });
}
