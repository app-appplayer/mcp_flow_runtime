import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_flow_runtime/src/hal/hal_factory.dart';
import 'package:mcp_flow_runtime/src/hal/hal_interface.dart';
import 'package:mcp_flow_runtime/src/types/hardware_types.dart';

void main() {
  group('Platform-specific HAL Providers', () {
    test('HAL factory detects current platform', () {
      final factory = HalFactory();
      final platform = factory.detectPlatform();
      
      // Should detect the test platform
      expect(platform, isNotNull);
      expect(platform, isA<PlatformType>());
    });

    test('HAL factory creates platform-specific HAL', () async {
      final factory = HalFactory();
      final hal = factory.createHal();
      
      expect(hal, isNotNull);
      
      await hal.initialize();
      expect(hal.providers, isNotEmpty);
      expect(hal.systemInfo['platform'], isNotNull);
      
      await hal.dispose();
    });

    test('Linux GPIO provider on supported platform', () async {
      final factory = HalFactory();
      
      // Force Linux platform
      final hal = factory.createHal(
        platform: Platform.isLinux ? null : PlatformType.linux,
      );
      
      await hal.initialize();
      
      final gpioProvider = hal.getProvider<GpioProvider>(ResourceType.gpio);
      expect(gpioProvider, isNotNull);
      
      if (Directory('/sys/class/gpio').existsSync()) {
        expect(gpioProvider!.name, contains('Linux GPIO'));
      } else {
        expect(gpioProvider!.name, contains('Mock GPIO'));
      }
      
      await hal.dispose();
    });

    test('Windows GPIO provider on Windows platform', () async {
      final factory = HalFactory();
      
      // Force Windows platform
      final hal = factory.createHal(platform: PlatformType.windows);
      
      await hal.initialize();
      
      final gpioProvider = hal.getProvider<GpioProvider>(ResourceType.gpio);
      expect(gpioProvider, isNotNull);
      expect(gpioProvider!.name, contains('Windows GPIO'));
      expect(gpioProvider.capabilities['interface'], equals('virtual'));
      
      await hal.dispose();
    });

    test('GPIO provider basic operations', () async {
      final factory = HalFactory();
      final hal = factory.createHal();
      
      await hal.initialize();
      
      final gpioProvider = hal.getProvider<GpioProvider>(ResourceType.gpio);
      expect(gpioProvider, isNotNull);
      
      // Configure output pin
      await gpioProvider!.configurePin(GpioConfig(
        pin: 0,
        mode: GpioMode.output,
        initialValue: false,
      ));
      
      // Write and read
      await gpioProvider.writePin(0, true);
      final value = await gpioProvider.readPin(0);
      expect(value, isTrue);
      
      await hal.dispose();
    });

    test('GPIO provider interrupt handling', () async {
      final factory = HalFactory();
      final hal = factory.createHal();
      
      await hal.initialize();
      
      final gpioProvider = hal.getProvider<GpioProvider>(ResourceType.gpio);
      expect(gpioProvider, isNotNull);
      
      // Configure input pin
      await gpioProvider!.configurePin(GpioConfig(
        pin: 1,
        mode: GpioMode.input,
      ));
      
      // Set interrupt handler
      var interruptCount = 0;
      await gpioProvider.setInterruptHandler(
        1,
        GpioInterrupt.both,
        (value) => interruptCount++,
      );
      
      // Wait for potential interrupts (on virtual/mock providers)
      await Future.delayed(Duration(milliseconds: 100));
      
      // Remove handler
      await gpioProvider.removeInterruptHandler(1);
      
      await hal.dispose();
    });
  });
}