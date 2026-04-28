/// Windows Hardware Abstraction Layer implementation
import 'dart:io';
import 'package:logging/logging.dart';
import '../../types/hardware_types.dart';
import '../hal_interface.dart';
import '../providers/windows_gpio_provider.dart';
import '../providers/mock_provider.dart';
import '../providers/mqtt_provider.dart';

/// Windows-specific HAL implementation
class WindowsHal implements HardwareAbstractionLayer {
  final Logger _logger = Logger('WindowsHal');
  final Map<ResourceType, HardwareProvider> _providers = {};
  final Map<String, dynamic>? config;

  WindowsHal({this.config});

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
    _logger.info('Initializing Windows HAL');

    // Use Windows virtual GPIO provider
    registerProvider(WindowsGpioProvider());
    
    // Register other providers with limited mode
    registerProvider(MockI2cProvider(limitedMode: true));
    registerProvider(MockSpiProvider(limitedMode: true));
    registerProvider(MockPwmProvider(limitedMode: true));
    registerProvider(MockUartProvider(limitedMode: true));
    registerProvider(MockAdcProvider(limitedMode: true));
    registerProvider(MockModbusProvider(limitedMode: true));
    registerProvider(MockMqttProvider()); // MQTT works on Windows

    // Check for COM ports
    _checkComPorts();

    // Check for Windows IoT Core features
    _checkWindowsIoT();

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
    _logger.info('Disposing Windows HAL');
    
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
    'platform': 'Windows',
    'version': _getWindowsVersion(),
    'architecture': Platform.version.contains('x64') ? 'x64' : 'x86',
    'providers': _providers.entries
        .map((e) => {
              'type': e.key.name,
              'provider': e.value.name,
              'version': e.value.version,
              'ready': e.value.isReady,
            })
        .toList(),
    'config': config,
    'com_ports': _getComPorts(),
    'windows_iot': _isWindowsIoT(),
  };

  String _getWindowsVersion() {
    try {
      final result = Process.runSync('cmd', ['/c', 'ver']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final versionMatch = RegExp(r'Version\s+([\d.]+)').firstMatch(output);
        if (versionMatch != null) {
          return versionMatch.group(1)!;
        }
      }
    } catch (e) {
      _logger.fine('Failed to get Windows version: $e');
    }
    return 'Unknown';
  }

  void _checkComPorts() {
    try {
      final ports = _getComPorts();
      if (ports.isNotEmpty) {
        _logger.info('Found COM ports: ${ports.join(', ')}');
        // Could enhance UART provider to use these ports
      }
    } catch (e) {
      _logger.fine('Failed to check COM ports: $e');
    }
  }

  List<String> _getComPorts() {
    final ports = <String>[];
    try {
      // Use WMI to query COM ports
      final result = Process.runSync('wmic', [
        'path',
        'Win32_PnPEntity',
        'where',
        'Name like "(COM%"',
        'get',
        'Name',
        '/value'
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final portMatches = RegExp(r'COM\d+').allMatches(output);
        for (final match in portMatches) {
          ports.add(match.group(0)!);
        }
      }
    } catch (e) {
      _logger.fine('Failed to list COM ports: $e');
      
      // Fallback: try direct check
      for (int i = 1; i <= 256; i++) {
        final port = 'COM$i';
        if (File('\\\\.\\$port').existsSync()) {
          ports.add(port);
        }
      }
    }
    return ports;
  }

  bool _isWindowsIoT() {
    try {
      // Check for Windows IoT Core
      final result = Process.runSync('reg', [
        'query',
        'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion',
        '/v',
        'ProductName'
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        return output.contains('IoT');
      }
    } catch (e) {
      _logger.fine('Failed to check Windows IoT: $e');
    }
    return false;
  }

  void _checkWindowsIoT() {
    if (_isWindowsIoT()) {
      _logger.info('Windows IoT Core detected - hardware access may be available');
      // Could register real hardware providers for Windows IoT
    }
  }
}