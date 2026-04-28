/// Hardware Abstraction Layer factory and platform detection

import 'dart:io';

import '../types/hardware_types.dart';
import 'hal_interface.dart';
import 'providers/mock_provider.dart';
import 'providers/linux_gpio_provider.dart';
import 'platforms/macos_hal.dart';
import 'platforms/windows_hal.dart';
import 'platforms/linux_hal.dart';
import 'platforms/raspberry_pi_hal.dart';
import 'platforms/beaglebone_hal.dart';
import 'platforms/orange_pi_hal.dart';

/// Platform types
enum PlatformType {
  linux,
  windows,
  macos,
  android,
  ios,
  embedded,
  mock,
}

/// HAL factory for creating platform-specific implementations
class HalFactory {
  static final HalFactory _instance = HalFactory._internal();
  factory HalFactory() => _instance;
  HalFactory._internal();

  /// Detect current platform
  PlatformType detectPlatform() {
    if (Platform.isLinux) {
      // Check if running on embedded Linux (Raspberry Pi, etc.)
      if (_isEmbeddedLinux()) {
        return PlatformType.embedded;
      }
      return PlatformType.linux;
    } else if (Platform.isWindows) {
      return PlatformType.windows;
    } else if (Platform.isMacOS) {
      return PlatformType.macos;
    } else if (Platform.isAndroid) {
      return PlatformType.android;
    } else if (Platform.isIOS) {
      return PlatformType.ios;
    }
    return PlatformType.mock;
  }

  /// Create HAL instance for current platform
  HardwareAbstractionLayer createHal({
    PlatformType? platform,
    Map<String, dynamic>? config,
  }) {
    final targetPlatform = platform ?? detectPlatform();
    
    switch (targetPlatform) {
      case PlatformType.embedded:
        return _createEmbeddedHal(config);
      case PlatformType.linux:
        return _createLinuxHal(config);
      case PlatformType.windows:
        return _createWindowsHal(config);
      case PlatformType.macos:
        return _createMacOsHal(config);
      case PlatformType.android:
        return _createAndroidHal(config);
      case PlatformType.ios:
        return _createIosHal(config);
      case PlatformType.mock:
        return _createMockHal(config);
    }
  }

  /// Check if running on embedded Linux
  bool _isEmbeddedLinux() {
    try {
      // Check for device tree model (common on embedded systems)
      final deviceTreeModel = File('/proc/device-tree/model');
      if (deviceTreeModel.existsSync()) {
        return true;
      }

      // Check for GPIO sysfs interface
      final gpioDir = Directory('/sys/class/gpio');
      if (gpioDir.existsSync()) {
        return true;
      }

      // Check for common embedded boards in cpuinfo
      final cpuInfo = File('/proc/cpuinfo');
      if (cpuInfo.existsSync()) {
        final info = cpuInfo.readAsStringSync();
        if (info.contains('BCM') || // Broadcom (Raspberry Pi)
            info.contains('AM33') || // BeagleBone
            info.contains('i.MX') || // NXP i.MX
            info.contains('Allwinner') || // Orange Pi, etc.
            info.contains('Rockchip') || // Rock Pi, etc.
            info.contains('Amlogic')) { // ODroid, etc.
          return true;
        }
      }
    } catch (_) {
      // Ignore errors in detection
    }
    return false;
  }

  /// Create embedded Linux HAL
  HardwareAbstractionLayer _createEmbeddedHal(Map<String, dynamic>? config) {
    // Quick synchronous detection based on device tree model
    try {
      final deviceTreeModel = File('/proc/device-tree/model');
      if (deviceTreeModel.existsSync()) {
        final model = deviceTreeModel.readAsStringSync();
        
        if (model.contains('Raspberry Pi')) {
          return RaspberryPiHal(config: config);
        } else if (model.contains('BeagleBone') || model.contains('TI AM335x')) {
          return BeagleBoneHal(config: config);
        } else if (model.contains('Orange Pi') || model.contains('OrangePi')) {
          return OrangePiHal(config: config);
        }
      }
    } catch (_) {
      // Fall through to generic
    }

    // Generic embedded Linux HAL
    final hal = DefaultHal(config: config, platform: PlatformType.embedded);
    
    // Register Linux GPIO provider
    hal.registerProvider(LinuxGpioProvider(
      sysfsPath: config?['gpioSysfsPath'] as String?,
    ));
    
    // Register other mock providers for now
    hal.registerProvider(MockI2cProvider());
    hal.registerProvider(MockSpiProvider());
    hal.registerProvider(MockPwmProvider());
    hal.registerProvider(MockUartProvider());
    hal.registerProvider(MockAdcProvider());
    hal.registerProvider(MockModbusProvider());
    
    return hal;
  }

  /// Create desktop Linux HAL
  HardwareAbstractionLayer _createLinuxHal(Map<String, dynamic>? config) {
    return LinuxHal(config: config);
  }

  /// Create Windows HAL
  HardwareAbstractionLayer _createWindowsHal(Map<String, dynamic>? config) {
    return WindowsHal(config: config);
  }

  /// Create macOS HAL
  HardwareAbstractionLayer _createMacOsHal(Map<String, dynamic>? config) {
    return MacOSHal(config: config);
  }

  /// Create Android HAL
  HardwareAbstractionLayer _createAndroidHal(Map<String, dynamic>? config) {
    // Android has some hardware access through USB
    return MockHal(config: config, limitedMode: true);
  }

  /// Create iOS HAL
  HardwareAbstractionLayer _createIosHal(Map<String, dynamic>? config) {
    // iOS has very limited hardware access
    return MockHal(config: config, limitedMode: true);
  }

  /// Create mock HAL for testing
  HardwareAbstractionLayer _createMockHal(Map<String, dynamic>? config) {
    return MockHal(config: config);
  }
}

/// Default HAL implementation
class DefaultHal implements HardwareAbstractionLayer {
  final Map<ResourceType, HardwareProvider> _providers = {};
  final Map<String, dynamic>? config;
  final PlatformType platform;

  DefaultHal({
    this.config,
    required this.platform,
  });

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
  List<HardwareProvider> get providers => _providers.values.toList();

  @override
  Future<void> initialize() async {
    for (final provider in _providers.values) {
      await provider.initialize();
    }
  }

  @override
  Future<void> dispose() async {
    for (final provider in _providers.values) {
      await provider.dispose();
    }
  }

  @override
  Map<String, dynamic> get systemInfo => {
        'platform': platform.name,
        'providers': _providers.entries
            .map((e) => {
                  'type': e.key.name,
                  'provider': e.value.name,
                  'version': e.value.version,
                })
            .toList(),
        'config': config,
      };
}

/// Mock HAL for testing and limited platforms
class MockHal extends DefaultHal {
  final bool limitedMode;

  MockHal({
    super.config,
    this.limitedMode = false,
  }) : super(platform: PlatformType.mock) {
    // Register mock providers
    registerProvider(MockGpioProvider(limitedMode: limitedMode));
    registerProvider(MockI2cProvider(limitedMode: limitedMode));
    registerProvider(MockSpiProvider(limitedMode: limitedMode));
    registerProvider(MockPwmProvider(limitedMode: limitedMode));
    registerProvider(MockUartProvider(limitedMode: limitedMode));
    registerProvider(MockAdcProvider(limitedMode: limitedMode));
    registerProvider(MockModbusProvider(limitedMode: limitedMode));
    registerProvider(MockDacProvider(limitedMode: limitedMode));
    registerProvider(MockTimerProvider(limitedMode: limitedMode));
  }
}