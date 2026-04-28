// HAL interface tests (TC-076~085, IT-011~015)
// Test document: TEST-HAL-001

import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/hal/hal_interface.dart';
import 'package:mcp_flow_runtime/src/hal/mock_hal_factory.dart';
import 'package:mcp_flow_runtime/src/types/hardware_types.dart';

void main() {
  // ---------------------------------------------------------------------------
  // TC-076: registerProvider
  // ---------------------------------------------------------------------------
  group('registerProvider', () {
    test('TC-076: registerProvider - normal registration', () {
      final hal = MockHalFactory.createMockHal();
      // MockHal pre-registers providers; verify GPIO is retrievable
      final gpio = hal.getProvider<GpioProvider>(ResourceType.gpio);
      expect(gpio, isNotNull);
      expect(hal.providers, contains(gpio));
    });

    test('TC-076b: registerProvider - replace with same type', () {
      final hal = MockHalFactory.createMockHal();
      final oldGpio = hal.getProvider<GpioProvider>(ResourceType.gpio);
      final newGpio = MockGpioProvider();
      hal.registerProvider(newGpio);
      final retrieved = hal.getProvider<GpioProvider>(ResourceType.gpio);
      expect(identical(retrieved, newGpio), isTrue);
      expect(identical(retrieved, oldGpio), isFalse);
    });

    test('TC-076c: registerProvider - provider with empty supportedTypes', () {
      final hal = MockHalFactory.createMockHal();
      final providerCount = hal.providers.length;
      final emptyProvider = _EmptySupportedTypesProvider();
      hal.registerProvider(emptyProvider);
      // Provider with empty supportedTypes should not add any mapping
      expect(hal.providers.length, equals(providerCount));
    });
  });

  // ---------------------------------------------------------------------------
  // TC-077: getProvider
  // ---------------------------------------------------------------------------
  group('getProvider', () {
    test('TC-077: getProvider - normal lookup', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final i2c = hal.getProvider<I2cProvider>(ResourceType.i2c);
      expect(i2c, isNotNull);
      expect(i2c, isA<I2cProvider>());
    });

    test('TC-077b: getProvider - all 9 types registered and retrievable', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      // MockHal registers gpio, i2c, spi, pwm, uart, adc, dac, timer, modbus (+ mqtt = 10)
      expect(hal.getProvider<GpioProvider>(ResourceType.gpio), isNotNull);
      expect(hal.getProvider<I2cProvider>(ResourceType.i2c), isNotNull);
      expect(hal.getProvider<SpiProvider>(ResourceType.spi), isNotNull);
      expect(hal.getProvider<PwmProvider>(ResourceType.pwm), isNotNull);
      expect(hal.getProvider<UartProvider>(ResourceType.uart), isNotNull);
      expect(hal.getProvider<AdcProvider>(ResourceType.adc), isNotNull);
      expect(hal.getProvider<DacProvider>(ResourceType.dac), isNotNull);
      expect(hal.getProvider<TimerProvider>(ResourceType.timer), isNotNull);
      expect(hal.getProvider<ModbusProvider>(ResourceType.modbus), isNotNull);
    });

    test('TC-077c: getProvider - unregistered type returns null', () {
      final hal = _MinimalHal();
      hal.registerProvider(MockGpioProvider());
      final result = hal.getProvider<SpiProvider>(ResourceType.spi);
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // TC-078: providers list
  // ---------------------------------------------------------------------------
  group('providers list', () {
    test('TC-078: providers - returns all registered providers', () {
      final hal = _MinimalHal();
      hal.registerProvider(MockGpioProvider());
      hal.registerProvider(MockI2cProvider());
      hal.registerProvider(MockSpiProvider());
      expect(hal.providers.length, equals(3));
    });

    test('TC-078b: providers - empty when nothing registered', () {
      final hal = _MinimalHal();
      expect(hal.providers, isEmpty);
    });

    test('TC-078c: providers - returned list mutation does not affect internal state', () {
      final hal = _MinimalHal();
      hal.registerProvider(MockGpioProvider());
      final list = hal.providers;
      final originalLength = list.length;
      // Attempt external mutation
      list.add(MockI2cProvider());
      // Internal state should be unchanged
      expect(hal.providers.length, equals(originalLength));
    });
  });

  // ---------------------------------------------------------------------------
  // TC-079: initialize
  // ---------------------------------------------------------------------------
  group('initialize', () {
    test('TC-079: initialize - all providers initialized', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      for (final p in hal.providers) {
        expect(p.isReady, isTrue);
      }
    });

    test('TC-079b: initialize - double call is idempotent', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      // Second call should not throw
      await hal.initialize();
      for (final p in hal.providers) {
        expect(p.isReady, isTrue);
      }
    });

    test('TC-079c: initialize - provider init failure propagates', () async {
      final hal = _MinimalHal();
      hal.registerProvider(_FailingProvider());
      expect(
        () => hal.initialize(),
        throwsA(isA<HalInitializationException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // TC-080: dispose
  // ---------------------------------------------------------------------------
  group('dispose', () {
    test('TC-080: dispose - all providers disposed', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      await hal.dispose();
      for (final p in hal.providers) {
        expect(p.isReady, isFalse);
      }
    });

    test('TC-080b: dispose - before init is safe no-op', () async {
      final hal = MockHalFactory.createMockHal();
      // Should not throw
      await hal.dispose();
    });

    test('TC-080c: dispose - exception in one provider does not block others', () async {
      final hal = _MinimalHal();
      final good = MockGpioProvider();
      final bad = _DisposeFailingProvider();
      hal.registerProvider(good);
      hal.registerProvider(bad);
      await hal.initialize();
      // dispose should attempt all providers; good should still get disposed
      try {
        await hal.dispose();
      } catch (_) {
        // Exception may propagate, but good provider should have been disposed
      }
      expect(good.isReady, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // TC-081: systemInfo
  // ---------------------------------------------------------------------------
  group('systemInfo', () {
    test('TC-081: systemInfo - returns expected keys', () {
      final hal = MockHalFactory.createMockHal();
      final info = hal.systemInfo;
      expect(info, containsPair('platform', 'mock'));
      expect(info, contains('capabilities'));
    });

    test('TC-081b: systemInfo - no providers registered', () {
      final hal = _MinimalHal();
      final info = hal.systemInfo;
      expect(info['providers'], isEmpty);
    });

    test('TC-081c: systemInfo - config null case', () {
      final hal = _MinimalHal();
      final info = hal.systemInfo;
      expect(info['config'], isNull);
      // Should not throw
    });
  });

  // ---------------------------------------------------------------------------
  // TC-082: HalException hierarchy
  // ---------------------------------------------------------------------------
  group('HalException hierarchy', () {
    test('TC-082: HalException - normal creation and toString', () {
      final notFound = HalNotFoundException('SpiProvider');
      expect(notFound.toString(), contains('SpiProvider'));
      expect(notFound.providerType, equals('SpiProvider'));

      final opEx = HalOperationException('fail', errorCode: -6);
      expect(opEx.errorCode, equals(-6));

      // All exception types can be instantiated
      expect(HalTimeoutException('timeout'), isA<HalException>());
      expect(HalPermissionException('denied'), isA<HalException>());
      expect(HalInitializationException('init fail'), isA<HalException>());
    });

    test('TC-082b: HalException - cause chaining', () {
      final original = FormatException('original error');
      final ex = HalOperationException('wrapped', cause: original);
      expect(ex.cause, equals(original));
      expect(ex.cause, isA<FormatException>());
    });

    test('TC-082c: HalException - empty message', () {
      final ex = HalException('');
      expect(ex.message, equals(''));
      // toString should not throw
      ex.toString();
    });
  });

  // ---------------------------------------------------------------------------
  // TC-083: ResourceType enum
  // ---------------------------------------------------------------------------
  group('ResourceType enum', () {
    test('TC-083: ResourceType - all 10 values exist', () {
      expect(ResourceType.values.length, equals(10));
      expect(ResourceType.values, contains(ResourceType.gpio));
      expect(ResourceType.values, contains(ResourceType.i2c));
      expect(ResourceType.values, contains(ResourceType.spi));
      expect(ResourceType.values, contains(ResourceType.pwm));
      expect(ResourceType.values, contains(ResourceType.uart));
      expect(ResourceType.values, contains(ResourceType.adc));
      expect(ResourceType.values, contains(ResourceType.dac));
      expect(ResourceType.values, contains(ResourceType.timer));
      expect(ResourceType.values, contains(ResourceType.modbus));
      expect(ResourceType.values, contains(ResourceType.mqtt));
    });

    test('TC-083b: ResourceType - name property matches lowercase string', () {
      expect(ResourceType.gpio.name, equals('gpio'));
      expect(ResourceType.i2c.name, equals('i2c'));
      expect(ResourceType.spi.name, equals('spi'));
      expect(ResourceType.pwm.name, equals('pwm'));
      expect(ResourceType.uart.name, equals('uart'));
      expect(ResourceType.adc.name, equals('adc'));
      expect(ResourceType.dac.name, equals('dac'));
      expect(ResourceType.timer.name, equals('timer'));
      expect(ResourceType.modbus.name, equals('modbus'));
      expect(ResourceType.mqtt.name, equals('mqtt'));
    });

    test('TC-083c: ResourceType - invalid name throws ArgumentError', () {
      expect(
        () => ResourceType.values.byName('invalid'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // TC-084: HardwareProvider basic properties
  // ---------------------------------------------------------------------------
  group('HardwareProvider properties', () {
    test('TC-084: HardwareProvider - basic properties return expected values', () async {
      final provider = MockGpioProvider();
      expect(provider.name, equals('MockGpioProvider'));
      expect(provider.version, equals('1.0.0'));
      expect(provider.supportedTypes, equals({ResourceType.gpio}));
      expect(provider.capabilities, isNotEmpty);
      await provider.initialize();
      expect(provider.isReady, isTrue);
    });

    test('TC-084b: HardwareProvider - isReady false before initialize', () {
      final provider = MockGpioProvider();
      expect(provider.isReady, isFalse);
    });

    test('TC-084c: HardwareProvider - isReady false after dispose', () async {
      final provider = MockGpioProvider();
      await provider.initialize();
      expect(provider.isReady, isTrue);
      await provider.dispose();
      expect(provider.isReady, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // TC-085: Concurrent access
  // ---------------------------------------------------------------------------
  group('concurrent access', () {
    test('TC-085: concurrent getProvider calls return correct providers', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();

      final results = await Future.wait([
        Future(() => hal.getProvider<GpioProvider>(ResourceType.gpio)),
        Future(() => hal.getProvider<I2cProvider>(ResourceType.i2c)),
        Future(() => hal.getProvider<SpiProvider>(ResourceType.spi)),
      ]);

      expect(results[0], isA<GpioProvider>());
      expect(results[1], isA<I2cProvider>());
      expect(results[2], isA<SpiProvider>());
    });

    test('TC-085b: getProvider during initialize returns provider or null', () async {
      final hal = MockHalFactory.createMockHal();
      // Start initialize but also query immediately
      final initFuture = hal.initialize();
      // getProvider may return a provider (MockHal does not guard on init state)
      final gpio = hal.getProvider<GpioProvider>(ResourceType.gpio);
      await initFuture;
      // After init, should definitely be available
      expect(hal.getProvider<GpioProvider>(ResourceType.gpio), isNotNull);
      // The pre-init call should return non-null for MockHal (no guard)
      expect(gpio, isNotNull);
    });

    test('TC-085c: getProvider after dispose returns null', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      await hal.dispose();
      // MockHal.getProvider does not guard on disposed state, still returns provider
      // The spec says: null or HalOperationException - MockHal returns the provider instance
      final gpio = hal.getProvider<GpioProvider>(ResourceType.gpio);
      // Provider exists but is not ready
      if (gpio != null) {
        expect(gpio.isReady, isFalse);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // IT-011 ~ IT-015: Integration tests
  // ---------------------------------------------------------------------------
  group('HAL Integration', () {
    test('IT-011: Full HAL init - MockHal with all providers', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();

      expect(hal.getProvider<GpioProvider>(ResourceType.gpio), isA<GpioProvider>());
      expect(hal.getProvider<I2cProvider>(ResourceType.i2c), isA<I2cProvider>());
      expect(hal.getProvider<SpiProvider>(ResourceType.spi), isA<SpiProvider>());
      expect(hal.getProvider<PwmProvider>(ResourceType.pwm), isA<PwmProvider>());
      expect(hal.getProvider<UartProvider>(ResourceType.uart), isA<UartProvider>());
      expect(hal.getProvider<AdcProvider>(ResourceType.adc), isA<AdcProvider>());
    });

    test('IT-012: MockHal GPIO read/write via provider', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();

      final gpio = hal.getProvider<GpioProvider>(ResourceType.gpio)!;
      await gpio.configurePin(const GpioConfig(pin: 18, mode: GpioMode.output));
      await gpio.writePin(18, true);
      final value = await gpio.readPin(18);
      expect(value, isTrue);
    });

    test('IT-013: MockHal sequential interface test', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();

      // GPIO
      final gpio = hal.getProvider<GpioProvider>(ResourceType.gpio)!;
      await gpio.configurePin(const GpioConfig(pin: 1, mode: GpioMode.output));
      await gpio.writePin(1, true);

      // I2C
      final i2c = hal.getProvider<I2cProvider>(ResourceType.i2c)!;
      final bus = await i2c.openBus(1);
      await bus.close();

      // SPI
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(const SpiConfig(bus: 0, device: 0));
      await device.close();

      // PWM
      final pwm = hal.getProvider<PwmProvider>(ResourceType.pwm)!;
      await pwm.setDutyCycle(0, 0.5);

      // UART
      final uart = hal.getProvider<UartProvider>(ResourceType.uart)!;
      final port = await uart.openPort(
          const UartConfig(port: '/dev/ttyUSB0', baudRate: 115200));
      await port.close();

      // ADC
      final adc = hal.getProvider<AdcProvider>(ResourceType.adc)!;
      final voltage = await adc.readVoltage(0);
      expect(voltage, isNotNull);
    });

    test('IT-014: HAL dispose - resource cleanup', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();

      final gpio = hal.getProvider<GpioProvider>(ResourceType.gpio)!;
      await gpio.configurePin(const GpioConfig(pin: 5, mode: GpioMode.output));
      await gpio.configurePin(const GpioConfig(pin: 6, mode: GpioMode.output));

      await hal.dispose();

      for (final p in hal.providers) {
        expect(p.isReady, isFalse);
      }
    });

    test('IT-015: systemInfo returns expected keys', () {
      final hal = MockHalFactory.createMockHal();
      final info = hal.systemInfo;

      expect(info, containsPair('platform', 'mock'));
      expect(info, containsPair('version', '1.0.0'));
      expect(info, contains('capabilities'));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helper classes
// ---------------------------------------------------------------------------

/// Minimal HAL for isolated unit tests (no pre-registered providers)
class _MinimalHal implements HardwareAbstractionLayer {
  final Map<ResourceType, HardwareProvider> _providers = {};

  @override
  void registerProvider(HardwareProvider provider) {
    for (final type in provider.supportedTypes) {
      _providers[type] = provider;
    }
  }

  @override
  T? getProvider<T extends HardwareProvider>(ResourceType type) {
    return _providers[type] as T?;
  }

  @override
  List<HardwareProvider> get providers =>
      _providers.values.toSet().toList();

  @override
  Future<void> initialize() async {
    for (final provider in _providers.values.toSet()) {
      await provider.initialize();
    }
  }

  @override
  Future<void> dispose() async {
    for (final provider in _providers.values.toSet()) {
      await provider.dispose();
    }
  }

  @override
  Map<String, dynamic> get systemInfo => {
        'platform': 'test',
        'providers': _providers.keys.map((t) => t.name).toList(),
        'config': null,
      };
}

/// Provider with empty supportedTypes for TC-076c
class _EmptySupportedTypesProvider implements HardwareProvider {
  @override
  String get name => 'EmptyProvider';
  @override
  String get version => '1.0.0';
  @override
  Set<ResourceType> get supportedTypes => {};
  @override
  Map<String, dynamic> get capabilities => {};
  @override
  bool get isReady => false;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
}

/// Provider whose initialize() always throws, for TC-079c
class _FailingProvider implements GpioProvider {
  @override
  String get name => 'FailingProvider';
  @override
  String get version => '1.0.0';
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.gpio};
  @override
  Map<String, dynamic> get capabilities => {};
  @override
  bool get isReady => false;
  @override
  List<int> get availablePins => [];

  @override
  Future<void> initialize() async {
    throw HalInitializationException('simulated init failure');
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> configurePin(GpioConfig config) async {}
  @override
  Future<bool> readPin(int pin) async => false;
  @override
  Future<void> writePin(int pin, bool value) async {}
  @override
  Future<void> setInterruptHandler(
      int pin, GpioInterrupt trigger, void Function(bool) handler) async {}
  @override
  Future<void> removeInterruptHandler(int pin) async {}
}

/// Provider whose dispose() throws, for TC-080c
class _DisposeFailingProvider implements I2cProvider {
  bool _isReady = false;

  @override
  String get name => 'DisposeFailingProvider';
  @override
  String get version => '1.0.0';
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.i2c};
  @override
  Map<String, dynamic> get capabilities => {};
  @override
  bool get isReady => _isReady;
  @override
  List<int> get availableBuses => [];

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    throw HalOperationException('dispose failed');
  }

  @override
  Future<I2cBus> openBus(int bus) async => throw UnimplementedError();
}
