/// Mock hardware providers for testing and simulation

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../types/hardware_types.dart';
import '../../errors/flow_errors.dart';
import '../hal_interface.dart';

/// Base mock provider
abstract class MockProvider extends HardwareProvider {
  final bool limitedMode;
  bool _ready = false;

  MockProvider({this.limitedMode = false});

  @override
  String get version => '1.0.0-mock';

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() async {
    // Removed wall-clock delay placeholder — Flutter widget tests run in a
    // FakeAsync zone where this would stall `pumpWidget` indefinitely.
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    _ready = false;
  }

  @override
  Map<String, dynamic> get capabilities => {
        'mock': true,
        'limitedMode': limitedMode,
      };
}

/// Mock GPIO provider
class MockGpioProvider extends MockProvider implements GpioProvider {
  final Map<int, GpioConfig> _configs = {};
  final Map<int, bool> _values = {};
  final Map<int, StreamController<bool>> _interrupts = {};

  MockGpioProvider({super.limitedMode});

  @override
  String get name => 'Mock GPIO';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.gpio};

  @override
  List<int> get availablePins => List.generate(40, (i) => i);

  @override
  Future<void> configurePin(GpioConfig config) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'gpio', resourceType: 'gpio');
    
    _configs[config.pin] = config;
    if (config.mode == GpioMode.output) {
      _values[config.pin] = config.initialValue;
    }
  }

  @override
  Future<bool> readPin(int pin) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'gpio', resourceType: 'gpio');
    
    final config = _configs[pin];
    if (config == null) {
      throw HardwareError('Pin $pin not configured', resourceId: pin.toString(), resourceType: 'gpio');
    }
    
    if (config.mode == GpioMode.output) {
      return _values[pin] ?? false;
    }
    
    // Simulate random input for testing
    return Random().nextBool();
  }

  @override
  Future<void> writePin(int pin, bool value) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'gpio', resourceType: 'gpio');
    
    final config = _configs[pin];
    if (config == null) {
      throw HardwareError('Pin $pin not configured', resourceId: pin.toString(), resourceType: 'gpio');
    }
    
    if (config.mode != GpioMode.output) {
      throw HardwareError('Pin $pin is not configured as output', resourceId: pin.toString(), resourceType: 'gpio');
    }
    
    _values[pin] = value;
  }

  @override
  Future<void> setInterruptHandler(
    int pin,
    GpioInterrupt trigger,
    void Function(bool value) handler,
  ) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'gpio', resourceType: 'gpio');
    
    final controller = StreamController<bool>.broadcast();
    _interrupts[pin] = controller;
    
    controller.stream.listen(handler);
    
    // Simulate interrupts for testing
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_interrupts.containsKey(pin)) {
        timer.cancel();
        return;
      }
      controller.add(Random().nextBool());
    });
  }

  @override
  Future<void> removeInterruptHandler(int pin) async {
    await _interrupts[pin]?.close();
    _interrupts.remove(pin);
  }
}

/// Mock I2C provider
class MockI2cProvider extends MockProvider implements I2cProvider {
  MockI2cProvider({super.limitedMode});

  @override
  String get name => 'MockI2C';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.i2c};

  @override
  List<int> get availableBuses => [0, 1];

  @override
  Future<I2cBus> openBus(int bus) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'i2c', resourceType: 'i2c');
    
    if (!availableBuses.contains(bus)) {
      throw HardwareError('I2C bus $bus not available', resourceId: bus.toString(), resourceType: 'i2c');
    }
    
    return MockI2cBus(bus);
  }
}

/// Mock I2C bus
class MockI2cBus implements I2cBus {
  @override
  final int bus;
  final Map<int, Map<int, int>> _registers = {};

  MockI2cBus(this.bus);

  @override
  Future<Uint8List> read(int address, int length) async {
    // Simulate device data
    return Uint8List.fromList(
      List.generate(length, (i) => Random().nextInt(256)),
    );
  }

  @override
  Future<void> write(int address, Uint8List data) async {
    // Simulate write delay
    await Future.delayed(const Duration(microseconds: 100));
  }

  @override
  Future<Uint8List> readRegister(int address, int register, int length) async {
    final deviceRegs = _registers[address] ?? {};
    final data = <int>[];
    
    for (int i = 0; i < length; i++) {
      data.add(deviceRegs[register + i] ?? Random().nextInt(256));
    }
    
    return Uint8List.fromList(data);
  }

