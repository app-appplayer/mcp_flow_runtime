/// Raspberry Pi specific HAL implementation
import 'dart:io';
import 'embedded_linux_hal.dart';
import '../providers/mock_provider.dart';

/// Raspberry Pi hardware abstraction layer
class RaspberryPiHal extends EmbeddedLinuxHal {
  String? _cachedPiModel;

  RaspberryPiHal({Map<String, dynamic>? config}) 
    : super(loggerName: 'RaspberryPiHal', config: config);

  @override
  Future<String> getBoardModel() async {
    if (_cachedPiModel != null) return _cachedPiModel!;
    _cachedPiModel = await _detectRaspberryPiModel();
    return _cachedPiModel!;
  }

  @override
  List<int> getGpioPins() {
    // BCM GPIO pins available on most Pi models
    // This covers 40-pin header models (Pi 2, 3, 4, Zero W, etc.)
    return [
      2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
      21, 22, 23, 24, 25, 26, 27
    ];
  }

  @override
  List<int> getI2cBuses() {
    // Standard I2C buses on Raspberry Pi
    return [0, 1]; // I2C-0 (usually for HAT EEPROM) and I2C-1 (user accessible)
  }

  @override
  List<int> getSpiBuses() {
    // Standard SPI buses on Raspberry Pi
    return [0, 1]; // SPI0 and SPI1 (Pi 4 has up to 6 SPI)
  }

  @override
  List<String> getUartDevices() {
    // Common UART devices on Raspberry Pi
    return ['/dev/ttyAMA0', '/dev/ttyS0', '/dev/serial0', '/dev/serial1'];
  }

  @override
  Future<bool> isDetected() async {
    try {
      // Check for Raspberry Pi specific files
      final deviceTreeModel = File('/proc/device-tree/model');
      if (await deviceTreeModel.exists()) {
        final model = await deviceTreeModel.readAsString();
        return model.contains('Raspberry Pi');
      }

      // Check CPU info for BCM processor
      final cpuInfo = File('/proc/cpuinfo');
      if (await cpuInfo.exists()) {
        final info = await cpuInfo.readAsString();
        return info.contains('BCM');
      }
    } catch (e) {
      logger.fine('Failed to detect Raspberry Pi: $e');
    }
    return false;
  }

  @override
  Future<void> initializeBoardSpecific() async {
    logger.info('Initializing Raspberry Pi specific features');

    // Check for Pi Camera
    await _checkPiCamera();

    // Check for HAT EEPROM
    await _checkHatEeprom();

    // Register Modbus provider (often used with Pi in industrial settings)
    registerProvider(MockModbusProvider());
  }

  Future<String> _detectRaspberryPiModel() async {
    try {
      // Try to read from device tree
      final deviceTreeModel = File('/proc/device-tree/model');
      if (await deviceTreeModel.exists()) {
        final model = await deviceTreeModel.readAsString();
        return model.trim();
      }

      // Try to read from cpuinfo
      final cpuInfo = File('/proc/cpuinfo');
      if (await cpuInfo.exists()) {
        final content = await cpuInfo.readAsString();
        final revisionMatch = RegExp(r'Revision\s*:\s*([a-fA-F0-9]+)').firstMatch(content);
        if (revisionMatch != null) {
          final revision = revisionMatch.group(1)!;
          return _getModelFromRevision(revision);
        }
      }
    } catch (e) {
      logger.warning('Failed to detect Pi model: $e');
    }

    return 'Raspberry Pi (Unknown Model)';
  }

  String _getModelFromRevision(String revision) {
    // Simplified model detection based on revision
    final rev = int.tryParse(revision, radix: 16) ?? 0;
    
    if (rev >= 0xa02082 && rev <= 0xa22082) {
      return 'Raspberry Pi 3 Model B';
    } else if (rev >= 0xa03111 && rev <= 0xc03111) {
      return 'Raspberry Pi 4 Model B';
    } else if (rev >= 0x900092 && rev <= 0x900093) {
      return 'Raspberry Pi Zero';
    } else if (rev >= 0x9000c1) {
      return 'Raspberry Pi Zero W';
    } else if (rev >= 0xa01040 && rev <= 0xa21041) {
      return 'Raspberry Pi 2 Model B';
    } else if (rev >= 0x0002 && rev <= 0x0015) {
      return 'Raspberry Pi Model B';
    } else {
      return 'Raspberry Pi (Model $revision)';
    }
  }

  Future<void> _checkPiCamera() async {
    try {
      // Check for camera modules
      final vcgencmd = await Process.run('vcgencmd', ['get_camera']);
      if (vcgencmd.exitCode == 0) {
        final output = vcgencmd.stdout.toString();
        if (output.contains('detected=1')) {
          logger.info('Raspberry Pi Camera detected');
        }
      }
    } catch (e) {
      logger.fine('Failed to check Pi Camera: $e');
    }
  }

  Future<void> _checkHatEeprom() async {
    try {
      // Check for HAT EEPROM
      final hatEeprom = File('/proc/device-tree/hat/product');
      if (await hatEeprom.exists()) {
        final product = await hatEeprom.readAsString();
        logger.info('HAT detected: $product');
      }
    } catch (e) {
      logger.fine('Failed to check HAT EEPROM: $e');
    }
  }

  /// Enable specific hardware interfaces (requires root privileges)
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
        default:
          throw ArgumentError('Unknown interface: $interface');
      }
    } catch (e) {
      logger.severe('Failed to enable $interface: $e');
      rethrow;
    }
  }

  Future<void> _enableI2C() async {
    logger.info('Enabling I2C interface');
    // This would typically require modifying /boot/config.txt and loading modules
    // For now, just log the action
    logger.warning('I2C enabling requires manual configuration in /boot/config.txt');
    logger.info('Add "dtparam=i2c_arm=on" to /boot/config.txt and reboot');
  }

  Future<void> _enableSPI() async {
    logger.info('Enabling SPI interface');
    // This would typically require modifying /boot/config.txt and loading modules
    logger.warning('SPI enabling requires manual configuration in /boot/config.txt');
    logger.info('Add "dtparam=spi=on" to /boot/config.txt and reboot');
  }

  Future<void> _enableUART() async {
    logger.info('Enabling UART interface');
    // This would typically require modifying /boot/config.txt
    logger.warning('UART enabling requires manual configuration in /boot/config.txt');
    logger.info('Add "enable_uart=1" to /boot/config.txt and reboot');
  }
}