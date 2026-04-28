/// Linux SPI provider using spidev interface
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import '../../types/hardware_types.dart';
import '../hal_interface.dart';
import '../../errors/flow_errors.dart';

/// Linux SPI device implementation
class LinuxSpiDevice implements SpiDevice {
  final int _bus;
  final RandomAccessFile _file;
  final SpiConfig _config;
  
  LinuxSpiDevice(this._bus, this._file, this._config);
  
  @override
  SpiConfig get config => _config;
  
  @override
  Future<Uint8List> transfer(Uint8List data) async {
    try {
      // In a real implementation, would use ioctl SPI_IOC_MESSAGE
      // For now, simplified version
      final result = Uint8List(data.length);
      await _file.writeFrom(data);
      await _file.readInto(result);
      return result;
    } catch (e) {
      throw HardwareError(
        'SPI transfer failed on bus $_bus device ${_config.device}: $e',
        resourceId: 'spi$_bus.${_config.device}',
        resourceType: 'spi',
      );
    }
  }
  
  @override
  Future<void> write(Uint8List data) async {
    try {
      await _file.writeFrom(data);
    } catch (e) {
      throw HardwareError(
        'SPI write failed on bus $_bus device ${_config.device}: $e',
        resourceId: 'spi$_bus.${_config.device}',
        resourceType: 'spi',
      );
    }
  }
  
  @override
  Future<Uint8List> read(int length) async {
    try {
      // Send zeros and read response
      final zeros = Uint8List(length);
      return await transfer(zeros);
    } catch (e) {
      throw HardwareError(
        'SPI read failed on bus $_bus device ${_config.device}: $e',
        resourceId: 'spi$_bus.${_config.device}',
        resourceType: 'spi',
      );
    }
  }
  
  @override
  Future<void> close() async {
    await _file.close();
  }
}

/// Linux SPI provider implementation
class LinuxSpiProvider implements SpiProvider {
  final Logger _logger = Logger('LinuxSpiProvider');
  final Map<String, LinuxSpiDevice> _openDevices = {};
  bool _isReady = false;
  
  @override
  String get name => 'Linux SPI (spidev)';

  @override
  String get version => '1.0.0';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.spi};

  @override
  bool get isReady => _isReady;

  @override
  Map<String, dynamic> get capabilities => {
    'maxSpeed': 50000000, // 50 MHz
    'modes': ['mode0', 'mode1', 'mode2', 'mode3'],
    'bitsPerWord': [8, 16],
  };

  @override
  List<int> get availableDevices {
    final devices = <int>[];
    
    // Check for available SPI devices (return unique device numbers)
    for (int bus = 0; bus < 5; bus++) {
      for (int dev = 0; dev < 3; dev++) {
        final device = File('/dev/spidev$bus.$dev');
        if (device.existsSync()) {
          // Add unique identifier (bus * 10 + device)
          devices.add(bus * 10 + dev);
        }
      }
    }
    
    return devices;
  }

  @override
  Future<void> initialize() async {
    // Check if SPI is available
    final devices = availableDevices;
    if (devices.isEmpty) {
      throw HardwareError(
        'No SPI devices found. Is SPI enabled?',
        resourceId: 'spi',
        resourceType: 'spi',
      );
    }
    _isReady = true;
    _logger.info('Linux SPI provider initialized with ${devices.length} devices');
  }

  @override
  Future<void> dispose() async {
    // Close all open devices
    for (final device in _openDevices.values) {
      await device.close();
    }
    _openDevices.clear();
    _isReady = false;
  }

  @override
  Future<SpiDevice> openDevice(SpiConfig config) async {
    // Extract bus and device from the device number
    // We use convention: device = bus * 10 + device_num
    final bus = config.device ~/ 10;
    final deviceNum = config.device % 10;
    final key = '$bus.$deviceNum';
    
    // Check if device is already open
    if (_openDevices.containsKey(key)) {
      return _openDevices[key]!;
    }
    
    // Open the device
    final devicePath = '/dev/spidev$bus.$deviceNum';
    final file = File(devicePath);
    
    if (!await file.exists()) {
      throw HardwareError(
        'SPI device not found at $devicePath',
        resourceId: 'spi$bus.$deviceNum',
        resourceType: 'spi',
      );
    }
    
    final randomFile = await file.open();
    
    // In a real implementation, would configure the device using ioctl:
    // - SPI_IOC_WR_MODE for mode
    // - SPI_IOC_WR_BITS_PER_WORD for bits
    // - SPI_IOC_WR_MAX_SPEED_HZ for speed
    
    final device = LinuxSpiDevice(bus, randomFile, config);
    _openDevices[key] = device;
    
    _logger.info('Opened SPI device $bus.$deviceNum');
    return device;
  }
}