  @override
  Future<void> writeRegister(int address, int register, Uint8List data) async {
    final deviceRegs = _registers[address] ??= {};
    
    for (int i = 0; i < data.length; i++) {
      deviceRegs[register + i] = data[i];
    }
    
    await Future.delayed(const Duration(microseconds: 100));
  }

  @override
  Future<void> close() async {
    // Nothing to close in mock
  }
}

/// Mock SPI provider
class MockSpiProvider extends MockProvider implements SpiProvider {
  MockSpiProvider({super.limitedMode});

  @override
  String get name => 'MockSPI';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.spi};

  @override
  List<int> get availableDevices => [0, 1];

  @override
  Future<SpiDevice> openDevice(SpiConfig config) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'spi', resourceType: 'spi');
    
    if (!availableDevices.contains(config.device)) {
      throw HardwareError('SPI device ${config.device} not available', 
        resourceId: config.device.toString(), 
        resourceType: 'spi'
      );
    }
    
    return MockSpiDevice(config);
  }
}

/// Mock SPI device
class MockSpiDevice implements SpiDevice {
  @override
  final SpiConfig config;

  MockSpiDevice(this.config);

  @override
  Future<Uint8List> transfer(Uint8List data) async {
    // Simulate SPI transfer with random response
    await Future.delayed(Duration(microseconds: data.length * 10));
    return Uint8List.fromList(
      List.generate(data.length, (i) => Random().nextInt(256)),
    );
  }

  @override
  Future<void> write(Uint8List data) async {
    await Future.delayed(Duration(microseconds: data.length * 10));
  }

  @override
  Future<Uint8List> read(int length) async {
    return transfer(Uint8List(length));
  }

  @override
  Future<void> close() async {
    // Nothing to close in mock
  }
}

/// Mock PWM provider
class MockPwmProvider extends MockProvider implements PwmProvider {
  final Map<int, PwmConfig> _configs = {};
  final Map<int, double> _dutyCycles = {};
  final Map<int, bool> _enabled = {};

  MockPwmProvider({super.limitedMode});

  @override
  String get name => 'MockPWM';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.pwm};

  @override
  List<int> get availableChannels => List.generate(8, (i) => i);

  @override
  Future<void> configureChannel(PwmConfig config) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'pwm', resourceType: 'pwm');
    
    _configs[config.channel] = config;
    _dutyCycles[config.channel] = config.dutyPercent;
    _enabled[config.channel] = true;
  }

  @override
  Future<void> setDutyCycle(int channel, double dutyCycle) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'pwm', resourceType: 'pwm');
    
    if (!_configs.containsKey(channel)) {
      throw HardwareError('PWM channel $channel not configured', 
        resourceId: channel.toString(), 
        resourceType: 'pwm'
      );
    }
    
    _dutyCycles[channel] = dutyCycle.clamp(0.0, 1.0);
  }

  @override
  Future<void> setFrequency(int channel, double frequency) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'pwm', resourceType: 'pwm');
    
    final config = _configs[channel];
    if (config == null) {
      throw HardwareError('PWM channel $channel not configured', 
        resourceId: channel.toString(), 
        resourceType: 'pwm'
      );
    }
    
    _configs[channel] = PwmConfig(
      channel: channel,
      frequencyHz: frequency,
      dutyPercent: _dutyCycles[channel] ?? 0.0,
    );
  }

  @override
  Future<void> setEnabled(int channel, bool enabled) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'pwm', resourceType: 'pwm');
    
    if (!_configs.containsKey(channel)) {
      throw HardwareError('PWM channel $channel not configured', 
        resourceId: channel.toString(), 
        resourceType: 'pwm'
      );
    }
    
    _enabled[channel] = enabled;
  }
}

/// Mock UART provider
class MockUartProvider extends MockProvider implements UartProvider {
  MockUartProvider({super.limitedMode});

  @override
  String get name => 'MockUART';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.uart};

  @override
  List<String> get availablePorts => ['/dev/ttyUSB0', '/dev/ttyUSB1', 'COM1', 'COM2'];

  @override
  Future<UartPort> openPort(UartConfig config) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'uart', resourceType: 'uart');
    
    if (!availablePorts.contains(config.port)) {
      throw HardwareError('UART port ${config.port} not available', 
        resourceId: config.port, 
        resourceType: 'uart'
      );
    }
    
    return MockUartPort(config);
  }
}

