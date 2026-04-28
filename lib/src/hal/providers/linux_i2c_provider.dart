/// Linux I2C provider using sysfs interface
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import '../../types/hardware_types.dart';
import '../hal_interface.dart';
import '../../errors/flow_errors.dart';

/// Linux I2C bus implementation
class LinuxI2cBus implements I2cBus {
  final int _bus;
  final RandomAccessFile _device;
  final Logger _logger = Logger('LinuxI2cBus');
  
  LinuxI2cBus(this._bus, this._device);
  
  @override
  int get bus => _bus;
  
  @override
  Future<Uint8List> read(int address, int length) async {
    try {
      // In real implementation, would use ioctl to set I2C_SLAVE
      // For now, simplified version
      final buffer = Uint8List(length);
      await _device.readInto(buffer);
      return buffer;
    } catch (e) {
      throw HardwareError(
        'Failed to read from I2C device 0x${address.toRadixString(16)}: $e',
        resourceId: 'i2c$_bus',
        resourceType: 'i2c',
      );
    }
  }
  
  @override
  Future<void> write(int address, Uint8List data) async {
    try {
      // In real implementation, would use ioctl to set I2C_SLAVE
      await _device.writeFrom(data);
    } catch (e) {
      throw HardwareError(
        'Failed to write to I2C device 0x${address.toRadixString(16)}: $e',
        resourceId: 'i2c$_bus',
        resourceType: 'i2c',
      );
    }
  }
  
  @override
  Future<Uint8List> readRegister(int address, int register, int length) async {
    try {
      // Write register address then read
      await write(address, Uint8List.fromList([register]));
      return await read(address, length);
    } catch (e) {
      throw HardwareError(
        'Failed to read register 0x${register.toRadixString(16)} from device 0x${address.toRadixString(16)}: $e',
        resourceId: 'i2c$_bus',
        resourceType: 'i2c',
      );
    }
  }
  
  @override
  Future<void> writeRegister(int address, int register, Uint8List data) async {
    try {
      // Write register address followed by data
      final buffer = Uint8List(1 + data.length);
      buffer[0] = register;
      buffer.setRange(1, buffer.length, data);
      await write(address, buffer);
    } catch (e) {
      throw HardwareError(
        'Failed to write register 0x${register.toRadixString(16)} to device 0x${address.toRadixString(16)}: $e',
        resourceId: 'i2c$_bus',
        resourceType: 'i2c',
      );
    }
  }
  
  @override
  Future<void> close() async {
    await _device.close();
  }
}

/// Linux I2C provider implementation
class LinuxI2cProvider implements I2cProvider {
  final Logger _logger = Logger('LinuxI2cProvider');
  final Map<int, LinuxI2cBus> _openBuses = {};
  bool _isReady = false;
  
  @override
  String get name => 'Linux I2C';

  @override
  String get version => '1.0.0';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.i2c};

  @override
  bool get isReady => _isReady;

  @override
  Map<String, dynamic> get capabilities => {
    'maxBusses': 10,
    'maxSpeed': 400000, // 400 kHz
    'supports10Bit': false,
  };

  @override
  List<int> get availableBuses {
    final busses = <int>[];
    // Check for available I2C busses
    for (int i = 0; i < 10; i++) {
      final device = File('/dev/i2c-$i');
      if (device.existsSync()) {
        busses.add(i);
      }
    }
    return busses;
  }

  @override
  Future<void> initialize() async {
    // Check if I2C is available
    final busses = availableBuses;
    if (busses.isEmpty) {
      throw HardwareError(
        'No I2C busses found. Is I2C enabled?',
        resourceId: 'i2c',
        resourceType: 'i2c',
      );
    }
    _isReady = true;
    _logger.info('Linux I2C provider initialized with ${busses.length} busses');
  }

  @override
  Future<void> dispose() async {
    // Close all open buses
    for (final bus in _openBuses.values) {
      await bus.close();
    }
    _openBuses.clear();
    _isReady = false;
  }
  
  @override
  Future<I2cBus> openBus(int bus) async {
    // Check if bus is already open
    if (_openBuses.containsKey(bus)) {
      return _openBuses[bus]!;
    }
    
    // Open the device
    final devicePath = '/dev/i2c-$bus';
    final file = File(devicePath);
    
    if (!await file.exists()) {
      throw HardwareError(
        'I2C bus $bus not found at $devicePath',
        resourceId: 'i2c$bus',
        resourceType: 'i2c',
      );
    }
    
    final device = await file.open();
    final i2cBus = LinuxI2cBus(bus, device);
    _openBuses[bus] = i2cBus;
    
    return i2cBus;
  }

}