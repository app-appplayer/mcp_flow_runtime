/// Mock HAL factory for testing
import '../types/hardware_types.dart';
import 'hal_interface.dart';
import 'providers/mqtt_provider.dart';
import 'dart:typed_data';
import 'dart:async';

/// Mock HAL factory implementation
class MockHalFactory {
  static HardwareAbstractionLayer createMockHal() {
    return MockHardwareAbstractionLayer();
  }
}

/// Mock HAL implementation
class MockHardwareAbstractionLayer implements HardwareAbstractionLayer {
  final Map<ResourceType, HardwareProvider> _providers = {};
  
  MockHardwareAbstractionLayer() {
    // Register all mock providers
    registerProvider(MockGpioProvider());
    registerProvider(MockI2cProvider());
    registerProvider(MockSpiProvider());
    registerProvider(MockAdcProvider());
    registerProvider(MockPwmProvider());
    registerProvider(MockUartProvider());
    registerProvider(MockModbusProvider());
    registerProvider(MockDacProvider());
    registerProvider(MockTimerProvider());
    registerProvider(MockMqttProvider());
  }

  @override
  T? getProvider<T extends HardwareProvider>(ResourceType type) {
    return _providers[type] as T?;
  }

  @override
  List<HardwareProvider> get providers => _providers.values.toList();

  @override
  void registerProvider(HardwareProvider provider) {
    for (final type in provider.supportedTypes) {
      _providers[type] = provider;
    }
  }

  @override
  Map<String, dynamic> get systemInfo => {
    'platform': 'mock',
    'version': '1.0.0',
    'capabilities': _providers.keys.map((t) => t.name).toList(),
  };

  @override
  Future<void> initialize() async {
    // Mock initialization
    for (final provider in _providers.values) {
      await provider.initialize();
    }
  }

  @override
  Future<void> dispose() async {
    // Mock cleanup
    for (final provider in _providers.values) {
      await provider.dispose();
    }
  }
}

/// Mock GPIO provider
class MockGpioProvider implements GpioProvider {
  final Map<int, bool> _pinStates = {};
  final Map<int, GpioConfig> _pinConfigs = {};
  final Map<int, void Function(bool)> _interruptHandlers = {};
  bool _isReady = false;
  
  // Event callback for resource events
  void Function(String resource, String event, {dynamic data})? onResourceEvent;

  @override
  String get name => 'MockGpioProvider';
  