/// Mock UART port
class MockUartPort implements UartPort {
  @override
  final UartConfig config;
  final _dataController = StreamController<Uint8List>.broadcast();

  MockUartPort(this.config) {
    // Simulate incoming data
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_dataController.isClosed) {
        timer.cancel();
        return;
      }
      
      final message = 'Mock data ${DateTime.now().millisecondsSinceEpoch}\n';
      _dataController.add(Uint8List.fromList(message.codeUnits));
    });
  }

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Future<void> write(Uint8List data) async {
    // Simulate write delay
    await Future.delayed(Duration(microseconds: data.length * 100));
  }

  @override
  Future<void> writeString(String data) async {
    await write(Uint8List.fromList(data.codeUnits));
  }

  @override
  Future<void> close() async {
    await _dataController.close();
  }
}

/// Mock ADC provider
class MockAdcProvider extends MockProvider implements AdcProvider {
  final Map<int, AdcConfig> _configs = {};

  MockAdcProvider({super.limitedMode});

  @override
  String get name => 'MockADC';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.adc};

  @override
  List<int> get availableChannels => List.generate(8, (i) => i);

  @override
  Future<void> configureChannel(AdcConfig config) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'adc', resourceType: 'adc');
    
    _configs[config.channel] = config;
  }

  @override
  Future<int> readRaw(int channel) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'adc', resourceType: 'adc');
    
    final config = _configs[channel];
    if (config == null) {
      throw HardwareError('ADC channel $channel not configured', 
        resourceId: channel.toString(), 
        resourceType: 'adc'
      );
    }
    
    final maxValue = (1 << config.resolution) - 1;
    return Random().nextInt(maxValue + 1);
  }

  @override
  Future<double> readVoltage(int channel) async {
    final config = _configs[channel];
    if (config == null) {
      throw HardwareError('ADC channel $channel not configured', 
        resourceId: channel.toString(), 
        resourceType: 'adc'
      );
    }
    
    final raw = await readRaw(channel);
    final maxValue = (1 << config.resolution) - 1;
    return (raw / maxValue) * config.referenceVoltage;
  }

  @override
  Future<double> readAveraged(int channel, int samples) async {
    double sum = 0;
    for (int i = 0; i < samples; i++) {
      sum += await readVoltage(channel);
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return sum / samples;
  }
}

/// Mock Modbus provider
class MockModbusProvider extends MockProvider implements ModbusProvider {
  MockModbusProvider({super.limitedMode});

  @override
  String get name => 'MockModbus';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.modbus};

  @override
  Future<ModbusClient> connect(ModbusConfig config) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'modbus', resourceType: 'modbus');
    
    await Future.delayed(const Duration(milliseconds: 500)); // Simulate connection
    return MockModbusClient(config);
  }
}

/// Mock Modbus client
class MockModbusClient implements ModbusClient {
  @override
  final ModbusConfig config;
  bool _connected = true;
  final Map<int, Map<int, bool>> _coils = {};
  final Map<int, Map<int, int>> _registers = {};

  MockModbusClient(this.config);

  @override
  bool get isConnected => _connected;

  @override
  Future<List<bool>> readCoils(int unitId, int address, int count) async {
    if (!isConnected) throw const HardwareError('Not connected', resourceId: 'modbus', resourceType: 'modbus');
    
    final unitCoils = _coils[unitId] ?? {};
    return List.generate(count, (i) => unitCoils[address + i] ?? false);
  }

  @override
  Future<List<bool>> readDiscreteInputs(int unitId, int address, int count) async {
    // Simulate random discrete inputs
    return List.generate(count, (_) => Random().nextBool());
  }

  @override
  Future<Uint16List> readHoldingRegisters(int unitId, int address, int count) async {
    if (!isConnected) throw const HardwareError('Not connected', resourceId: 'modbus', resourceType: 'modbus');
    
    final unitRegs = _registers[unitId] ?? {};
    return Uint16List.fromList(
      List.generate(count, (i) => unitRegs[address + i] ?? Random().nextInt(65536)),
    );
  }

