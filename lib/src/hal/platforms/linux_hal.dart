/// Linux Hardware Abstraction Layer implementation (Desktop/Server)
import 'dart:io';
import 'package:logging/logging.dart';
import '../../types/hardware_types.dart';
import '../hal_interface.dart';
import '../providers/linux_gpio_provider.dart';
import '../providers/linux_i2c_provider.dart';
import '../providers/linux_spi_provider.dart';
import '../providers/mock_provider.dart';
import '../providers/mqtt_provider.dart';

/// Desktop/Server Linux HAL implementation
class LinuxHal implements HardwareAbstractionLayer {
  final Logger _logger = Logger('LinuxHal');
  final Map<ResourceType, HardwareProvider> _providers = {};
  final Map<String, dynamic>? config;

  LinuxHal({this.config});

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
    _logger.info('Initializing Linux HAL');

    // Detect Linux distribution
    final distro = await _getLinuxDistribution();
    _logger.info('Linux distribution: $distro');

    // Try to use Linux GPIO if available
    if (await _hasGpioSupport()) {
      _logger.info('GPIO support detected');
      registerProvider(LinuxGpioProvider(
        sysfsPath: config?['gpioSysfsPath'] as String?,
      ));
    } else {
      _logger.info('No GPIO support, using mock provider');
      registerProvider(MockGpioProvider(limitedMode: true));
    }
    
    // Check for I2C support
    if (await _hasI2CSupport()) {
      _logger.info('I2C support detected');
      registerProvider(LinuxI2cProvider());
    } else {
      _logger.info('No I2C support, using mock provider');
      registerProvider(MockI2cProvider(limitedMode: true));
    }
    
    // Check for SPI support
    if (await _hasSPISupport()) {
      _logger.info('SPI support detected');
      registerProvider(LinuxSpiProvider());
    } else {
      _logger.info('No SPI support, using mock provider');
      registerProvider(MockSpiProvider(limitedMode: true));
    }
    
    // Register other providers
    registerProvider(MockPwmProvider(limitedMode: true));
    registerProvider(MockUartProvider(limitedMode: !await _hasSerialSupport()));
    registerProvider(MockAdcProvider(limitedMode: true));
    registerProvider(MockModbusProvider(limitedMode: true));
    registerProvider(MockMqttProvider()); // MQTT works on Linux

    // Initialize all providers - create a copy to avoid concurrent modification
    final providersList = _providers.values.toList();
    for (final provider in providersList) {
      try {
        await provider.initialize();
        _logger.info('Initialized ${provider.name}');
      } catch (e) {
        _logger.warning('Failed to initialize ${provider.name}: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    _logger.info('Disposing Linux HAL');
    
    // Create a copy to avoid concurrent modification
    final providersList = _providers.values.toList();
    for (final provider in providersList) {
      try {
        await provider.dispose();
      } catch (e) {
        _logger.warning('Failed to dispose ${provider.name}: $e');
      }
    }
    _providers.clear();
  }

  @override
  Map<String, dynamic> get systemInfo => {
    'platform': 'Linux',
    'distribution': _cachedDistro ?? 'Unknown',
    'kernel': _getKernelVersion(),
    'architecture': Platform.version.contains('x86_64') ? 'x86_64' : 
                   Platform.version.contains('aarch64') ? 'ARM64' : 'Unknown',
    'providers': _providers.entries
        .map((e) => {
              'type': e.key.name,
              'provider': e.value.name,
              'version': e.value.version,
              'ready': e.value.isReady,
            })
        .toList(),
    'config': config,
    'hardware_support': {
      'gpio': _hasGpioSupport(),
      'i2c': _hasI2CSupport(),
      'spi': _hasSPISupport(),
      'serial': _hasSerialSupport(),
    },
    'serial_devices': _getSerialDevices(),
  };

  String? _cachedDistro;

  Future<String> _getLinuxDistribution() async {
    if (_cachedDistro != null) return _cachedDistro!;

    try {
      // Try /etc/os-release first (systemd standard)
      final osRelease = File('/etc/os-release');
      if (await osRelease.exists()) {
        final content = await osRelease.readAsString();
        final nameMatch = RegExp(r'PRETTY_NAME="([^"]+)"').firstMatch(content);
        if (nameMatch != null) {
          _cachedDistro = nameMatch.group(1)!;
          return _cachedDistro!;
        }
      }

      // Try lsb_release
      final result = await Process.run('lsb_release', ['-d']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final parts = output.split(':');
        if (parts.length > 1) {
          _cachedDistro = parts[1].trim();
          return _cachedDistro!;
        }
      }

      // Try various distro-specific files
      final distroFiles = {
        '/etc/debian_version': 'Debian',
        '/etc/redhat-release': 'Red Hat',
        '/etc/fedora-release': 'Fedora',
        '/etc/arch-release': 'Arch Linux',
        '/etc/gentoo-release': 'Gentoo',
        '/etc/SuSE-release': 'SUSE',
      };

      for (final entry in distroFiles.entries) {
        if (await File(entry.key).exists()) {
          _cachedDistro = entry.value;
          return _cachedDistro!;
        }
      }
    } catch (e) {
      _logger.fine('Failed to detect Linux distribution: $e');
    }

    _cachedDistro = 'Generic Linux';
    return _cachedDistro!;
  }

  String _getKernelVersion() {
    try {
      final result = Process.runSync('uname', ['-r']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      _logger.fine('Failed to get kernel version: $e');
    }
    return 'Unknown';
  }

  Future<bool> _hasGpioSupport() async {
    return await Directory('/sys/class/gpio').exists();
  }

  Future<bool> _hasI2CSupport() async {
    final i2cDev = Directory('/dev');
    if (!await i2cDev.exists()) return false;
    
    try {
      final entries = await i2cDev.list().toList();
      return entries.any((e) => e.path.contains(RegExp(r'i2c-\d+')));
    } catch (e) {
      return false;
    }
  }

  Future<bool> _hasSPISupport() async {
    final spiDev = Directory('/dev');
    if (!await spiDev.exists()) return false;
    
    try {
      final entries = await spiDev.list().toList();
      return entries.any((e) => e.path.contains(RegExp(r'spidev\d+\.\d+')));
    } catch (e) {
      return false;
    }
  }

  Future<bool> _hasSerialSupport() async {
    final devices = await _getSerialDevices();
    return devices.isNotEmpty;
  }

  Future<List<String>> _getSerialDevices() async {
    final devices = <String>[];
    try {
      final devDir = Directory('/dev');
      final entries = await devDir.list().toList();
      
      for (final entry in entries) {
        if (entry.path.contains(RegExp(r'tty(USB|ACM|S)\d+')) ||
            entry.path.contains(RegExp(r'serial\d+'))) {
          devices.add(entry.path);
        }
      }
    } catch (e) {
      _logger.fine('Failed to list serial devices: $e');
    }
    return devices;
  }
}