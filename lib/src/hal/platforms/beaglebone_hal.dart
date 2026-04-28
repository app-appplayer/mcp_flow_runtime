/// BeagleBone specific HAL implementation
import 'dart:io';
import 'embedded_linux_hal.dart';
import '../providers/mock_provider.dart';

/// BeagleBone (Black/Green/Blue) hardware abstraction layer
class BeagleBoneHal extends EmbeddedLinuxHal {
  String? _cachedBoardModel;

  BeagleBoneHal({Map<String, dynamic>? config}) 
    : super(loggerName: 'BeagleBoneHal', config: config);

  @override
  Future<String> getBoardModel() async {
    if (_cachedBoardModel != null) return _cachedBoardModel!;
    _cachedBoardModel = await _detectBeagleBoneModel();
    return _cachedBoardModel!;
  }

  @override
  List<int> getGpioPins() {
    // BeagleBone has 4 GPIO banks (32 pins each)
    // Return commonly used pins from P8 and P9 headers
    return [
      // P8 header GPIOs
      38, 39, 34, 35, 66, 67, 69, 68, 45, 44, 23, 26, 47, 46, 27, 65, 22, 63, 62, 37, 36, 33, 32, 61, 86, 88, 87, 89, 10, 11, 9, 81, 8, 80, 78, 79, 76, 77, 74, 75, 72, 73, 70, 71,
      // P9 header GPIOs
      30, 60, 31, 50, 48, 51, 5, 4, 13, 12, 3, 2, 49, 15, 117, 14, 115, 113, 111, 112, 110, 20, 7
    ];
  }

  @override
  List<int> getI2cBuses() {
    // BeagleBone has 3 I2C buses (0, 1, 2)
    return [0, 1, 2];
  }

  @override
  List<int> getSpiBuses() {
    // BeagleBone has 2 SPI buses (0, 1)
    return [0, 1];
  }

  @override
  List<String> getUartDevices() {
    // BeagleBone UART devices
    return [
      '/dev/ttyO0', // UART0 (console)
      '/dev/ttyO1', // UART1
      '/dev/ttyO2', // UART2
      '/dev/ttyO3', // UART3
      '/dev/ttyO4', // UART4
      '/dev/ttyO5', // UART5
      '/dev/ttyS0', // Alternative naming
      '/dev/ttyS1',
      '/dev/ttyS2',
      '/dev/ttyS3',
      '/dev/ttyS4',
      '/dev/ttyS5'
    ];
  }

  @override
  Future<bool> isDetected() async {
    try {
      // Check for BeagleBone specific files
      final boardName = File('/sys/devices/platform/bone_capemgr/baseboard/board-name');
      if (await boardName.exists()) {
        return true;
      }

      // Check device tree model
      final deviceTreeModel = File('/proc/device-tree/model');
      if (await deviceTreeModel.exists()) {
        final model = await deviceTreeModel.readAsString();
        return model.contains('BeagleBone') || model.contains('TI AM335x');
      }

      // Check CPU info for AM335x processor
      final cpuInfo = File('/proc/cpuinfo');
      if (await cpuInfo.exists()) {
        final info = await cpuInfo.readAsString();
        return info.contains('AM33');
      }
    } catch (e) {
      logger.fine('Failed to detect BeagleBone: $e');
    }
    return false;
  }

  @override
  Future<void> initializeBoardSpecific() async {
    logger.info('Initializing BeagleBone specific features');

    // Check for capes (expansion boards)
    await _checkCapes();

    // Initialize PRU if available
    await _checkPru();

    // Register ADC provider (BeagleBone has built-in ADCs)
    registerProvider(MockAdcProvider());
    
    // Register Modbus provider
    registerProvider(MockModbusProvider());
  }

  Future<String> _detectBeagleBoneModel() async {
    try {
      // Try board-name first
      final boardName = File('/sys/devices/platform/bone_capemgr/baseboard/board-name');
      if (await boardName.exists()) {
        final name = await boardName.readAsString();
        return name.trim();
      }

      // Try device tree
      final deviceTreeModel = File('/proc/device-tree/model');
      if (await deviceTreeModel.exists()) {
        final model = await deviceTreeModel.readAsString();
        return model.trim();
      }

      // Check eeprom
      final eeprom = File('/sys/bus/i2c/devices/0-0050/eeprom');
      if (await eeprom.exists()) {
        // Read board ID from EEPROM (simplified)
        return 'BeagleBone Black';
      }
    } catch (e) {
      logger.warning('Failed to detect BeagleBone model: $e');
    }

    return 'BeagleBone (Unknown Model)';
  }

  Future<void> _checkCapes() async {
    try {
      final capesDir = Directory('/sys/devices/platform/bone_capemgr/slots');
      if (await capesDir.exists()) {
        final slots = File('${capesDir.path}/slots');
        if (await slots.exists()) {
          final content = await slots.readAsString();
          logger.info('Cape slots:\n$content');
        }
      }
    } catch (e) {
      logger.fine('Failed to check capes: $e');
    }
  }

  Future<void> _checkPru() async {
    try {
      // Check if PRU (Programmable Real-time Unit) is available
      final pruDir = Directory('/sys/class/remoteproc');
      if (await pruDir.exists()) {
        final entries = await pruDir.list().toList();
        final pruDevices = entries.where((e) => e.path.contains('pru')).toList();
        if (pruDevices.isNotEmpty) {
          logger.info('PRU (Programmable Real-time Unit) available: ${pruDevices.length} cores');
        }
      }
    } catch (e) {
      logger.fine('Failed to check PRU: $e');
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
        case 'adc':
          await _enableADC();
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
    logger.info('Enabling I2C interface on BeagleBone');
    logger.warning('Use config-pin utility or device tree overlays to enable I2C pins');
    logger.info('Example: config-pin P9.17 i2c');
  }

  Future<void> _enableSPI() async {
    logger.info('Enabling SPI interface on BeagleBone');
    logger.warning('Use config-pin utility or device tree overlays to enable SPI pins');
    logger.info('Example: config-pin P9.17 spi');
  }

  Future<void> _enableUART() async {
    logger.info('Enabling UART interface on BeagleBone');
    logger.warning('Use config-pin utility or device tree overlays to enable UART pins');
    logger.info('Example: config-pin P9.24 uart');
  }

  Future<void> _enablePWM() async {
    logger.info('Enabling PWM interface on BeagleBone');
    logger.warning('Use config-pin utility or device tree overlays to enable PWM pins');
    logger.info('Example: config-pin P9.14 pwm');
  }

  Future<void> _enableADC() async {
    logger.info('Enabling ADC interface on BeagleBone');
    logger.info('ADC is usually enabled by default on BeagleBone');
    logger.info('Access via /sys/bus/iio/devices/iio:device0/');
  }
}