  @override
  String get version => '1.0.0';
  
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.gpio};
  
  @override
  Map<String, dynamic> get capabilities => {
    'digitalRead': true,
    'digitalWrite': true,
    'interrupts': true,
    'pullUp': true,
    'pullDown': true,
  };
  
  @override
  List<int> get availablePins => List.generate(40, (i) => i);

  @override
  Future<void> configurePin(GpioConfig config) async {
    _pinConfigs[config.pin] = config;
    if (config.mode == GpioMode.output) {
      _pinStates[config.pin] = config.initialValue;
    }
  }

  @override
  Future<bool> readPin(int pin) async {
    return _pinStates[pin] ?? false;
  }

  @override
  Future<void> writePin(int pin, bool value) async {
    final config = _pinConfigs[pin];
    if (config?.mode == GpioMode.output) {
      final oldValue = _pinStates[pin] ?? false;
      _pinStates[pin] = value;
      
      // Emit resource event if value changed
      if (oldValue != value && onResourceEvent != null) {
        onResourceEvent!('gpio_$pin', value ? 'high' : 'low', data: {
          'pin': pin,
          'value': value,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
  }

  @override
  Future<void> setInterruptHandler(
    int pin,
    GpioInterrupt trigger,
    void Function(bool value) handler,
  ) async {
    _interruptHandlers[pin] = handler;
  }
  
  /// Simulate a pin change for testing
  void simulatePinChange(int pin, bool value) {
    final oldValue = _pinStates[pin] ?? false;
    _pinStates[pin] = value;
    
    // Trigger interrupt handler if exists
    final handler = _interruptHandlers[pin];
    if (handler != null) {
      handler(value);
    }
    
    // Emit resource event
    if (oldValue != value && onResourceEvent != null) {
      onResourceEvent!('gpio_$pin', value ? 'high' : 'low', data: {
        'pin': pin,
        'value': value,
        'trigger': 'interrupt',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  @override
  Future<void> removeInterruptHandler(int pin) async {
    _interruptHandlers.remove(pin);
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _pinStates.clear();
    _pinConfigs.clear();
    _interruptHandlers.clear();
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;
}

/// Mock I2C provider
class MockI2cProvider implements I2cProvider {
  bool _isReady = false;

  @override
  String get name => 'MockI2cProvider';
  
  @override
  String get version => '1.0.0';
  
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.i2c};
  
  @override
  Map<String, dynamic> get capabilities => {
    'standardMode': true,
    'fastMode': true,
    'fastModePlus': true,
    'highSpeedMode': false,
  };
  
  @override
  List<int> get availableBuses => [0, 1];

  @override
  Future<I2cBus> openBus(int bus) async {
    return MockI2cBus(bus);
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;
}

/// Mock I2C bus
class MockI2cBus implements I2cBus {
  final int _bus;

  MockI2cBus(this._bus);

  @override
  int get bus => _bus;

  @override
  Future<void> write(int address, Uint8List data) async {
    // Mock write
  }

  @override
  Future<Uint8List> read(int address, int length) async {
    return Uint8List(length);
  }

  @override
  Future<void> writeRegister(int address, int register, Uint8List data) async {
    // Mock write register
  }

  @override
  Future<Uint8List> readRegister(int address, int register, int length) async {
    return Uint8List(length);
  }

  @override
  Future<void> close() async {
    // Mock close
  }
}

/// Mock SPI provider
class MockSpiProvider implements SpiProvider {
  bool _isReady = false;

  @override
  String get name => 'MockSpiProvider';
  
  @override
  String get version => '1.0.0';
  
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.spi};
  
  @override
  Map<String, dynamic> get capabilities => {
    'mode0': true,
    'mode1': true,
    'mode2': true,
    'mode3': true,
    'maxSpeed': 50000000,
  };
  
  @override
  List<int> get availableDevices => [0, 1];

  @override
  Future<SpiDevice> openDevice(SpiConfig config) async {
    return MockSpiDevice(config);
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;
}

/// Mock SPI device
class MockSpiDevice implements SpiDevice {
  final SpiConfig _config;

  MockSpiDevice(this._config);

  @override
  SpiConfig get config => _config;

  @override
  Future<Uint8List> transfer(Uint8List data) async {
    return Uint8List(data.length);
  }

  @override
  Future<void> write(Uint8List data) async {
    // Mock write
  }

  @override
  Future<Uint8List> read(int length) async {
    return Uint8List(length);
  }

  @override
  Future<void> close() async {
    // Mock close
  }
}

/// Mock ADC provider
class MockAdcProvider implements AdcProvider {
  bool _isReady = false;
  final Map<int, AdcConfig> _configs = {};

  @override
  String get name => 'MockAdcProvider';
  
  @override
  String get version => '1.0.0';
  
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.adc};
  
  @override
  Map<String, dynamic> get capabilities => {
    'resolution': 12,
    'maxChannels': 8,
    'referenceVoltage': 3.3,
  };
  
  @override
  List<int> get availableChannels => List.generate(8, (i) => i);

  @override
  Future<int> readRaw(int channel) async {
    return 2048; // Mid-range value for 12-bit ADC
  }

  @override
  Future<double> readVoltage(int channel) async {
    return 1.65; // 3.3V / 2
  }

  @override
  Future<void> configureChannel(AdcConfig config) async {
    _configs[config.channel] = config;
  }

  @override
  Future<double> readAveraged(int channel, int samples) async {
    return 1.65; // Mock averaged value
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _configs.clear();
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;
}

/// Mock PWM provider
class MockPwmProvider implements PwmProvider {
  final Map<int, double> _dutyCycles = {};
  final Map<int, double> _frequencies = {};
  final Map<int, bool> _enabled = {};
  bool _isReady = false;

  @override
  String get name => 'MockPwmProvider';
  
  @override
  String get version => '1.0.0';
  
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.pwm};
  
  @override
  Map<String, dynamic> get capabilities => {
    'maxChannels': 6,
    'resolution': 16,
    'maxFrequency': 100000,
  };
  
  @override
  List<int> get availableChannels => List.generate(6, (i) => i);

  @override
  Future<void> configureChannel(PwmConfig config) async {
    _dutyCycles[config.channel] = config.dutyPercent;
    _frequencies[config.channel] = config.frequencyHz ?? 1000.0;
    _enabled[config.channel] = true;
  }

  @override
  Future<void> setDutyCycle(int channel, double dutyCycle) async {
    _dutyCycles[channel] = dutyCycle;
  }

  @override
  Future<void> setFrequency(int channel, double frequency) async {
    _frequencies[channel] = frequency;
  }

  @override
  Future<void> setEnabled(int channel, bool enabled) async {
    _enabled[channel] = enabled;
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _dutyCycles.clear();
    _frequencies.clear();
    _enabled.clear();
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;
}

/// Mock UART provider
class MockUartProvider implements UartProvider {
  bool _isReady = false;

  @override
  String get name => 'MockUartProvider';
  
  @override
  String get version => '1.0.0';
  
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.uart};
  
  @override
  Map<String, dynamic> get capabilities => {
    'hardwareFlowControl': true,
    'softwareFlowControl': true,
    'maxBaudRate': 921600,
  };
  
  @override
  List<String> get availablePorts => ['/dev/ttyUSB0', '/dev/ttyUSB1'];

  @override
  Future<UartPort> openPort(UartConfig config) async {
    return MockUartPort(config);
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;
}

/// Mock UART port
class MockUartPort implements UartPort {
  final _controller = StreamController<Uint8List>.broadcast();
  final UartConfig _config;

  MockUartPort(this._config);

  @override
  UartConfig get config => _config;

  @override
  Stream<Uint8List> get dataStream => _controller.stream;

  @override
  Future<void> write(Uint8List data) async {
    // Mock write
  }

  @override
  Future<void> writeString(String data) async {
    // Mock write string
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

/// Mock Modbus provider
class MockModbusProvider implements ModbusProvider {
  bool _isReady = false;

  @override
  String get name => 'MockModbusProvider';
  
  @override
  String get version => '1.0.0';
  
  @override
  Set<ResourceType> get supportedTypes => {ResourceType.modbus};
  
  @override
  Map<String, dynamic> get capabilities => {
    'modbusRtu': true,
    'modbusTcp': true,
    'functionCodes': [1, 2, 3, 4, 5, 6, 15, 16],
  };

  @override
  Future<ModbusClient> connect(ModbusConfig config) async {
    return MockModbusClient(config);
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;
}

/// Mock Modbus client
class MockModbusClient implements ModbusClient {
  final ModbusConfig _config;
  bool _isConnected = true;

  MockModbusClient(this._config);

  @override
  ModbusConfig get config => _config;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<List<bool>> readCoils(int unitId, int address, int count) async {
    return List.filled(count, false);
  }

  @override
  Future<List<bool>> readDiscreteInputs(int unitId, int address, int count) async {
    return List.filled(count, false);
  }

  @override
  Future<Uint16List> readHoldingRegisters(int unitId, int address, int count) async {
    return Uint16List(count);
  }

  @override
  Future<Uint16List> readInputRegisters(int unitId, int address, int count) async {
    return Uint16List(count);
  }

  @override
  Future<void> writeSingleCoil(int unitId, int address, bool value) async {
    // Mock write
  }

  @override
  Future<void> writeSingleRegister(int unitId, int address, int value) async {
    // Mock write
  }

  @override
  Future<void> writeMultipleCoils(int unitId, int address, List<bool> values) async {
    // Mock write
  }

  @override
  Future<void> writeMultipleRegisters(int unitId, int address, Uint16List values) async {
    // Mock write
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }
}

/// Mock DAC provider for testing
class MockDacProvider implements DacProvider {
  final Map<int, DacConfig> _configs = {};
  final Map<int, int> _rawValues = {};
  final Map<int, double> _voltages = {};
  final Map<int, bool> _enabled = {};

  @override
  String get name => 'MockDAC';

  @override
  String get version => '1.0.0';

  @override
  Map<String, dynamic> get capabilities => {'maxChannels': 4, 'resolution': 12};

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.dac};

  @override
  bool get isReady => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize() async { _initialized = true; }

  @override
  Future<void> dispose() async { _initialized = false; _configs.clear(); }

  @override
  Future<void> configureChannel(DacConfig config) async {
    _configs[config.channel] = config;
    _rawValues[config.channel] = 0;
    _voltages[config.channel] = 0.0;
    _enabled[config.channel] = false;
  }

  @override
  Future<void> writeRaw(int channel, int value) async {
    _rawValues[channel] = value;
  }

  @override
  Future<void> writeVoltage(int channel, double voltage) async {
    _voltages[channel] = voltage;
  }

  @override
  Future<void> setOutputEnabled(int channel, bool enabled) async {
    _enabled[channel] = enabled;
  }

  @override
  List<int> get availableChannels => _configs.keys.toList();
}

/// Mock Timer provider for testing
class MockTimerProvider implements TimerProvider {
  int _nextTimerId = 1;
  final Map<int, Timer> _timers = {};

  @override
  String get name => 'MockTimer';

  @override
  String get version => '1.0.0';

  @override
  Map<String, dynamic> get capabilities => {'maxTimers': 16};

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.timer};

  @override
  bool get isReady => _initialized;
  bool _initialized = false;

  @override
  Future<void> initialize() async { _initialized = true; }

  @override
  Future<void> dispose() async {
    for (final timer in _timers.values) { timer.cancel(); }
    _timers.clear();
    _initialized = false;
  }

  @override
  Future<int> start(Duration duration, void Function() callback, {bool periodic = false}) async {
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
    _timers.remove(timerId)?.cancel();
  }

  @override
  bool isRunning(int timerId) => _timers.containsKey(timerId) && _timers[timerId]!.isActive;
}