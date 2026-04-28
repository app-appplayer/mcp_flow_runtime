/// Embedded Linux Hardware Abstraction Layer base implementation
import 'dart:io';
import 'package:logging/logging.dart';
import '../../types/hardware_types.dart';
import '../hal_interface.dart';
import '../providers/linux_gpio_provider.dart';
import '../providers/mock_provider.dart';

/// Base class for embedded Linux HAL implementations
abstract class EmbeddedLinuxHal implements HardwareAbstractionLayer {
  final Logger logger;
  final Map<ResourceType, HardwareProvider> _providers = {};
  final Map<String, dynamic>? config;

  EmbeddedLinuxHal({
    required String loggerName,
    this.config,
  }) : logger = Logger(loggerName);

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

  /// Get the board model/name
  Future<String> getBoardModel();

  /// Get board-specific GPIO pins
  List<int> getGpioPins();

  /// Get board-specific I2C buses
  List<int> getI2cBuses();

  /// Get board-specific SPI buses
  List<int> getSpiBuses();

  /// Get board-specific UART devices
  List<String> getUartDevices();

  /// Check if this board is detected
  Future<bool> isDetected();

  /// Initialize board-specific features
  Future<void> initializeBoardSpecific();

  @override
  Future<void> initialize() async {
    logger.info('Initializing Embedded Linux HAL');

    // Detect board model
    final boardModel = await getBoardModel();
    logger.info('Detected board: $boardModel');

    // Initialize GPIO provider
    final gpioPath = config?['gpioSysfsPath'] as String? ?? '/sys/class/gpio';
    registerProvider(LinuxGpioProvider(sysfsPath: gpioPath));

    // Initialize I2C
    await _initializeI2C();

    // Initialize SPI
    await _initializeSPI();

    // Initialize PWM
    await _initializePWM();

    // Initialize UART
    await _initializeUART();

    // Initialize ADC if available
    await _initializeADC();

    // Initialize board-specific features
    await initializeBoardSpecific();

    // Initialize all providers - create a copy to avoid concurrent modification
    final providersList = _providers.values.toList();
    for (final provider in providersList) {
      try {
        await provider.initialize();
        logger.info('Initialized ${provider.name}');
      } catch (e) {
        logger.warning('Failed to initialize ${provider.name}: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    logger.info('Disposing Embedded Linux HAL');
    
    // Create a copy to avoid concurrent modification
    final providersList = _providers.values.toList();
    for (final provider in providersList) {
      try {
        await provider.dispose();
      } catch (e) {
        logger.warning('Failed to dispose ${provider.name}: $e');
      }
    }
    _providers.clear();
  }

  @override
  Map<String, dynamic> get systemInfo => {
    'platform': 'Embedded Linux',
    'board': getBoardModel(),
    'kernel': _getKernelVersion(),
    'architecture': _getCpuArchitecture(),
    'providers': _providers.entries
        .map((e) => {
              'type': e.key.name,
              'provider': e.value.name,
              'version': e.value.version,
              'ready': e.value.isReady,
            })
        .toList(),
    'config': config,
    'gpio_pins': getGpioPins(),
    'i2c_buses': getI2cBuses(),
    'spi_buses': getSpiBuses(),
    'uart_devices': getUartDevices(),
  };

  Future<void> _initializeI2C() async {
    try {
      final i2cBuses = getI2cBuses();
      final availableBuses = <int>[];
      
      for (final bus in i2cBuses) {
        if (await File('/dev/i2c-$bus').exists()) {
          availableBuses.add(bus);
        }
      }

      if (availableBuses.isNotEmpty) {
        logger.info('Found I2C buses: ${availableBuses.join(', ')}');
        // TODO: Register real I2C provider
        registerProvider(MockI2cProvider());
      } else {
        logger.info('No I2C buses found');
      }
    } catch (e) {
      logger.warning('Failed to initialize I2C: $e');
    }
  }

  Future<void> _initializeSPI() async {
    try {
      final spiBuses = getSpiBuses();
      final availableDevices = <String>[];
      
      for (final bus in spiBuses) {
        // Check for multiple chip selects per bus
        for (int cs = 0; cs < 4; cs++) {
          final device = '/dev/spidev$bus.$cs';
          if (await File(device).exists()) {
            availableDevices.add(device);
          }
        }
      }

      if (availableDevices.isNotEmpty) {
        logger.info('Found SPI devices: ${availableDevices.join(', ')}');
        // TODO: Register real SPI provider
        registerProvider(MockSpiProvider());
      } else {
        logger.info('No SPI devices found');
      }
    } catch (e) {
      logger.warning('Failed to initialize SPI: $e');
    }
  }

  Future<void> _initializePWM() async {
    try {
      // Check for hardware PWM support
      final pwmDir = Directory('/sys/class/pwm');
      if (await pwmDir.exists()) {
        logger.info('Hardware PWM support detected');
        // TODO: Register real PWM provider
        registerProvider(MockPwmProvider());
      } else {
        logger.info('No hardware PWM support, using software PWM');
        registerProvider(MockPwmProvider());
      }
    } catch (e) {
      logger.warning('Failed to initialize PWM: $e');
    }
  }

  Future<void> _initializeUART() async {
    try {
      final uartDevices = getUartDevices();
      final availableDevices = <String>[];
      
      for (final device in uartDevices) {
        if (await File(device).exists()) {
          availableDevices.add(device);
        }
      }

      if (availableDevices.isNotEmpty) {
        logger.info('Found UART devices: ${availableDevices.join(', ')}');
        // TODO: Register real UART provider
        registerProvider(MockUartProvider());
      }
    } catch (e) {
      logger.warning('Failed to initialize UART: $e');
    }
  }

  Future<void> _initializeADC() async {
    try {
      // Check for IIO ADC devices
      final iioDir = Directory('/sys/bus/iio/devices');
      if (await iioDir.exists()) {
        final devices = await iioDir.list().toList();
        final adcDevices = devices.where((d) => d.path.contains('iio:device')).toList();
        
        if (adcDevices.isNotEmpty) {
          logger.info('Found ${adcDevices.length} IIO ADC devices');
          // TODO: Register real ADC provider
          registerProvider(MockAdcProvider());
        }
      }
    } catch (e) {
      logger.warning('Failed to initialize ADC: $e');
    }
  }

  String _getKernelVersion() {
    try {
      final result = Process.runSync('uname', ['-r']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      logger.fine('Failed to get kernel version: $e');
    }
    return 'Unknown';
  }

  String _getCpuArchitecture() {
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      logger.fine('Failed to get CPU architecture: $e');
    }
    return 'Unknown';
  }

  /// Enable specific hardware interfaces (requires root privileges)
  Future<void> enableInterface(String interface) async {
    logger.warning('Interface enabling ($interface) typically requires root privileges and system configuration');
  }
}