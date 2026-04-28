/// Orange Pi specific HAL implementation
import 'dart:io';
import 'embedded_linux_hal.dart';
import '../providers/mock_provider.dart';

/// Orange Pi hardware abstraction layer
class OrangePiHal extends EmbeddedLinuxHal {
  String? _cachedBoardModel;

  OrangePiHal({Map<String, dynamic>? config}) 
    : super(loggerName: 'OrangePiHal', config: config);

  @override
  Future<String> getBoardModel() async {
    if (_cachedBoardModel != null) return _cachedBoardModel!;
    _cachedBoardModel = await _detectOrangePiModel();
    return _cachedBoardModel!;
  }

  @override
  List<int> getGpioPins() {
    // Orange Pi GPIO pins (varies by model, this is for common 40-pin header)
    // Using WiringPi-like numbering
    return [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
      21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31
    ];
  }

  @override
  List<int> getI2cBuses() {
    // Orange Pi typically has 2-3 I2C buses
    return [0, 1, 2];
  }

  @override
  List<int> getSpiBuses() {
    // Orange Pi typically has 1-2 SPI buses
    return [0, 1];
  }

  @override
  List<String> getUartDevices() {
    // Orange Pi UART devices
    return [
      '/dev/ttyS0', // UART0 (usually debug console)
      '/dev/ttyS1', // UART1
      '/dev/ttyS2', // UART2
      '/dev/ttyS3', // UART3
      '/dev/ttyS4', // UART4
      '/dev/ttyS5', // UART5
      '/dev/ttyS6', // UART6
      '/dev/ttyS7'  // UART7
    ];
  }

  @override
  Future<bool> isDetected() async {
    try {
      // Check device tree model
      final deviceTreeModel = File('/proc/device-tree/model');
      if (await deviceTreeModel.exists()) {
        final model = await deviceTreeModel.readAsString();
        if (model.contains('Orange Pi') || model.contains('OrangePi')) {
          return true;
        }
      }

      // Check CPU info for Allwinner processor
      final cpuInfo = File('/proc/cpuinfo');
      if (await cpuInfo.exists()) {
        final info = await cpuInfo.readAsString();
        if (info.contains('Allwinner') || info.contains('sun')) {
          // Additional check for Orange Pi specific files
          final compatFile = File('/proc/device-tree/compatible');
          if (await compatFile.exists()) {
            final compat = await compatFile.readAsString();
            return compat.contains('orange') || compat.contains('xunlong');
          }
        }
      }
    } catch (e) {
      logger.fine('Failed to detect Orange Pi: $e');
    }
    return false;
  }

  @override
  Future<void> initializeBoardSpecific() async {
    logger.info('Initializing Orange Pi specific features');

    // Check for H3/H5/H6 specific features
    await _checkSocFeatures();

    // Check thermal zones
    await _checkThermalZones();

    // Register Modbus provider
    registerProvider(MockModbusProvider());
  }

  Future<String> _detectOrangePiModel() async {
    try {
      // Try device tree model
      final deviceTreeModel = File('/proc/device-tree/model');
      if (await deviceTreeModel.exists()) {
        final model = await deviceTreeModel.readAsString();
        return model.trim();
      }

      // Try to identify by SoC
      final compatFile = File('/proc/device-tree/compatible');
      if (await compatFile.exists()) {
        final compat = await compatFile.readAsString();
        
        if (compat.contains('sun8i-h3')) {
          return 'Orange Pi (H3 SoC)';
        } else if (compat.contains('sun50i-h5')) {
          return 'Orange Pi (H5 SoC)';
        } else if (compat.contains('sun50i-h6')) {
          return 'Orange Pi (H6 SoC)';
        } else if (compat.contains('sun50i-a64')) {
          return 'Orange Pi (A64 SoC)';
        } else if (compat.contains('rk3399')) {
          return 'Orange Pi RK3399';
        }
      }
    } catch (e) {
      logger.warning('Failed to detect Orange Pi model: $e');
    }

    return 'Orange Pi (Unknown Model)';
  }

  Future<void> _checkSocFeatures() async {
    try {
      // Check SoC specific features
      final compatFile = File('/proc/device-tree/compatible');
      if (await compatFile.exists()) {
        final compat = await compatFile.readAsString();
        
        if (compat.contains('sun8i-h3') || compat.contains('sun50i-h5')) {
          logger.info('H3/H5 SoC detected - Hardware video encoding available');
        } else if (compat.contains('sun50i-h6')) {
          logger.info('H6 SoC detected - Hardware video encoding and PCIe available');
        }
      }

      // Check for Mali GPU
      final gpuDir = Directory('/sys/devices/platform/mali');
      if (await gpuDir.exists()) {
        logger.info('Mali GPU detected');
      }
    } catch (e) {
      logger.fine('Failed to check SoC features: $e');
    }
  }

  Future<void> _checkThermalZones() async {
    try {
      final thermalDir = Directory('/sys/class/thermal');
      if (await thermalDir.exists()) {
        final zones = await thermalDir
            .list()
            .where((e) => e.path.contains('thermal_zone'))
            .toList();
        
        for (final zone in zones) {
          final tempFile = File('${zone.path}/temp');
          if (await tempFile.exists()) {
            final temp = await tempFile.readAsString();
            final celsius = int.parse(temp.trim()) / 1000;
            logger.info('${zone.path}: ${celsius}°C');
          }
        }
      }
    } catch (e) {
      logger.fine('Failed to check thermal zones: $e');
    }
  }

  @override
  Future<void> enableInterface(String interface) async {
    try {
      switch (interface.toLowerCase()) {
        case 'i2c':
          await _enableI2C();
          break;
        case 'spi':
          await _enableSPI();
          break;
        case 'uart':
          await _enableUART();
          break;
        case 'pwm':
          await _enablePWM();
          break;
        default:
          await super.enableInterface(interface);
      }
    } catch (e) {
      logger.severe('Failed to enable $interface: $e');
      rethrow;
    }
  }

  Future<void> _enableI2C() async {
    logger.info('Enabling I2C interface on Orange Pi');
    logger.warning('Use armbian-config or edit /boot/armbianEnv.txt');
    logger.info('Add overlay: overlays=i2c0 i2c1');
  }

  Future<void> _enableSPI() async {
    logger.info('Enabling SPI interface on Orange Pi');
    logger.warning('Use armbian-config or edit /boot/armbianEnv.txt');
    logger.info('Add overlay: overlays=spi-spidev');
  }

  Future<void> _enableUART() async {
    logger.info('Enabling UART interface on Orange Pi');
    logger.warning('Use armbian-config or edit /boot/armbianEnv.txt');
    logger.info('Add overlay: overlays=uart1 uart2');
  }

  Future<void> _enablePWM() async {
    logger.info('Enabling PWM interface on Orange Pi');
    logger.warning('Use armbian-config or edit /boot/armbianEnv.txt');
    logger.info('Add overlay: overlays=pwm');
  }
}