  @override
  Future<Uint16List> readInputRegisters(int unitId, int address, int count) async {
    // Simulate random input registers
    return Uint16List.fromList(
      List.generate(count, (_) => Random().nextInt(65536)),
    );
  }

  @override
  Future<void> writeSingleCoil(int unitId, int address, bool value) async {
    if (!isConnected) throw const HardwareError('Not connected', resourceId: 'modbus', resourceType: 'modbus');
    
    final unitCoils = _coils[unitId] ??= {};
    unitCoils[address] = value;
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> writeSingleRegister(int unitId, int address, int value) async {
    if (!isConnected) throw const HardwareError('Not connected', resourceId: 'modbus', resourceType: 'modbus');
    
    final unitRegs = _registers[unitId] ??= {};
    unitRegs[address] = value & 0xFFFF;
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> writeMultipleCoils(int unitId, int address, List<bool> values) async {
    if (!isConnected) throw const HardwareError('Not connected', resourceId: 'modbus', resourceType: 'modbus');
    
    final unitCoils = _coils[unitId] ??= {};
    for (int i = 0; i < values.length; i++) {
      unitCoils[address + i] = values[i];
    }
    await Future.delayed(Duration(milliseconds: 10 * values.length));
  }

  @override
  Future<void> writeMultipleRegisters(int unitId, int address, Uint16List values) async {
    if (!isConnected) throw const HardwareError('Not connected', resourceId: 'modbus', resourceType: 'modbus');
    
    final unitRegs = _registers[unitId] ??= {};
    for (int i = 0; i < values.length; i++) {
      unitRegs[address + i] = values[i];
    }
    await Future.delayed(Duration(milliseconds: 10 * values.length));
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

/// Mock DAC provider for testing
class MockDacProvider extends MockProvider implements DacProvider {
  final Map<int, DacConfig> _configs = {};
  final Map<int, int> _rawValues = {};
  final Map<int, double> _voltages = {};
  final Map<int, bool> _enabled = {};

  MockDacProvider({super.limitedMode = false});

  @override
  String get name => 'MockDAC';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.dac};

  @override
  Future<void> configureChannel(DacConfig config) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'dac', resourceType: 'dac');
    _configs[config.channel] = config;
    _rawValues[config.channel] = 0;
    _voltages[config.channel] = 0.0;
    _enabled[config.channel] = false;
  }

  @override
  Future<void> writeRaw(int channel, int value) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'dac', resourceType: 'dac');
    if (!_configs.containsKey(channel)) {
      throw HardwareError('DAC channel $channel not configured', resourceId: channel.toString(), resourceType: 'dac');
    }
    _rawValues[channel] = value;
  }

  @override
  Future<void> writeVoltage(int channel, double voltage) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'dac', resourceType: 'dac');
    if (!_configs.containsKey(channel)) {
      throw HardwareError('DAC channel $channel not configured', resourceId: channel.toString(), resourceType: 'dac');
    }
    _voltages[channel] = voltage;
  }

  @override
  Future<void> setOutputEnabled(int channel, bool enabled) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'dac', resourceType: 'dac');
    _enabled[channel] = enabled;
  }

  @override
  List<int> get availableChannels => _configs.keys.toList();
}

/// Mock Timer provider for testing
class MockTimerProvider extends MockProvider implements TimerProvider {
  int _nextTimerId = 1;
  final Map<int, Timer> _timers = {};

  MockTimerProvider({super.limitedMode = false});

  @override
  String get name => 'MockTimer';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.timer};

  @override
  Future<int> start(Duration duration, void Function() callback, {bool periodic = false}) async {
    if (!isReady) throw const HardwareError('Provider not ready', resourceId: 'timer', resourceType: 'timer');
    final id = _nextTimerId++;
    if (periodic) {
      _timers[id] = Timer.periodic(duration, (_) => callback());
    } else {
      _timers[id] = Timer(duration, () {
        callback();
        _timers.remove(id);
      });
    }
    return id;
  }

  @override
  Future<void> stop(int timerId) async {
    final timer = _timers.remove(timerId);
    timer?.cancel();
  }

  @override
  bool isRunning(int timerId) => _timers.containsKey(timerId) && _timers[timerId]!.isActive;

  @override
  Future<void> dispose() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    await super.dispose();
  }
}