/// macOS Hardware Abstraction Layer implementation
import 'dart:io';
import 'package:logging/logging.dart';
import '../../types/hardware_types.dart';
import '../hal_interface.dart';
import '../providers/mock_provider.dart';
import '../providers/mqtt_provider.dart';

/// macOS-specific HAL implementation
class MacOSHal implements HardwareAbstractionLayer {
  final Logger _logger = Logger('MacOSHal');
  final Map<ResourceType, HardwareProvider> _providers = {};
  final Map<String, dynamic>? config;

  MacOSHal({this.config});

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
    _logger.info('Initializing macOS HAL');

    // macOS has limited hardware access
    // Use mock providers in limited mode for safety
    registerProvider(MockGpioProvider(limitedMode: true));
    registerProvider(MockI2cProvider(limitedMode: true));
    registerProvider(MockSpiProvider(limitedMode: true));
    registerProvider(MockPwmProvider(limitedMode: true));
    registerProvider(MockUartProvider(limitedMode: true));
    registerProvider(MockAdcProvider(limitedMode: true));
    registerProvider(MockModbusProvider(limitedMode: true));
    registerProvider(MockMqttProvider()); // MQTT works on macOS

    // Check for USB serial devices
    _checkSerialDevices();

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
    _logger.info('Disposing macOS HAL');
    
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
    'platform': 'macOS',
    'version': _getMacOSVersion(),
    'architecture': Platform.version.contains('arm64') ? 'Apple Silicon' : 'Intel',
    'providers': _providers.entries
        .map((e) => {
              'type': e.key.name,
              'provider': e.value.name,
              'version': e.value.version,
              'ready': e.value.isReady,
            })
        .toList(),
    'config': config,
    'serial_devices': _getSerialDevices(),
  };

  String _getMacOSVersion() {
    try {
      final result = Process.runSync('sw_vers', ['-productVersion']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      _logger.fine('Failed to get macOS version: $e');
    }
    return 'Unknown';
  }

  void _checkSerialDevices() {
    try {
      final devices = _getSerialDevices();
      if (devices.isNotEmpty) {
        _logger.info('Found serial devices: ${devices.join(', ')}');
        // Could enhance UART provider to use these devices
      }
    } catch (e) {
      _logger.fine('Failed to check serial devices: $e');
    }
  }

  List<String> _getSerialDevices() {
    final devices = <String>[];
    try {
      final devDir = Directory('/dev');
      final entries = devDir.listSync();
      
      for (final entry in entries) {
        if (entry.path.contains('tty.usb') || 
            entry.path.contains('cu.usb') ||
            entry.path.contains('tty.usbserial') ||
            entry.path.contains('cu.usbserial')) {
          devices.add(entry.path);
        }
      }
    } catch (e) {
      _logger.fine('Failed to list serial devices: $e');
    }
    return devices;
  }
}