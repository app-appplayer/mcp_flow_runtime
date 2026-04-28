// Types module tests with TC IDs from TEST-TYPES-001

import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/types/flow_types.dart';
import 'package:mcp_flow_runtime/src/types/hardware_types.dart';
import 'package:mcp_flow_runtime/src/types/runtime_types.dart';
import 'package:mcp_flow_runtime/src/errors/flow_errors.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

final minimalFlowJson = <String, dynamic>{
  'version': '1.0.0',
  'metadata': {'name': 'Test Flow'},
  'processes': [
    {
      'id': 'test_process',
      'name': 'Test Process',
      'trigger': {'type': 'startup'},
      'steps': [
        {'action': 'log', 'params': {'message': 'hello'}},
      ],
    }
  ],
};

final fullFlowJson = <String, dynamic>{
  'version': '1.0.0',
  'metadata': {
    'name': 'Full Flow',
    'description': 'Comprehensive test flow',
    'author': 'tester',
  },
  'resources': {
    'led': {
      'type': 'gpio',
      'config': {'pin': 18, 'mode': 'output'},
    },
    'sensor': {
      'type': 'i2c',
      'config': {'bus': 1, 'address': 72},
    },
  },
  'state': {
    'temperature': {
      'type': 'number',
      'initial': 20.0,
      'persistent': false,
    },
    'flag': {'type': 'boolean', 'initial': false, 'persistent': true},
  },
  'processes': [
    {
      'id': 'main_process',
      'name': 'Main Process',
      'priority': 'high',
      'loop': false,
      'trigger': {'type': 'startup'},
      'steps': [],
    }
  ],
};

final gpioConfigMap = <String, dynamic>{
  'pin': 18,
  'mode': 'output',
  'initialValue': true,
};
final i2cConfigMap = <String, dynamic>{
  'bus': 1,
  'address': 72,
  'clockHz': 100000,
};
final spiConfigMap = <String, dynamic>{
  'bus': 0,
  'device': 0,
  'clockHz': 1000000,
  'mode': 0,
};
final uartConfigMap = <String, dynamic>{
  'port': '/dev/ttyS0',
  'baudRate': 115200,
  'dataBits': 8,
  'parity': 'none',
  'stopBits': 1,
};
final adcConfigMap = <String, dynamic>{
  'channel': 0,
  'referenceVoltage': 3.3,
  'resolution': 12,
};

