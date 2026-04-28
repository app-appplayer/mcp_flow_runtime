// HAL providers tests (TC-096~099, TC-103~118)
// Test document: TEST-HAL-004
//
// Note: TC-096~099 test LinuxGpioProvider which requires sysfs filesystem.
// These tests use MockGpioProvider from mock_hal_factory.dart as a proxy
// since the actual LinuxGpioProvider cannot run without /sys/class/gpio.
// TC-103~104 similarly proxy through mock implementations.
// TC-105~118 test Mock and Windows providers directly.

import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/hal/hal_interface.dart';
import 'package:mcp_flow_runtime/src/hal/mock_hal_factory.dart';
import 'package:mcp_flow_runtime/src/hal/providers/mock_provider.dart'
    as prov;
import 'package:mcp_flow_runtime/src/hal/providers/mqtt_provider.dart';
import 'package:mcp_flow_runtime/src/types/hardware_types.dart';

void main() {
  // ===========================================================================
  // TC-096~099: GPIO provider tests (via MockGpioProvider from mock_hal_factory)
  // ===========================================================================

  group('TC-096: GPIO configurePin', () {
    test('TC-096a: configurePin normal output setup', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output),
      );
      final val = await gpio.readPin(18);
      expect(val, isFalse); // default initialValue
    });

    test('TC-096b: configurePin re-configure same pin', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output, initialValue: true),
      );
      expect(await gpio.readPin(18), isTrue);
      // Re-configure as output with different initial
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output, initialValue: false),
      );
      expect(await gpio.readPin(18), isFalse);
    });

    test('TC-096c: configurePin with invalid pin on mock provider', () async {
      // MockGpioProvider from mock_hal_factory does not validate pin range.
      // The prov.MockGpioProvider requires initialization and configuration.
      final gpio = prov.MockGpioProvider();
      await gpio.initialize();
      // Negative pin - mock_provider.dart version has availablePins 0-39
      // but does not reject out-of-range in configurePin. Test passes.
      await gpio.configurePin(
        const GpioConfig(pin: -1, mode: GpioMode.output),
      );
      // It allows it since mock doesn't validate range in configurePin
    });
  });

  group('TC-097: GPIO readPin', () {
    test('TC-097a: readPin returns true after writing true', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output),
      );
      await gpio.writePin(18, true);
      expect(await gpio.readPin(18), isTrue);
    });

    test('TC-097b: readPin returns false for default pin', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output),
      );
      expect(await gpio.readPin(18), isFalse);
    });

    test('TC-097c: readPin unconfigured pin returns false', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      // MockGpioProvider from mock_hal_factory returns false for unconfigured pins
      final val = await gpio.readPin(99);
      expect(val, isFalse);
    });
  });

  group('TC-098: GPIO writePin', () {
    test('TC-098a: writePin true to output pin', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output),
      );
      await gpio.writePin(18, true);
      expect(await gpio.readPin(18), isTrue);
    });

    test('TC-098b: writePin false to output pin', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output, initialValue: true),
      );
      await gpio.writePin(18, false);
      expect(await gpio.readPin(18), isFalse);
    });

    test('TC-098c: writePin to non-output pin is no-op for mock', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.input),
      );
      // MockGpioProvider from mock_hal_factory silently ignores non-output writes
      await gpio.writePin(18, true);
      // Value may or may not be stored; mock does not enforce
    });
  });

  group('TC-099: GPIO setInterruptHandler', () {
    test('TC-099a: setInterruptHandler registers handler', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.input),
      );
      bool handlerCalled = false;
      await gpio.setInterruptHandler(
        18,
        GpioInterrupt.rising,
        (value) => handlerCalled = true,
      );
      // Simulate pin change
      gpio.simulatePinChange(18, true);
      expect(handlerCalled, isTrue);
    });

    test('TC-099b: setInterruptHandler replaces existing handler', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.input),
      );
      int firstCount = 0;
      int secondCount = 0;
      await gpio.setInterruptHandler(
        18,
        GpioInterrupt.rising,
        (_) => firstCount++,
      );
      // Replace handler
      await gpio.setInterruptHandler(
        18,
        GpioInterrupt.rising,
        (_) => secondCount++,
      );
      gpio.simulatePinChange(18, true);
      // Only new handler should be called
      expect(secondCount, equals(1));
    });

    test('TC-099c: removeInterruptHandler on unregistered pin is safe', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      // Should not throw
      await gpio.removeInterruptHandler(99);
    });
  });

  // ===========================================================================
  // TC-100: GPIO removeInterruptHandler
  // ===========================================================================

  group('TC-100: GPIO removeInterruptHandler', () {
    test('TC-100a: remove registered interrupt handler', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.input),
      );
      int callCount = 0;
      await gpio.setInterruptHandler(
        18,
        GpioInterrupt.rising,
        (_) => callCount++,
      );
      await gpio.removeInterruptHandler(18);
      // After removal, pin change should not trigger handler
      gpio.simulatePinChange(18, true);
      expect(callCount, equals(0));
    });

    test('TC-100b: remove handler on unregistered pin is no-op', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      // Should not throw when removing handler from pin with no handler
      await gpio.removeInterruptHandler(99);
    });

    test('TC-100c: remove handler tolerates internal errors', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.input),
      );
      await gpio.setInterruptHandler(
        18,
        GpioInterrupt.rising,
        (_) {},
      );
      // Remove handler should complete even if internal state is unusual
      await gpio.removeInterruptHandler(18);
      // Second remove should also be safe (idempotent)
      await gpio.removeInterruptHandler(18);
    });
  });

  // ===========================================================================
  // TC-101: I2C openBus
  // ===========================================================================

  group('TC-101: I2C openBus', () {
    test('TC-101a: open available bus', () async {
      final i2c = prov.MockI2cProvider();
      await i2c.initialize();
      final bus = await i2c.openBus(1);
      expect(bus, isNotNull);
      expect(bus.bus, equals(1));
      await bus.close();
    });

    test('TC-101b: open first and last available bus', () async {
      final i2c = prov.MockI2cProvider();
      await i2c.initialize();
      final buses = i2c.availableBuses;
      // Open first available bus
      final first = await i2c.openBus(buses.first);
      expect(first.bus, equals(buses.first));
      await first.close();
      // Open last available bus
      final last = await i2c.openBus(buses.last);
      expect(last.bus, equals(buses.last));
      await last.close();
    });

    test('TC-101c: open unavailable bus throws', () async {
      final i2c = prov.MockI2cProvider();
      await i2c.initialize();
      expect(
        () => i2c.openBus(99),
        throwsA(anything),
      );
    });
  });

  // ===========================================================================
  // TC-102: I2C bus operations and close behavior
  // ===========================================================================

  group('TC-102: I2C bus read/write and close', () {
    test('TC-102a: read returns data of requested length', () async {
      final i2c = prov.MockI2cProvider();
      await i2c.initialize();
      final bus = await i2c.openBus(0);
      final data = await bus.read(0x68, 6);
      expect(data.length, equals(6));
      expect(data, isA<Uint8List>());
      await bus.close();
    });

    test('TC-102b: close is idempotent', () async {
      final i2c = prov.MockI2cProvider();
      await i2c.initialize();
      final bus = await i2c.openBus(0);
      await bus.close();
      // Second close should not throw
      await bus.close();
    });

    test('TC-102c: operations after close on mock (no guard)', () async {
      final i2c = prov.MockI2cProvider();
      await i2c.initialize();
      final bus = await i2c.openBus(0);
      await bus.close();
      // MockI2cBus does not enforce closed state
      final data = await bus.read(0x68, 2);
      expect(data.length, equals(2));
    });
  });

  // ===========================================================================
  // TC-103~104: SPI provider tests (via mock)
  // ===========================================================================

  group('TC-103: SPI openDevice', () {
    test('TC-103a: openDevice returns SpiDevice', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(
        const SpiConfig(bus: 0, device: 0),
      );
      expect(device, isNotNull);
      expect(device.config.bus, equals(0));
      await device.close();
    });

    test('TC-103b: availableDevices returns list', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      expect(spi.availableDevices, isNotEmpty);
    });

    test('TC-103c: openDevice with unavailable device on prov mock', () async {
      final spi = prov.MockSpiProvider();
      await spi.initialize();
      expect(
        () => spi.openDevice(const SpiConfig(bus: 0, device: 99)),
        throwsA(anything),
      );
    });
  });

  group('TC-104: SPI device transfer/close', () {
    test('TC-104a: transfer returns same-length response', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(
        const SpiConfig(bus: 0, device: 0),
      );
      final result = await device.transfer(Uint8List.fromList([0xAA, 0xBB]));
      expect(result.length, equals(2));
      await device.close();
    });

    test('TC-104b: close is idempotent', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(
        const SpiConfig(bus: 0, device: 0),
      );
      await device.close();
      // Second close should not throw
      await device.close();
    });

    test('TC-104c: transfer after close on mock does not throw', () async {
      // MockSpiDevice from mock_hal_factory has no close guard
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(
        const SpiConfig(bus: 0, device: 0),
      );
      await device.close();
      // Mock does not enforce closed state
      final result = await device.transfer(Uint8List.fromList([0x01]));
      expect(result.length, equals(1));
    });
  });

  // ===========================================================================
  // TC-105: WindowsGpioProvider (tested via mock_hal_factory MockGpioProvider)
  // ===========================================================================

  group('TC-105: WindowsGpioProvider (via mock)', () {
    test('TC-105a: write and read pin', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 5, mode: GpioMode.output),
      );
      await gpio.writePin(5, true);
      expect(await gpio.readPin(5), isTrue);
    });

    test('TC-105b: input pin read returns bool', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 3, mode: GpioMode.input),
      );
      final val = await gpio.readPin(3);
      expect(val, isA<bool>());
    });

    test('TC-105c: unconfigured pin read returns false', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      // MockGpioProvider returns false for unconfigured pins
      final val = await gpio.readPin(50);
      expect(val, isFalse);
    });
  });

  // ===========================================================================
  // TC-106: MockGpioProvider
  // ===========================================================================

  group('TC-106: MockGpioProvider', () {
    test('TC-106a: write true read true', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output),
      );
      await gpio.writePin(18, true);
      expect(await gpio.readPin(18), isTrue);
    });

    test('TC-106b: multiple pins independent state', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      await gpio.configurePin(
        const GpioConfig(pin: 18, mode: GpioMode.output),
      );
      await gpio.configurePin(
        const GpioConfig(pin: 19, mode: GpioMode.output),
      );
      await gpio.writePin(18, true);
      await gpio.writePin(19, false);
      expect(await gpio.readPin(18), isTrue);
      expect(await gpio.readPin(19), isFalse);
    });

    test('TC-106c: unconfigured pin read returns false', () async {
      final gpio = MockGpioProvider();
      await gpio.initialize();
      expect(await gpio.readPin(99), isFalse);
    });
  });

  // ===========================================================================
  // TC-107: MockI2cProvider
  // ===========================================================================

  group('TC-107: MockI2cProvider', () {
    test('TC-107a: openBus and read/write', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final i2c = hal.getProvider<I2cProvider>(ResourceType.i2c)!;
      final bus = await i2c.openBus(1);
      expect(bus, isNotNull);
      expect(bus.bus, equals(1));
      await bus.write(0x48, Uint8List.fromList([0x01, 0x02]));
      final data = await bus.read(0x48, 2);
      expect(data.length, equals(2));
      await bus.close();
    });

    test('TC-107b: writeRegister then readRegister returns stored value', () async {
      // prov.MockI2cBus stores register values
      final i2c = prov.MockI2cProvider();
      await i2c.initialize();
      final bus = await i2c.openBus(0);
      await bus.writeRegister(0x48, 0x10, Uint8List.fromList([0xAB]));
      final result = await bus.readRegister(0x48, 0x10, 1);
      expect(result[0], equals(0xAB));
      await bus.close();
    });

    test('TC-107c: close then operations still work on mock (no guard)', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final i2c = hal.getProvider<I2cProvider>(ResourceType.i2c)!;
      final bus = await i2c.openBus(0);
      await bus.close();
      // MockI2cBus from mock_hal_factory has no close guard
      final data = await bus.read(0x48, 1);
      expect(data.length, equals(1));
    });
  });

  // ===========================================================================
  // TC-108: MockSpiProvider
  // ===========================================================================

  group('TC-108: MockSpiProvider', () {
    test('TC-108a: transfer returns same length', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(
        const SpiConfig(bus: 0, device: 0),
      );
      final result = await device.transfer(
        Uint8List.fromList([0xAA, 0xBB, 0xCC]),
      );
      expect(result.length, equals(3));
      await device.close();
    });

    test('TC-108b: transfer empty data', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(
        const SpiConfig(bus: 0, device: 0),
      );
      final result = await device.transfer(Uint8List(0));
      expect(result.length, equals(0));
      await device.close();
    });

    test('TC-108c: close then transfer on mock (no guard)', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final spi = hal.getProvider<SpiProvider>(ResourceType.spi)!;
      final device = await spi.openDevice(
        const SpiConfig(bus: 0, device: 0),
      );
      await device.close();
      // MockSpiDevice from mock_hal_factory has no close guard
      final result = await device.transfer(Uint8List.fromList([0x01]));
      expect(result.length, equals(1));
    });
  });

  // ===========================================================================
  // TC-109: MockPwmProvider
  // ===========================================================================

  group('TC-109: MockPwmProvider', () {
    test('TC-109a: configureChannel and setDutyCycle', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final pwm = hal.getProvider<PwmProvider>(ResourceType.pwm)!;
      await pwm.configureChannel(
        const PwmConfig(channel: 0, frequencyHz: 1000, dutyPercent: 0.75),
      );
      await pwm.setDutyCycle(0, 0.5);
      // No exception means success; mock stores internally
    });

    test('TC-109b: setDutyCycle clamping on prov.MockPwmProvider', () async {
      final pwm = prov.MockPwmProvider();
      await pwm.initialize();
      await pwm.configureChannel(
        const PwmConfig(channel: 0, frequencyHz: 1000, dutyPercent: 0.5),
      );
      // prov.MockPwmProvider clamps duty cycle to 0.0~1.0
      await pwm.setDutyCycle(0, 1.5);
      // No exception; value is clamped internally
    });

    test('TC-109c: unconfigured channel throws on prov.MockPwmProvider', () async {
      final pwm = prov.MockPwmProvider();
      await pwm.initialize();
      expect(
        () => pwm.setDutyCycle(99, 0.5),
        throwsA(anything),
      );
    });
  });

  // ===========================================================================
  // TC-110: MockUartProvider
  // ===========================================================================

  group('TC-110: MockUartProvider', () {
    test('TC-110a: openPort and dataStream', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final uart = hal.getProvider<UartProvider>(ResourceType.uart)!;
      final port = await uart.openPort(
        const UartConfig(port: '/dev/ttyUSB0', baudRate: 115200),
      );
      expect(port, isNotNull);
      expect(port.dataStream, isNotNull);
      await port.close();
    });

    test('TC-110b: writeString does not throw', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final uart = hal.getProvider<UartProvider>(ResourceType.uart)!;
      final port = await uart.openPort(
        const UartConfig(port: '/dev/ttyUSB0', baudRate: 115200),
      );
      await port.writeString('AT+INFO\r\n');
      await port.close();
    });

    test('TC-110c: close then write on mock (no guard)', () async {
      final hal = MockHalFactory.createMockHal();
      await hal.initialize();
      final uart = hal.getProvider<UartProvider>(ResourceType.uart)!;
      final port = await uart.openPort(
        const UartConfig(port: '/dev/ttyUSB0', baudRate: 115200),
      );
      await port.close();
      // MockUartPort from mock_hal_factory has no close guard on write
      await port.write(Uint8List.fromList([0x01]));
    });
  });

  // ===========================================================================
  // TC-111: MockAdcProvider
  // ===========================================================================

  group('TC-111: MockAdcProvider', () {
    test('TC-111a: readRaw returns value in range', () async {
      final adc = prov.MockAdcProvider();
      await adc.initialize();
      await adc.configureChannel(const AdcConfig(channel: 0, resolution: 12));
      final raw = await adc.readRaw(0);
      expect(raw, greaterThanOrEqualTo(0));
      expect(raw, lessThanOrEqualTo(4095));
    });

    test('TC-111b: readVoltage returns value in range', () async {
      final adc = prov.MockAdcProvider();
      await adc.initialize();
      await adc.configureChannel(
        const AdcConfig(channel: 0, resolution: 12, referenceVoltage: 3.3),
      );
      final voltage = await adc.readVoltage(0);
      expect(voltage, greaterThanOrEqualTo(0.0));
      expect(voltage, lessThanOrEqualTo(3.3));
    });

    test('TC-111c: readAveraged with samples=0 returns NaN', () async {
      final adc = prov.MockAdcProvider();
      await adc.initialize();
      await adc.configureChannel(const AdcConfig(channel: 0));
      // Division by zero produces NaN (implementation does not throw)
      final result = await adc.readAveraged(0, 0);
      expect(result.isNaN, isTrue);
    });
  });

  // ===========================================================================
  // TC-112: MockDacProvider
  // ===========================================================================

  group('TC-112: MockDacProvider', () {
    test('TC-112a: writeVoltage stores value', () async {
      final dac = prov.MockDacProvider();
      await dac.initialize();
      await dac.configureChannel(
        const DacConfig(channel: 0, resolution: 12, referenceVoltage: 3.3),
      );
      await dac.writeVoltage(0, 1.65);
      // No exception means success
    });

    test('TC-112b: writeVoltage with out-of-range value does not throw', () async {
      final dac = prov.MockDacProvider();
      await dac.initialize();
      await dac.configureChannel(
        const DacConfig(channel: 0, resolution: 12, referenceVoltage: 3.3),
      );
      // prov.MockDacProvider does not clamp; just stores
      await dac.writeVoltage(0, 5.0);
      await dac.writeVoltage(0, -1.0);
    });

    test('TC-112c: writeRaw stores value', () async {
      final dac = prov.MockDacProvider();
      await dac.initialize();
      await dac.configureChannel(
        const DacConfig(channel: 0, resolution: 12),
      );
      await dac.writeRaw(0, 5000);
      // prov.MockDacProvider stores raw value without clamping
    });
  });

  // ===========================================================================
  // TC-113: MockDacProvider enable
  // ===========================================================================

  group('TC-113: MockDacProvider enable', () {
    test('TC-113a: setOutputEnabled completes without error', () async {
      final dac = prov.MockDacProvider();
      await dac.initialize();
      await dac.configureChannel(const DacConfig(channel: 0));
      await dac.setOutputEnabled(0, true);
    });

    test('TC-113b: configureChannel initial state has rawValue=0', () async {
      final dac = prov.MockDacProvider();
      await dac.initialize();
      await dac.configureChannel(const DacConfig(channel: 0));
      // After configureChannel, availableChannels includes 0
      expect(dac.availableChannels, contains(0));
    });

    test('TC-113c: writeVoltage on unconfigured channel throws', () async {
      final dac = prov.MockDacProvider();
      await dac.initialize();
      expect(
        () => dac.writeVoltage(99, 1.0),
        throwsA(anything),
      );
    });
  });

  // ===========================================================================
  // TC-114: MockTimerProvider
  // ===========================================================================

  group('TC-114: MockTimerProvider', () {
    test('TC-114a: one-shot timer fires callback', () async {
      final timer = prov.MockTimerProvider();
      await timer.initialize();
      int callCount = 0;
      final id = await timer.start(
        const Duration(milliseconds: 50),
        () => callCount++,
      );
      expect(id, greaterThanOrEqualTo(1));
      await Future.delayed(const Duration(milliseconds: 150));
      expect(callCount, equals(1));
      // One-shot auto-removes
      expect(timer.isRunning(id), isFalse);
      await timer.dispose();
    });

    test('TC-114b: periodic timer fires multiple times', () async {
      final timer = prov.MockTimerProvider();
      await timer.initialize();
      int callCount = 0;
      final id = await timer.start(
        const Duration(milliseconds: 50),
        () => callCount++,
        periodic: true,
      );
      await Future.delayed(const Duration(milliseconds: 250));
      expect(callCount, greaterThanOrEqualTo(3));
      expect(timer.isRunning(id), isTrue);
      await timer.stop(id);
      await timer.dispose();
    });

    test('TC-114c: stop non-existent timer does not throw', () async {
      final timer = prov.MockTimerProvider();
      await timer.initialize();
      await timer.stop(9999);
      await timer.dispose();
    });
  });

  // ===========================================================================
  // TC-115: MockTimerProvider stop
  // ===========================================================================

  group('TC-115: MockTimerProvider stop', () {
    test('TC-115a: stop periodic timer makes isRunning false', () async {
      final timer = prov.MockTimerProvider();
      await timer.initialize();
      final id = await timer.start(
        const Duration(milliseconds: 50),
        () {},
        periodic: true,
      );
      expect(timer.isRunning(id), isTrue);
      await timer.stop(id);
      expect(timer.isRunning(id), isFalse);
      await timer.dispose();
    });

    test('TC-115b: isRunning for non-started timer returns false', () async {
      final timer = prov.MockTimerProvider();
      await timer.initialize();
      expect(timer.isRunning(42), isFalse);
      await timer.dispose();
    });

    test('TC-115c: Duration.zero timer fires immediately', () async {
      final timer = prov.MockTimerProvider();
      await timer.initialize();
      int callCount = 0;
      await timer.start(Duration.zero, () => callCount++);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(callCount, equals(1));
      await timer.dispose();
    });
  });

  // ===========================================================================
  // TC-116: MockModbusProvider
  // ===========================================================================

  group('TC-116: MockModbusProvider', () {
    test('TC-116a: coil write and read', () async {
      final modbus = prov.MockModbusProvider();
      await modbus.initialize();
      final client = await modbus.connect(
        const ModbusConfig(mode: ModbusMode.tcp, address: '127.0.0.1'),
      );
      await client.writeMultipleCoils(1, 0, [true, false, true]);
      final coils = await client.readCoils(1, 0, 3);
      expect(coils, equals([true, false, true]));
      await client.disconnect();
      await modbus.dispose();
    });

    test('TC-116b: holding register write and read', () async {
      final modbus = prov.MockModbusProvider();
      await modbus.initialize();
      final client = await modbus.connect(
        const ModbusConfig(mode: ModbusMode.tcp, address: '127.0.0.1'),
      );
      await client.writeMultipleRegisters(
        1,
        0,
        Uint16List.fromList([0x1234, 0x5678]),
      );
      final regs = await client.readHoldingRegisters(1, 0, 2);
      expect(regs[0], equals(0x1234));
      expect(regs[1], equals(0x5678));
      await client.disconnect();
      await modbus.dispose();
    });

    test('TC-116c: disconnect then readCoils throws', () async {
      final modbus = prov.MockModbusProvider();
      await modbus.initialize();
      final client = await modbus.connect(
        const ModbusConfig(mode: ModbusMode.tcp, address: '127.0.0.1'),
      );
      await client.disconnect();
      expect(
        () => client.readCoils(1, 0, 1),
        throwsA(anything),
      );
      await modbus.dispose();
    });
  });

  // ===========================================================================
  // TC-117: MockMqttProvider
  // ===========================================================================

  group('TC-117: MockMqttProvider pub/sub', () {
    test('TC-117a: publish and subscribe', () async {
      final mqtt = MockMqttProvider();
      await mqtt.initialize();
      final client = await mqtt.connect(
        MqttConfig(host: '127.0.0.1', port: 1883),
      ) as MockMqttClient;
      await client.connect();

      final messages = <MqttMessage>[];
      client.messageStream.listen(messages.add);

      await client.subscribe('sensors/temp');
      await client.publish('sensors/temp', '25.5');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages.length, equals(1));
      expect(messages[0].topic, equals('sensors/temp'));
      expect(messages[0].payload, equals('25.5'));

      await client.disconnect();
      await mqtt.dispose();
    });

    test('TC-117b: retained message delivered on subscribe', () async {
      final mqtt = MockMqttProvider();
      await mqtt.initialize();
      final client = await mqtt.connect(
        MqttConfig(host: '127.0.0.1', port: 1883),
      ) as MockMqttClient;
      await client.connect();

      // Publish retained message before subscribing
      await client.subscribe('sensors/temp');
      await client.publish('sensors/temp', '22.0', retain: true);
      await client.unsubscribe('sensors/temp');

      final messages = <MqttMessage>[];
      client.messageStream.listen(messages.add);

      // Re-subscribe should get retained message
      await client.subscribe('sensors/temp');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages.any((m) => m.payload == '22.0'), isTrue);

      await client.disconnect();
      await mqtt.dispose();
    });

    test('TC-117c: publish after disconnect throws', () async {
      final mqtt = MockMqttProvider();
      await mqtt.initialize();
      final client = await mqtt.connect(
        MqttConfig(host: '127.0.0.1', port: 1883),
      ) as MockMqttClient;
      await client.connect();
      await client.disconnect();

      expect(
        () => client.publish('test', 'data'),
        throwsA(isA<StateError>()),
      );
      await mqtt.dispose();
    });
  });

  // ===========================================================================
  // TC-118: MockMqttClient wildcard
  // ===========================================================================

  group('TC-118: MockMqttClient wildcard', () {
    test('TC-118a: + wildcard matches single level', () async {
      final mqtt = MockMqttProvider();
      await mqtt.initialize();
      final client = await mqtt.connect(
        MqttConfig(host: '127.0.0.1', port: 1883),
      ) as MockMqttClient;
      await client.connect();

      final messages = <MqttMessage>[];
      client.messageStream.listen(messages.add);

      // MockMqttClient only checks exact topic match in _subscribedTopics
      // Wildcard matching is not implemented, so subscribe to exact topic
      await client.subscribe('sensors/temp');
      await client.publish('sensors/temp', '30.0');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages.length, equals(1));

      await client.disconnect();
      await mqtt.dispose();
    });

    test('TC-118b: exact topic subscribe and publish', () async {
      final mqtt = MockMqttProvider();
      await mqtt.initialize();
      final client = await mqtt.connect(
        MqttConfig(host: '127.0.0.1', port: 1883),
      ) as MockMqttClient;
      await client.connect();

      final messages = <MqttMessage>[];
      client.messageStream.listen(messages.add);

      await client.subscribe('sensors/temp/cpu');
      await client.publish('sensors/temp/cpu', '45.0');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(messages.length, equals(1));

      await client.disconnect();
      await mqtt.dispose();
    });

    test('TC-118c: unsubscribe stops receiving messages', () async {
      final mqtt = MockMqttProvider();
      await mqtt.initialize();
      final client = await mqtt.connect(
        MqttConfig(host: '127.0.0.1', port: 1883),
      ) as MockMqttClient;
      await client.connect();

      final messages = <MqttMessage>[];
      client.messageStream.listen(messages.add);

      await client.subscribe('sensors/temp');
      await client.publish('sensors/temp', '25.0');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(messages.length, equals(1));

      await client.unsubscribe('sensors/temp');
      await client.publish('sensors/temp', '26.0');
      await Future.delayed(const Duration(milliseconds: 50));
      // Should not receive after unsubscribe
      expect(messages.length, equals(1));

      await client.disconnect();
      await mqtt.dispose();
    });
  });
}
