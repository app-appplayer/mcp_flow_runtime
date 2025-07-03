/// Hardware Abstraction Layer factory and platform detection

import 'dart:io';

import '../types/hardware_types.dart';
import 'hal_interface.dart';
import 'providers/mock_provider.dart';

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
      // Check for Raspberry Pi
      final deviceTreeModel = File('/proc/device-tree/model');
      if (deviceTreeModel.existsSync()) {
        final model = deviceTreeModel.readAsStringSync();
        if (model.contains('Raspberry Pi')) {
          return true;
        }
      }

      // Check for GPIO sysfs interface
      final gpioDir = Directory('/sys/class/gpio');
      if (gpioDir.existsSync()) {
        return true;
      }

      // Check for common embedded boards
      final cpuInfo = File('/proc/cpuinfo');
      if (cpuInfo.existsSync()) {
        final info = cpuInfo.readAsStringSync();
        if (info.contains('BCM') || // Broadcom (Raspberry Pi)
            info.contains('AM33') || // BeagleBone
            info.contains('i.MX') || // NXP i.MX
            info.contains('Allwinner')) {
          // Orange Pi, etc.
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
    // For now, return mock HAL
    // TODO: Implement with dart_periphery or flutter_gpiod
    return MockHal(config: config);
  }

  /// Create desktop Linux HAL
  HardwareAbstractionLayer _createLinuxHal(Map<String, dynamic>? config) {
    // Limited hardware access on desktop Linux
    return MockHal(config: config, limitedMode: true);
  }

  /// Create Windows HAL
  HardwareAbstractionLayer _createWindowsHal(Map<String, dynamic>? config) {
    // Limited hardware access on Windows
    return MockHal(config: config, limitedMode: true);
  }

  /// Create macOS HAL
  HardwareAbstractionLayer _createMacOsHal(Map<String, dynamic>? config) {
    // Limited hardware access on macOS
    return MockHal(config: config, limitedMode: true);
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
  }
}