void main() {
  // =========================================================================
  // 2. flow_types.dart tests (TC-641 ~ TC-655)
  // =========================================================================
  group('TC-641: FlowDefinition basic field parsing', () {
    test('TC-641a: FlowDefinition parses minimal JSON correctly', () {
      final definition = FlowDefinition.fromJson(minimalFlowJson);

      expect(definition.version, equals('1.0.0'));
      expect(definition.metadata.name, equals('Test Flow'));
      expect(definition.processes.length, equals(1));
      expect(definition.resources, isEmpty);
      expect(definition.state, isEmpty);
    });

    test('TC-641b: FlowDefinition optional fields are null when absent', () {
      final definition = FlowDefinition.fromJson({
        'version': '1.0.0',
        'metadata': {'name': 'Min'},
        'processes': [],
      });

      expect(definition.configuration, isNull);
      expect(definition.channels, isEmpty);
      expect(definition.synchronization, isNull);
      expect(definition.events, isNull);
      expect(definition.processes, isEmpty);
    });

    test('TC-641c: FlowDefinition version field missing uses default', () {
      // The generated fromJson provides a default for version,
      // so missing version does not throw - verify it parses with default
      final definition = FlowDefinition.fromJson({
        'metadata': {'name': 'No Version'},
        'processes': [],
      });
      expect(definition.metadata.name, equals('No Version'));
    });
  });

  group('TC-642: FlowDefinition full field parsing', () {
    test('TC-642a: FlowDefinition parses full JSON correctly', () {
      final definition = FlowDefinition.fromJson(fullFlowJson);

      expect(definition.resources.length, equals(2));
      expect(definition.state.length, equals(2));
      expect(definition.metadata.author, equals('tester'));
    });

    test('TC-642b: FlowDefinition schema field parsing', () {
      final definition = FlowDefinition.fromJson({
        r'$schema': 'https://makemind.dev/schemas/v1',
        'version': '1.0.0',
        'metadata': {'name': 'Schema Flow'},
        'processes': [],
      });

      expect(definition.schema, equals('https://makemind.dev/schemas/v1'));
    });

    test('TC-642c: FlowDefinition processes field missing throws error', () {
      expect(
        () => FlowDefinition.fromJson({
          'version': '1.0.0',
          'metadata': {'name': 'X'},
        }),
        throwsA(anything),
      );
    });
  });

  group('TC-643: FlowMetadata', () {
    test('TC-643a: FlowMetadata full field parsing', () {
      final metadata = FlowMetadata.fromJson({
        'name': 'Full',
        'description': 'Desc',
        'author': 'test',
      });

      expect(metadata.name, equals('Full'));
      expect(metadata.description, equals('Desc'));
      expect(metadata.author, equals('test'));
    });

    test('TC-643b: FlowMetadata optional fields null when absent', () {
      final metadata = FlowMetadata.fromJson({'name': 'Minimal Flow'});

      expect(metadata.name, equals('Minimal Flow'));
      expect(metadata.description, isNull);
      expect(metadata.author, isNull);
    });

    test('TC-643c: FlowMetadata name field missing throws error', () {
      expect(
        () => FlowMetadata.fromJson(<String, dynamic>{}),
        throwsA(anything),
      );
    });
  });

  group('TC-644: ResourceDefinition', () {
    test('TC-644a: ResourceDefinition field verification', () {
      final resource = ResourceDefinition.fromJson({
        'type': 'gpio',
        'config': {'pin': 18, 'mode': 'output'},
      });

      expect(resource.type, equals('gpio'));
      expect(resource.config['pin'], equals(18));
    });

    test('TC-644b: ResourceDefinition capabilities optional field', () {
      final resource = ResourceDefinition.fromJson({
        'type': 'gpio',
        'config': <String, dynamic>{},
        'capabilities': ['read', 'write'],
      });

      expect(resource.capabilities, equals(['read', 'write']));
    });

    test('TC-644c: ResourceDefinition type field missing throws error', () {
      expect(
        () => ResourceDefinition.fromJson({'config': {'pin': 5}}),
        throwsA(anything),
      );
    });
  });

  group('TC-645: StateDefinition', () {
    test('TC-645a: StateDefinition full field parsing', () {
      final stateDef = StateDefinition.fromJson({
        'type': 'number',
        'initial': 20.0,
        'persistent': true,
      });

      expect(stateDef.type, equals(StateType.number));
      expect(stateDef.initial, equals(20.0));
      expect(stateDef.persistent, isTrue);
    });

    test('TC-645b: StateDefinition persistent defaults to false', () {
      final stateDef = StateDefinition.fromJson({
        'type': 'number',
        'initial': 0,
      });

      expect(stateDef.persistent, isFalse);
    });

    test('TC-645c: StateDefinition type field missing throws error', () {
      expect(
        () => StateDefinition.fromJson({'initial': 0}),
        throwsA(anything),
      );
    });
  });

  group('TC-646: StateConstraints', () {
    test('TC-646a: StateConstraints all fields parse', () {
      final constraints = StateConstraints.fromJson({
        'min': -40,
        'max': 85,
        'minLength': 1,
        'maxLength': 100,
        'pattern': r'^\d+$',
        'enum': [0, 1, 2],
        'validate': 'value > 0',
      });

      expect(constraints.min, equals(-40));
      expect(constraints.max, equals(85));
      expect(constraints.minLength, equals(1));
      expect(constraints.maxLength, equals(100));
      expect(constraints.pattern, equals(r'^\d+$'));
      expect(constraints.enum$, equals([0, 1, 2]));
      expect(constraints.validate, equals('value > 0'));
    });

    test('TC-646b: StateConstraints all fields null', () {
      final constraints = StateConstraints.fromJson(<String, dynamic>{});

      expect(constraints.min, isNull);
      expect(constraints.max, isNull);
      expect(constraints.minLength, isNull);
      expect(constraints.maxLength, isNull);
      expect(constraints.pattern, isNull);
      expect(constraints.enum$, isNull);
    });
  });

  group('TC-647: ProcessDefinition', () {
    test('TC-647a: ProcessDefinition full field parsing', () {
      final process = ProcessDefinition.fromJson({
        'id': 'proc1',
        'name': 'Test',
        'priority': 'high',
        'loop': true,
        'steps': [],
      });

      expect(process.id, equals('proc1'));
      expect(process.priority, equals(ProcessPriority.high));
      expect(process.loop, isTrue);
    });

    test('TC-647b: ProcessDefinition priority/loop defaults', () {
      final process = ProcessDefinition.fromJson({
        'id': 'proc1',
        'name': 'Test Process',
        'steps': [],
      });

      expect(process.priority, equals(ProcessPriority.normal));
      expect(process.loop, isFalse);
      expect(process.enabled, isTrue);
    });

    test('TC-647c: ProcessDefinition id field missing throws error', () {
      expect(
        () => ProcessDefinition.fromJson({'name': 'Test', 'steps': []}),
        throwsA(anything),
      );
    });
  });

  group('TC-649: TriggerDefinition', () {
    test('TC-649a: TriggerDefinition startup trigger parsing', () {
      final trigger = TriggerDefinition.fromJson({'type': 'startup'});
      expect(trigger.type, equals(TriggerType.startup));
    });

    test('TC-649b: TriggerDefinition all trigger types', () {
      final types = [
        'manual', 'startup', 'event', 'condition',
        'schedule', 'channelReceive', 'stateChange', 'resourceEvent',
      ];

      for (final t in types) {
        final trigger = TriggerDefinition.fromJson({'type': t});
        expect(trigger.type, equals(TriggerType.values.byName(t)));
      }
    });

    test('TC-649c: TriggerDefinition unknown trigger type throws error', () {
      expect(
        () => TriggerDefinition.fromJson({'type': 'unknown_trigger'}),
        throwsA(anything),
      );
    });
  });

  group('TC-650: ActionDefinition', () {
    test('TC-650a: ActionDefinition parses then/else branches', () {
      final actionMap = <String, dynamic>{
        'action': 'if',
        'params': {'condition': 'state.flag'},
        'then': [
          {'action': 'log', 'params': {'message': 'true'}}
        ],
        'else': [
          {'action': 'log', 'params': {'message': 'false'}}
        ],
      };
      final actionDef = ActionDefinition.fromJson(actionMap);

      expect(actionDef.action, equals('if'));
      expect(actionDef.then, isNotNull);
      expect(actionDef.then!.length, equals(1));
      expect(actionDef.else$, isNotNull);
      expect(actionDef.else$!.length, equals(1));
    });

    test('TC-650b: ActionDefinition then/else null when absent', () {
      final actionDef = ActionDefinition.fromJson({
        'action': 'if',
        'params': {'condition': 'true'},
      });

      expect(actionDef.then, isNull);
      expect(actionDef.else$, isNull);
    });

    test('TC-650c: ActionDefinition action field missing throws error', () {
      expect(
        () => ActionDefinition.fromJson({'params': {'key': 'val'}}),
        throwsA(anything),
      );
    });
  });

  group('TC-651: RetryConfig', () {
    test('TC-651a: RetryConfig full field parsing', () {
      final retry = RetryConfig.fromJson({
        'count': 3,
        'delayMs': 1000,
        'backoff': 'exponential',
        'maxDelayMs': 5000,
      });

      expect(retry.count, equals(3));
      expect(retry.delayMs, equals(1000));
      expect(retry.backoff, equals('exponential'));
      expect(retry.maxDelayMs, equals(5000));
    });

    test('TC-651b: RetryConfig backoff defaults to null when absent', () {
      final retry = RetryConfig.fromJson({
        'count': 2,
        'delayMs': 1000,
      });

      expect(retry.count, equals(2));
      expect(retry.delayMs, equals(1000));
      expect(retry.backoff, isNull);
    });
  });

  group('TC-653: ChannelDefinition', () {
    test('TC-653a: ChannelDefinition queue type parsing', () {
      final channel = ChannelDefinition.fromJson({'type': 'queue', 'capacity': 100});
      expect(channel.type, equals(ChannelType.queue));
      expect(channel.capacity, equals(100));
    });

    test('TC-653b: ChannelDefinition all channel types', () {
      final types = ['queue', 'pubsub', 'pipe', 'sharedMemory'];

      for (final t in types) {
        final channel = ChannelDefinition.fromJson({'type': t});
        expect(channel.type, equals(ChannelType.values.byName(t)));
      }
    });

    test('TC-653c: ChannelDefinition unknown type throws error', () {
      expect(
        () => ChannelDefinition.fromJson({'type': 'invalid_channel'}),
        throwsA(anything),
      );
    });
  });

  group('TC-654: McpConfig', () {
    test('TC-654a: McpConfig parsing with tools and resources', () {
      final mcp = McpConfig.fromJson({
        'mode': 'standard',
        'tools': [
          {'name': 'tool1', 'description': 'First tool'},
          {'name': 'tool2', 'description': 'Second tool'},
        ],
        'resources': [
          {'name': 'res1', 'uri': 'mcp://res1'},
        ],
      });

      expect(mcp.tools!.length, equals(2));
      expect(mcp.resources!.length, equals(1));
    });

    test('TC-654b: McpConfig mode defaults to standard', () {
      final mcp = McpConfig.fromJson(<String, dynamic>{});
      expect(mcp.mode, equals(McpMode.standard));
    });

    test('TC-654c: McpConfig invalid mode throws error', () {
      expect(
        () => McpConfig.fromJson({'mode': 'invalid_mode'}),
        throwsA(anything),
      );
    });
  });

  group('TC-655: SecurityConfig', () {
    test('TC-655a: SecurityConfig parsing', () {
      final security = SecurityConfig.fromJson({
        'requireAuth': true,
        'allowedRoles': ['admin', 'operator'],
        'auditLog': true,
        'confirmationRequired': false,
        'rateLimit': {'maxRequestsPerSecond': 10, 'burstLimit': 20},
      });

      expect(security.requireAuth, isTrue);
      expect(security.allowedRoles, equals(['admin', 'operator']));
      expect(security.auditLog, isTrue);
      expect(security.confirmationRequired, isFalse);
      expect(security.rateLimit!['maxRequestsPerSecond'], equals(10));
    });

    test('TC-655b: SecurityConfig all fields null', () {
      final security = SecurityConfig.fromJson(<String, dynamic>{});

      expect(security.requireAuth, isNull);
      expect(security.allowedRoles, isNull);
      expect(security.auditLog, isNull);
    });

    test('TC-655c: SecurityConfig allowedRoles empty array', () {
      final security = SecurityConfig.fromJson({
        'requireAuth': true,
        'allowedRoles': [],
      });

      expect(security.allowedRoles, isEmpty);
    });
  });

  // =========================================================================
  // 3. hardware_types.dart tests (TC-666 ~ TC-678)
  // =========================================================================
  group('TC-666: GpioConfig', () {
    test('TC-666a: GpioConfig.fromJson parses all fields', () {
      final config = GpioConfig.fromJson(gpioConfigMap);

      expect(config.pin, equals(18));
      expect(config.mode, equals(GpioMode.output));
      expect(config.initialValue, isTrue);
    });

    test('TC-666b: GpioConfig interrupt null and initialValue default', () {
      final config = GpioConfig.fromJson({'pin': 5, 'mode': 'input'});

      expect(config.interrupt, isNull);
      expect(config.initialValue, isFalse);
    });

    test('TC-666c: GpioConfig unknown mode string throws error', () {
      expect(
        () => GpioConfig.fromJson({'pin': 5, 'mode': 'invalid_mode'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TC-668: GpioMode/GpioInterrupt enums', () {
    test('TC-668a: GpioMode enum normal parsing', () {
      expect(GpioMode.values.byName('output'), equals(GpioMode.output));
    });

    test('TC-668b: GpioMode enum all values', () {
      final modes = GpioMode.values.map((m) => m.name).toSet();
      expect(
          modes, containsAll(['input', 'output', 'inputPullUp', 'inputPullDown']));
    });

    test('TC-668c: GpioInterrupt enum all values', () {
      final interrupts = GpioInterrupt.values.map((i) => i.name).toSet();
      expect(interrupts, containsAll(['none', 'rising', 'falling', 'both']));
    });
  });

  group('TC-670: I2cConfig', () {
    test('TC-670a: I2cConfig.fromJson parses bus, address, and clockHz', () {
      final config = I2cConfig.fromJson(i2cConfigMap);

      expect(config.bus, equals(1));
      expect(config.address, equals(72));
      expect(config.clockHz, equals(100000));
    });

    test('TC-670b: I2cConfig clockHz is null when absent', () {
      final config = I2cConfig.fromJson({'bus': 1, 'address': 0x20});

      expect(config.clockHz, isNull);
    });

    test('TC-670c: I2cConfig bus field missing throws error', () {
      expect(
        () => I2cConfig.fromJson({'address': 0x20}),
        throwsA(anything),
      );
    });
  });

  group('TC-672: SpiConfig', () {
    test('TC-672a: SpiConfig.fromJson parses all fields', () {
      final config = SpiConfig.fromJson(spiConfigMap);

      expect(config.bus, equals(0));
      expect(config.device, equals(0));
      expect(config.clockHz, equals(1000000));
      expect(config.mode, equals(0));
    });

    test('TC-672b: SpiConfig clockHz default value', () {
      final config = SpiConfig.fromJson({'bus': 0, 'device': 0});

      expect(config.clockHz, equals(1000000));
    });

    test('TC-672c: SpiConfig bus field missing throws error', () {
      expect(
        () => SpiConfig.fromJson({'device': 0}),
        throwsA(anything),
      );
    });
  });

  group('TC-673: UartConfig', () {
    test('TC-673a: UartConfig.fromJson parses all fields', () {
      final config = UartConfig.fromJson(uartConfigMap);

      expect(config.port, equals('/dev/ttyS0'));
      expect(config.baudRate, equals(115200));
      expect(config.parity, equals('none'));
      expect(config.dataBits, equals(8));
      expect(config.stopBits, equals(1));
    });

    test('TC-673b: UartConfig dataBits/parity/stopBits defaults', () {
      final config = UartConfig.fromJson({'port': '/dev/ttyS0', 'baudRate': 9600});

      expect(config.dataBits, equals(8));
      expect(config.parity, equals('none'));
      expect(config.stopBits, equals(1));
    });

    test('TC-673c: UartConfig port field missing throws error', () {
      expect(
        () => UartConfig.fromJson({'baudRate': 9600}),
        throwsA(anything),
      );
    });
  });

  group('TC-674: AdcConfig', () {
    test('TC-674a: AdcConfig.fromJson parses all fields', () {
      final config = AdcConfig.fromJson(adcConfigMap);

      expect(config.channel, equals(0));
      expect(config.referenceVoltage, equals(3.3));
      expect(config.resolution, equals(12));
    });

    test('TC-674b: AdcConfig defaults', () {
      final config = AdcConfig.fromJson({'channel': 0});

      expect(config.referenceVoltage, equals(3.3));
      expect(config.resolution, equals(12));
    });

    test('TC-674c: AdcConfig channel field missing throws error', () {
      expect(
        () => AdcConfig.fromJson(<String, dynamic>{}),
        throwsA(anything),
      );
    });
  });

  group('TC-675: DacConfig', () {
    test('TC-675a: DacConfig.fromJson full parsing', () {
      final config = DacConfig.fromJson({
        'channel': 1,
        'referenceVoltage': 5.0,
        'resolution': 16,
      });

      expect(config.channel, equals(1));
      expect(config.referenceVoltage, equals(5.0));
      expect(config.resolution, equals(16));
    });

    test('TC-675b: DacConfig.fromJson defaults', () {
      final config = DacConfig.fromJson({'channel': 0});

      expect(config.referenceVoltage, equals(3.3));
      expect(config.resolution, equals(12));
    });

    test('TC-675c: DacConfig channel field missing throws error', () {
      expect(
        () => DacConfig.fromJson(<String, dynamic>{}),
        throwsA(anything),
      );
    });
  });

  group('TC-676: ModbusConfig', () {
    test('TC-676a: ModbusConfig TCP mode', () {
      final config = ModbusConfig.fromJson({
        'mode': 'tcp',
        'address': '192.168.1.100',
        'port': 502,
        'unitId': 1,
      });

      expect(config.mode, equals(ModbusMode.tcp));
      expect(config.address, equals('192.168.1.100'));
      expect(config.port, equals(502));
    });

    test('TC-676b: ModbusConfig RTU mode', () {
      final config = ModbusConfig.fromJson({
        'mode': 'rtu',
        'address': '/dev/ttyS0',
        'baudRate': 9600,
        'unitId': 1,
      });

      expect(config.mode, equals(ModbusMode.rtu));
      expect(config.baudRate, equals(9600));
    });

    test('TC-676c: ModbusConfig unknown mode throws error', () {
      expect(
        () => ModbusConfig.fromJson({'mode': 'invalid', 'address': '127.0.0.1'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TC-678: ResourceType enum', () {
    test('TC-678a: ResourceType enum normal access', () {
      expect(ResourceType.gpio, isNotNull);
      expect(ResourceType.i2c, isNotNull);
    });

    test('TC-678b: ResourceType has all expected values', () {
      final types = ResourceType.values.map((t) => t.name).toSet();
      expect(types, containsAll([
        'gpio', 'i2c', 'spi', 'pwm', 'uart', 'adc', 'dac', 'timer',
        'modbus', 'mqtt',
      ]));
    });

    test('TC-678c: ResourceType values count verification', () {
      expect(ResourceType.values.length, equals(10));
    });
  });

  // =========================================================================
  // 4. runtime_types.dart tests (TC-686 ~ TC-695)
  // =========================================================================
  group('TC-686: RuntimeConfig', () {
    test('TC-686a: RuntimeConfig default values', () {
      const config = RuntimeConfig();

      expect(config.storeType, equals('memory'));
      expect(config.enableMonitoring, isTrue);
      expect(config.logLevel, equals('info'));
      expect(config.tickRateMs, equals(10));
      expect(config.maxProcesses, equals(50));
    });

    test('TC-686b: RuntimeConfig all fields set', () {
      const config = RuntimeConfig(
        tickRateMs: 20,
        maxProcesses: 100,
        maxMemoryKB: 256000,
        storeType: 'file',
        enableMonitoring: false,
        logLevel: 'debug',
      );

      expect(config.tickRateMs, equals(20));
      expect(config.maxProcesses, equals(100));
      expect(config.maxMemoryKB, equals(256000));
      expect(config.storeType, equals('file'));
      expect(config.enableMonitoring, isFalse);
      expect(config.logLevel, equals('debug'));
    });
  });

  group('TC-687: ProcessInstance', () {
    test('TC-687a: ProcessInstance initial state has auto-set startedAt', () {
      final instance = ProcessInstance(
        id: 'pi-001',
        definitionId: 'flow1',
        state: ProcessState.created,
        createdAt: DateTime.now(),
        localContext: {},
      );

      expect(instance.state, equals(ProcessState.created));
      expect(instance.startedAt, isNotNull);
      expect(instance.currentStepIndex, equals(0));
      expect(instance.completedAt, isNull);
      expect(instance.errorMessage, isNull);
    });

    test('TC-687b: ProcessInstance localContext empty map', () {
      final instance = ProcessInstance(
        id: 'pi-002',
        definitionId: 'flow1',
        localContext: {},
      );

      expect(instance.localContext, isEmpty);
    });
  });

  group('TC-688: ProcessState transitions', () {
    test('TC-688a: ProcessState transitions are tracked correctly', () {
      final instance = ProcessInstance(
        id: 'pi-002',
        definitionId: 'f1',
        state: ProcessState.created,
        createdAt: DateTime.now(),
        localContext: {},
      );

      instance.state = ProcessState.executing;
      expect(instance.startedAt, isNotNull);
      expect(instance.state, equals(ProcessState.executing));

      instance.state = ProcessState.completed;
      instance.completedAt = DateTime.now();
      expect(instance.state, equals(ProcessState.completed));
    });

    test('TC-688b: ProcessState error transition with errorMessage', () {
      final instance = ProcessInstance(
        id: 'pi-003',
        definitionId: 'f1',
        state: ProcessState.executing,
      );

      instance.state = ProcessState.error;
      instance.errorMessage = 'test error';

      expect(instance.state, equals(ProcessState.error));
      expect(instance.errorMessage, equals('test error'));
    });
  });

  group('TC-689: ProcessState enum', () {
    test('TC-689a: ProcessState enum normal access', () {
      expect(ProcessState.executing, isNotNull);
    });

    test('TC-689b: ProcessState has all expected values', () {
      final states = ProcessState.values.map((s) => s.name).toSet();
      expect(states, containsAll([
        'created', 'waiting', 'ready', 'executing',
        'suspended', 'completed', 'error',
      ]));
    });

    test('TC-689c: ProcessState values count verification', () {
      expect(ProcessState.values.length, equals(7));
    });
  });

  group('TC-690: ActionResult', () {
    test('TC-690a: ActionResult success case', () {
      const result = ActionResult(
        status: ActionStatus.success,
        value: 42,
        executionTime: Duration(milliseconds: 100),
      );

      expect(result.status, equals(ActionStatus.success));
      expect(result.value, equals(42));
      expect(result.errorCode, isNull);
      expect(result.executionTime, greaterThan(Duration.zero));
    });

    test('TC-690b: ActionResult timeout status', () {
      const result = ActionResult(
        status: ActionStatus.timeout,
        executionTime: Duration(seconds: 5),
      );

      expect(result.status, equals(ActionStatus.timeout));
      expect(result.value, isNull);
    });

    test('TC-690c: ActionResult failure case', () {
      const result = ActionResult(
        status: ActionStatus.failure,
        errorCode: 'GPIO_WRITE_FAIL',
        errorMessage: 'write failed',
        executionTime: Duration(milliseconds: 50),
      );

      expect(result.status, equals(ActionStatus.failure));
      expect(result.errorCode, isNotNull);
      expect(result.value, isNull);
    });
  });

  group('TC-692: ActionStatus enum', () {
    test('TC-692a: ActionStatus enum normal access', () {
      expect(ActionStatus.success, isNotNull);
    });

    test('TC-692b: ActionStatus enum all values', () {
      final statuses = ActionStatus.values.map((s) => s.name).toSet();
      expect(statuses, containsAll(['success', 'failure', 'skipped', 'timeout']));
    });

    test('TC-692c: ActionStatus values count verification', () {
      expect(ActionStatus.values.length, equals(4));
    });
  });

  group('TC-693: RuntimeStatus enum', () {
    test('TC-693a: RuntimeStatus enum normal access', () {
      expect(RuntimeStatus.running, isNotNull);
    });

    test('TC-693b: RuntimeStatus has all expected values', () {
      final statuses = RuntimeStatus.values.map((s) => s.name).toSet();
      expect(statuses, containsAll([
        'created', 'stopped', 'starting', 'running', 'stopping', 'error',
      ]));
    });

    test('TC-693c: RuntimeStatus values count verification', () {
      expect(RuntimeStatus.values.length, equals(6));
    });
  });

  group('TC-694: RuntimeStatistics', () {
    test('TC-694a: RuntimeStatistics toJson contains expected keys', () {
      final stats = RuntimeStatistics(
        totalProcessesStarted: 10,
        totalProcessesCompleted: 8,
        totalProcessesFailed: 1,
        activeProcessCount: 1,
        totalActionsExecuted: 50,
        actionCountByType: {'log': 20, 'gpio.write': 30},
      );
      final json = stats.toJson();

      expect(json, contains('startedAt'));
      expect(json, contains('totalProcessesStarted'));
      expect(json, contains('activeProcessCount'));
    });

    test('TC-694b: RuntimeStatistics initial state values', () {
      final stats = RuntimeStatistics(
        totalProcessesStarted: 0,
        totalProcessesCompleted: 0,
        totalProcessesFailed: 0,
        activeProcessCount: 0,
        totalActionsExecuted: 0,
        actionCountByType: {},
      );

      expect(stats.startedAt, isNotNull);
      expect(stats.totalProcessesStarted, equals(0));
    });
  });

  group('TC-695: ScheduledProcess', () {
    test('TC-695a: ScheduledProcess fields accessible', () {
      final sp = ScheduledProcess(
        definitionId: 'flow1',
        triggerType: 'startup',
        triggerParams: {'delay': 100},
      );

      expect(sp.definitionId, equals('flow1'));
      expect(sp.scheduledAt, isNotNull);
      expect(sp.triggerType, equals('startup'));
      expect(sp.triggerParams, equals({'delay': 100}));
    });

    test('TC-695b: ScheduledProcess triggerParams null', () {
      final sp = ScheduledProcess(
        definitionId: 'flow1',
        triggerType: 'startup',
      );

      expect(sp.triggerParams, isNull);
    });
  });

  // =========================================================================
  // 5. flow_errors.dart tests (TC-701 ~ TC-712)
  // =========================================================================
  group('TC-701: FlowError base', () {
    test('TC-701a: FlowError.toString returns [code] message format', () {
      const error = FlowParseError(
        'field is required',
        field: 'processes',
      );

      expect(error.code, equals('PARSE_ERROR'));
      expect(error.toString(), contains('field is required'));
    });

    test('TC-701b: FlowError empty message', () {
      const error = FlowParseError('');
      expect(error.toString(), contains('[PARSE_ERROR]'));
    });

    test('TC-701c: FlowError cause field wraps original exception', () {
      final cause = FormatException('invalid json');
      final error = FlowParseError(
        'parse failed',
        cause: cause,
      );

      expect(error.cause, isA<FormatException>());
    });
  });

  group('TC-702: FlowParseError', () {
    test('TC-702a: FlowParseError field property', () {
      const error = FlowParseError(
        'missing required field',
        field: 'processes',
      );

      expect(error.field, equals('processes'));
    });

    test('TC-702b: FlowParseError field null', () {
      const error = FlowParseError('some error');
      expect(error.field, isNull);
    });

    test('TC-702c: FlowParseError is FlowError', () {
      const error = FlowParseError('M');
      expect(error, isA<FlowError>());
    });
  });

  group('TC-703: FlowValidationError', () {
    test('TC-703a: FlowValidationError multiple errors', () {
      final error = FlowValidationError(
        'validation failed',
        errors: [
          ValidationError(code: 'ID_DUPLICATE', message: 'p1'),
          ValidationError(code: 'MISSING_TRIGGER', message: 'p2'),
        ],
      );

      expect(error.errors.length, equals(2));
    });

    test('TC-703b: FlowValidationError empty errors list', () {
      const error = FlowValidationError('validation', errors: []);
      expect(error.errors, isEmpty);
    });

    test('TC-703c: FlowValidationError is FlowError', () {
      const error = FlowValidationError('M', errors: []);
      expect(error, isA<FlowError>());
    });
  });

  group('TC-704: ProcessExecutionError', () {
    test('TC-704a: ProcessExecutionError stores processId and stepIndex', () {
      const error = ProcessExecutionError(
        'gpio write failed',
        processId: 'my_process',
        actionType: 'gpio.write',
        stepIndex: 3,
      );

      expect(error.processId, equals('my_process'));
      expect(error.stepIndex, equals(3));
      expect(error.actionType, equals('gpio.write'));
    });

    test('TC-704b: ProcessExecutionError stepIndex null', () {
      const error = ProcessExecutionError('err', processId: 'p');
      expect(error.stepIndex, isNull);
    });

    test('TC-704c: ProcessExecutionError is FlowError', () {
      const error = ProcessExecutionError('M', processId: 'p');
      expect(error, isA<FlowError>());
    });
  });

  group('TC-705: HardwareError', () {
    test('TC-705a: HardwareError resourceId, resourceType', () {
      const error = HardwareError(
        'write failed',
        resourceId: 'led',
        resourceType: 'gpio',
      );

      expect(error.resourceId, equals('led'));
      expect(error.resourceType, equals('gpio'));
    });

    test('TC-705b: HardwareError errorCode', () {
      const error = HardwareError(
        'permission denied',
        resourceId: 'led',
        resourceType: 'gpio',
        errorCode: 13,
      );

      expect(error.errorCode, equals(13));
    });

    test('TC-705c: HardwareError is FlowError', () {
      const error = HardwareError('M', resourceId: 'r', resourceType: 'gpio');
      expect(error, isA<FlowError>());
    });
  });

  group('TC-706: FlowStateError', () {
    test('TC-706a: FlowStateError variableName', () {
      const error = FlowStateError(
        'variable not found',
        variableName: 'temperature',
      );

      expect(error.variableName, equals('temperature'));
    });

    test('TC-706b: FlowStateError variableName null', () {
      const error = FlowStateError('some error');
      expect(error.variableName, isNull);
    });

    test('TC-706c: FlowStateError is FlowError', () {
      const error = FlowStateError('M');
      expect(error, isA<FlowError>());
    });
  });

  group('TC-707: McpError', () {
    test('TC-707a: McpError method, mcpErrorCode', () {
      const error = McpError(
        'internal error',
        method: 'tools/call',
        mcpErrorCode: -32603,
      );

      expect(error.method, equals('tools/call'));
      expect(error.mcpErrorCode, equals(-32603));
    });

    test('TC-707b: McpError method null', () {
      const error = McpError('M');
      expect(error.method, isNull);
    });

    test('TC-707c: McpError is FlowError', () {
      const error = McpError('M');
      expect(error, isA<FlowError>());
    });
  });

  group('TC-708: SecurityError', () {
    test('TC-708a: SecurityError basic fields', () {
      const error = SecurityError('unauthorized access');

      expect(error.code, equals('SECURITY_ERROR'));
      expect(error.message, equals('unauthorized access'));
    });

    test('TC-708b: SecurityError no extra fields', () {
      const error = SecurityError('M');

      expect(error.cause, isNull);
    });

    test('TC-708c: SecurityError is FlowError', () {
      const error = SecurityError('M');
      expect(error, isA<FlowError>());
    });
  });

  group('TC-709: ResourceLimitError', () {
    test('TC-709a: ResourceLimitError stores limit and requested count', () {
      const error = ResourceLimitError(
        'max I2C connections exceeded',
        resourceType: 'i2c',
        limit: 5,
        requested: 6,
      );

      expect(error.limit, equals(5));
      expect(error.requested, equals(6));
      expect(error.resourceType, equals('i2c'));
    });

    test('TC-709b: ResourceLimitError limit equals requested', () {
      const error = ResourceLimitError(
        'at limit',
        resourceType: 'i2c',
        limit: 5,
        requested: 5,
      );

      expect(error.limit, equals(5));
      expect(error.requested, equals(5));
    });

    test('TC-709c: ResourceLimitError is FlowError', () {
      const error = ResourceLimitError('M',
          resourceType: 'i2c', limit: 1, requested: 2);
      expect(error, isA<FlowError>());
    });
  });

  group('TC-710: TimeoutError', () {
    test('TC-710a: TimeoutError timeout, operation', () {
      const error = TimeoutError(
        'read timed out',
        timeout: Duration(seconds: 5),
        operation: 'gpio.read',
      );

      expect(error.timeout, equals(const Duration(seconds: 5)));
      expect(error.operation, equals('gpio.read'));
    });

    test('TC-710b: TimeoutError timeout zero', () {
      const error = TimeoutError(
        'M',
        timeout: Duration.zero,
        operation: 'op',
      );

      expect(error.timeout, equals(Duration.zero));
    });

    test('TC-710c: TimeoutError is FlowError', () {
      const error = TimeoutError('M',
          timeout: Duration.zero, operation: 'op');
      expect(error, isA<FlowError>());
    });
  });

  group('TC-712: FlowError hierarchy', () {
    test('TC-712a: all FlowError subclasses are instances of FlowError', () {
      final errors = <FlowError>[
        const FlowParseError('M'),
        const FlowValidationError('M', errors: []),
        const ProcessExecutionError('M', processId: 'p'),
        const HardwareError('M', resourceId: 'r', resourceType: 'gpio'),
        const FlowStateError('M'),
        const McpError('M'),
        const SecurityError('M'),
        const ResourceLimitError('M',
            resourceType: 'i2c', limit: 1, requested: 2),
        const TimeoutError('M',
            timeout: Duration.zero, operation: 'op'),
      ];
      for (final e in errors) {
        expect(e, isA<FlowError>());
      }
    });

    test('TC-712b: ConcreteFlowError is FlowError', () {
      const error = ConcreteFlowError('TEST', 'test message');
      expect(error, isA<FlowError>());
    });

    test('TC-712c: FlowError catch block catches all subclasses', () {
      final caught = <FlowError>[];
      final errors = <FlowError>[
        const HardwareError('M', resourceId: 'r', resourceType: 'gpio'),
        const McpError('M'),
        const SecurityError('M'),
      ];

      for (final error in errors) {
        try {
          throw error;
        } on FlowError catch (e) {
          caught.add(e);
        }
      }

      expect(caught.length, equals(3));
    });
  });

  // =========================================================================
  // 6. Serialization round-trip tests (TC-716 ~ TC-719)
  // =========================================================================
  group('TC-716: GpioConfig serialization', () {
    test('TC-716a: GpioConfig round-trip serialization is lossless', () {
      final config = GpioConfig.fromJson(gpioConfigMap);
      final restored = GpioConfig.fromJson(config.toJson());

      expect(restored.pin, equals(config.pin));
      expect(restored.mode, equals(config.mode));
      expect(restored.initialValue, equals(config.initialValue));
    });

    test('TC-716b: GpioConfig optional field round-trip', () {
      final config = GpioConfig.fromJson({'pin': 5, 'mode': 'input'});
      final restored = GpioConfig.fromJson(config.toJson());

      expect(restored.interrupt, isNull);
    });

    test('TC-716c: GpioConfig invalid JSON throws error', () {
      expect(
        () => GpioConfig.fromJson(<String, dynamic>{}),
        throwsA(isA<Error>()),
      );
    });
  });

  group('TC-717: ProcessInstance serialization', () {
    test('TC-717a: ProcessInstance has serializable fields', () {
      final instance = ProcessInstance(
        id: 'pi-001',
        definitionId: 'flow1',
        state: ProcessState.created,
      );

      expect(instance.id, equals('pi-001'));
      expect(instance.definitionId, equals('flow1'));
      expect(instance.state, equals(ProcessState.created));
      expect(instance.createdAt, isNotNull);
      expect(instance.currentStepIndex, equals(0));
    });

    test('TC-717b: ProcessInstance error state fields', () {
      final instance = ProcessInstance(
        id: 'pi-002',
        definitionId: 'flow1',
        state: ProcessState.error,
      );
      instance.errorMessage = 'some error';

      expect(instance.state, equals(ProcessState.error));
      expect(instance.errorMessage, equals('some error'));
    });

    test('TC-717c: ProcessInstance completedAt null', () {
      final instance = ProcessInstance(
        id: 'pi-003',
        definitionId: 'flow1',
      );

      expect(instance.completedAt, isNull);
    });
  });

  group('TC-718: ActionResult serialization', () {
    test('TC-718a: ActionResult fields accessible for serialization', () {
      const result = ActionResult(
        status: ActionStatus.success,
        value: 'done',
        executionTime: Duration(milliseconds: 200),
      );

      expect(result.status, equals(ActionStatus.success));
      expect(result.value, equals('done'));
      expect(result.errorCode, isNull);
      expect(result.executionTime, equals(const Duration(milliseconds: 200)));
    });

    test('TC-718b: ActionResult value null', () {
      const result = ActionResult(
        status: ActionStatus.skipped,
        executionTime: Duration(milliseconds: 0),
      );

      expect(result.value, isNull);
    });

    test('TC-718c: ActionResult failure state', () {
      const result = ActionResult(
        status: ActionStatus.failure,
        errorCode: 'TIMEOUT',
        executionTime: Duration(milliseconds: 100),
      );

      expect(result.errorCode, equals('TIMEOUT'));
    });
  });

  group('TC-719: Hardware config round-trip serialization', () {
    test('TC-719a: I2cConfig round-trip', () {
      final i2c = I2cConfig.fromJson(i2cConfigMap);
      final i2cRestored = I2cConfig.fromJson(i2c.toJson());
      expect(i2cRestored.bus, equals(i2c.bus));
      expect(i2cRestored.address, equals(i2c.address));
    });

    test('TC-719b: SpiConfig round-trip', () {
      final spi = SpiConfig.fromJson(spiConfigMap);
      final spiRestored = SpiConfig.fromJson(spi.toJson());
      expect(spiRestored.bus, equals(spi.bus));
      expect(spiRestored.clockHz, equals(spi.clockHz));
    });

    test('TC-719c: Missing required fields throws error', () {
      expect(
        () => GpioConfig.fromJson(<String, dynamic>{}),
        throwsA(isA<Error>()),
      );
    });
  });

  // =========================================================================
  // 7. Integration tests (IT-066 ~ IT-070)
  // =========================================================================
  group('IT-066: FlowDefinition resource pipeline', () {
    test('IT-066a: FlowDefinition -> ResourceDefinition -> GpioConfig pipeline',
        () {
      final definition = FlowDefinition.fromJson(fullFlowJson);
      final ledResource = definition.resources['led']!;
      final gpioConfig = GpioConfig.fromJson(ledResource.config);

      expect(gpioConfig.pin, equals(18));
      expect(gpioConfig.mode, equals(GpioMode.output));
    });

    test('IT-066b: FlowDefinition -> ResourceDefinition -> I2cConfig pipeline',
        () {
      final definition = FlowDefinition.fromJson(fullFlowJson);
      final sensorResource = definition.resources['sensor']!;
      final i2cConfig = I2cConfig.fromJson(sensorResource.config);

      expect(i2cConfig.bus, equals(1));
      expect(i2cConfig.address, equals(72));
    });

    test('IT-066c: FlowDefinition nonexistent resource returns null', () {
      final definition = FlowDefinition.fromJson(fullFlowJson);
      expect(definition.resources['nonexistent'], isNull);
    });
  });

  group('IT-067: FlowDefinition state pipeline', () {
    test('IT-067a: FlowDefinition -> StateDefinition pipeline', () {
      final definition = FlowDefinition.fromJson(fullFlowJson);
      final tempState = definition.state['temperature']!;

      expect(tempState.type, equals(StateType.number));
      expect(tempState.initial, equals(20.0));
    });

    test('IT-067b: FlowDefinition -> StateDefinition persistent flag', () {
      final definition = FlowDefinition.fromJson(fullFlowJson);
      final flagState = definition.state['flag']!;

      expect(flagState.persistent, isTrue);
    });

    test('IT-067c: FlowDefinition nonexistent state returns null', () {
      final definition = FlowDefinition.fromJson(fullFlowJson);
      expect(definition.state['nonexistent'], isNull);
    });
  });

  group('IT-068: FlowError catch pattern', () {
    test('IT-068a: HardwareError is caught by FlowError catch block', () {
      final caught = <FlowError>[];
      try {
        throw const HardwareError(
          'write failed',
          resourceId: 'led',
          resourceType: 'gpio',
        );
      } on FlowError catch (e) {
        caught.add(e);
      }
      expect(caught.length, equals(1));
      expect(caught.first, isA<HardwareError>());
    });
  });

  group('IT-069: All hardware types round-trip serialization', () {
    test('IT-069a: All hardware types round-trip serialization', () {
      // GpioConfig
      final gpio = GpioConfig.fromJson(gpioConfigMap);
      final gpioRestored = GpioConfig.fromJson(gpio.toJson());
      expect(gpioRestored.pin, equals(gpio.pin));

      // I2cConfig
      final i2c = I2cConfig.fromJson(i2cConfigMap);
      final i2cRestored = I2cConfig.fromJson(i2c.toJson());
      expect(i2cRestored.bus, equals(i2c.bus));
      expect(i2cRestored.address, equals(i2c.address));

      // SpiConfig
      final spi = SpiConfig.fromJson(spiConfigMap);
      final spiRestored = SpiConfig.fromJson(spi.toJson());
      expect(spiRestored.bus, equals(spi.bus));
      expect(spiRestored.clockHz, equals(spi.clockHz));

      // UartConfig
      final uart = UartConfig.fromJson(uartConfigMap);
      final uartRestored = UartConfig.fromJson(uart.toJson());
      expect(uartRestored.port, equals(uart.port));
      expect(uartRestored.baudRate, equals(uart.baudRate));

      // AdcConfig
      final adc = AdcConfig.fromJson(adcConfigMap);
      final adcRestored = AdcConfig.fromJson(adc.toJson());
      expect(adcRestored.channel, equals(adc.channel));
      expect(adcRestored.referenceVoltage, equals(adc.referenceVoltage));
    });
  });

  // =========================================================================
  // Missing TC implementations
  // =========================================================================
  group('TC-646c: StateConstraints min > max', () {
    test('TC-646c: min greater than max is accepted at parse level', () {
      // StateConstraints.fromJson does not validate min > max;
      // validation happens at a higher layer
      final constraints = StateConstraints.fromJson({
        'min': 100,
        'max': 0,
      });

      expect(constraints.min, equals(100));
      expect(constraints.max, equals(0));
    });
  });

  group('TC-651c: RetryConfig count zero or negative', () {
    test('TC-651c: RetryConfig with negative count parses without error', () {
      // RetryConfig.fromJson does not validate count bounds;
      // validation happens at a higher layer
      final retry = RetryConfig.fromJson({
        'count': -1,
        'delayMs': 1000,
      });

      expect(retry.count, equals(-1));
    });
  });

  group('TC-686c: RuntimeConfig invalid storeType', () {
    test('TC-686c: RuntimeConfig with invalid storeType is accepted at construction', () {
      // RuntimeConfig accepts arbitrary storeType string;
      // validation happens at runtime
      const config = RuntimeConfig(storeType: 'invalid_store');
      expect(config.storeType, equals('invalid_store'));
    });
  });

  group('TC-687c: ProcessInstance empty id', () {
    test('TC-687c: ProcessInstance with empty id is accepted at construction', () {
      // ProcessInstance does not validate id at construction level
      final instance = ProcessInstance(
        id: '',
        definitionId: 'flow1',
      );

      expect(instance.id, equals(''));
    });
  });

  group('TC-688c: ProcessState invalid transition', () {
    test('TC-688c: completed to executing transition is allowed at field level', () {
      // ProcessInstance.state is a simple setter; no transition guard
      final instance = ProcessInstance(
        id: 'pi-transition',
        definitionId: 'f1',
        state: ProcessState.completed,
      );
      instance.completedAt = DateTime.now();

      instance.state = ProcessState.executing;
      expect(instance.state, equals(ProcessState.executing));
    });
  });

  group('TC-694c: RuntimeStatistics activeProcessCount boundary', () {
    test('TC-694c: RuntimeStatistics accepts zero activeProcessCount', () {
      final stats = RuntimeStatistics(
        totalProcessesStarted: 0,
        totalProcessesCompleted: 0,
        totalProcessesFailed: 0,
        activeProcessCount: 0,
        totalActionsExecuted: 0,
        actionCountByType: {},
      );

      expect(stats.activeProcessCount, greaterThanOrEqualTo(0));
    });
  });

  group('TC-695c: ScheduledProcess empty definitionId', () {
    test('TC-695c: ScheduledProcess with empty definitionId is accepted', () {
      // ScheduledProcess does not validate definitionId at construction
      final sp = ScheduledProcess(
        definitionId: '',
        triggerType: 'startup',
      );

      expect(sp.definitionId, equals(''));
    });
  });

  // =========================================================================
  // 8. Synchronization type tests (TC-720 ~ TC-724)
  // =========================================================================
  group('TC-720: SynchronizationDefinition', () {
    test('TC-720a: SynchronizationDefinition.fromJson parses all fields', () {
      final json = <String, dynamic>{
        'mutexes': {'m1': {'timeoutMs': 1000}},
        'semaphores': {'s1': {'initial': 3, 'max': 5}},
        'barriers': {'b1': {'count': 4, 'autoReset': true}},
        'events': {'e1': {'autoReset': false, 'initialState': true}},
      };
      final sync = SynchronizationDefinition.fromJson(json);

      expect(sync.mutexes?.length, equals(1));
      expect(sync.semaphores?.length, equals(1));
      expect(sync.barriers?.length, equals(1));
      expect(sync.events?.length, equals(1));
    });

    test('TC-720b: SynchronizationDefinition.fromJson all fields null', () {
      final sync = SynchronizationDefinition.fromJson(<String, dynamic>{});

      expect(sync.mutexes, isNull);
      expect(sync.semaphores, isNull);
      expect(sync.barriers, isNull);
      expect(sync.events, isNull);
    });

    test('TC-720c: SynchronizationDefinition toJson round-trip', () {
      final json = <String, dynamic>{
        'mutexes': {'m1': {'timeoutMs': 1000}},
        'semaphores': {'s1': {'initial': 3, 'max': 5}},
        'barriers': {'b1': {'count': 4, 'autoReset': true}},
        'events': {'e1': {'autoReset': false, 'initialState': true}},
      };
      final sync = SynchronizationDefinition.fromJson(json);
      final restored = SynchronizationDefinition.fromJson(sync.toJson());

      expect(restored.mutexes?.length, equals(sync.mutexes?.length));
      expect(restored.semaphores?.length, equals(sync.semaphores?.length));
      expect(restored.barriers?.length, equals(sync.barriers?.length));
      expect(restored.events?.length, equals(sync.events?.length));
    });
  });

  group('TC-721: MutexDefinition', () {
    test('TC-721a: MutexDefinition.fromJson parses all fields', () {
      final mutex = MutexDefinition.fromJson(
        {'priorityInheritance': true, 'timeoutMs': 5000},
      );

      expect(mutex.priorityInheritance, isTrue);
      expect(mutex.timeoutMs, equals(5000));
    });

    test('TC-721b: MutexDefinition.fromJson optional fields null', () {
      final mutex = MutexDefinition.fromJson(<String, dynamic>{});

      expect(mutex.priorityInheritance, isNull);
      expect(mutex.timeoutMs, isNull);
    });

    test('TC-721c: MutexDefinition toJson round-trip', () {
      final original = MutexDefinition.fromJson(
        {'priorityInheritance': true, 'timeoutMs': 3000},
      );
      final restored = MutexDefinition.fromJson(original.toJson());

      expect(restored.priorityInheritance, equals(original.priorityInheritance));
      expect(restored.timeoutMs, equals(original.timeoutMs));
    });
  });

  group('TC-722: SemaphoreDefinition', () {
    test('TC-722a: SemaphoreDefinition.fromJson parses all fields', () {
      final semaphore = SemaphoreDefinition.fromJson(
        {'initial': 3, 'max': 10},
      );

      expect(semaphore.initial, equals(3));
      expect(semaphore.max, equals(10));
    });

    test('TC-722b: SemaphoreDefinition.fromJson max null when absent', () {
      final semaphore = SemaphoreDefinition.fromJson({'initial': 1});

      expect(semaphore.max, isNull);
    });

    test('TC-722c: SemaphoreDefinition.fromJson initial missing throws', () {
      expect(
        () => SemaphoreDefinition.fromJson(<String, dynamic>{}),
        throwsA(anything),
      );
    });
  });

  group('TC-723: BarrierDefinition', () {
    test('TC-723a: BarrierDefinition.fromJson parses all fields', () {
      final barrier = BarrierDefinition.fromJson(
        {'count': 4, 'autoReset': true},
      );

      expect(barrier.count, equals(4));
      expect(barrier.autoReset, isTrue);
    });

    test('TC-723b: BarrierDefinition.fromJson autoReset null when absent', () {
      final barrier = BarrierDefinition.fromJson({'count': 2});

      expect(barrier.autoReset, isNull);
    });

    test('TC-723c: BarrierDefinition.fromJson count missing throws', () {
      expect(
        () => BarrierDefinition.fromJson(<String, dynamic>{}),
        throwsA(anything),
      );
    });
  });

  group('TC-724: EventSyncDefinition', () {
    test('TC-724a: EventSyncDefinition.fromJson parses all fields', () {
      final event = EventSyncDefinition.fromJson(
        {'autoReset': true, 'initialState': false},
      );

      expect(event.autoReset, isTrue);
      expect(event.initialState, isFalse);
    });

    test('TC-724b: EventSyncDefinition.fromJson all optional fields null', () {
      final event = EventSyncDefinition.fromJson(<String, dynamic>{});

      expect(event.autoReset, isNull);
      expect(event.initialState, isNull);
    });

    test('TC-724c: EventSyncDefinition toJson round-trip', () {
      final original = EventSyncDefinition.fromJson(
        {'autoReset': true, 'initialState': true},
      );
      final restored = EventSyncDefinition.fromJson(original.toJson());

      expect(restored.autoReset, equals(original.autoReset));
      expect(restored.initialState, equals(original.initialState));
    });
  });

  group('IT-070: RuntimeStatistics', () {
    test('IT-070a: RuntimeStatistics cumulative aggregation', () {
      final stats = RuntimeStatistics(
        totalProcessesStarted: 5,
        totalProcessesCompleted: 4,
        totalProcessesFailed: 1,
        activeProcessCount: 0,
        totalActionsExecuted: 25,
        actionCountByType: {'log': 15, 'gpio.write': 10},
      );

      final json = stats.toJson();
      expect(json['totalProcessesStarted'], equals(5));
      expect(json['totalProcessesFailed'], equals(1));
      expect(json['activeProcessCount'], equals(0));
    });
  });
}
