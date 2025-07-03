/// Hardware-related type definitions for MCP Flow Runtime

/// GPIO pin modes
enum GpioMode {
  input,
  output,
  inputPullUp,
  inputPullDown,
}

/// GPIO interrupt trigger types
enum GpioInterrupt {
  none,
  rising,
  falling,
  both,
}

/// GPIO configuration
class GpioConfig {
  final int pin;
  final GpioMode mode;
  final GpioInterrupt? interrupt;
  final bool initialValue;

  const GpioConfig({
    required this.pin,
    required this.mode,
    this.interrupt,
    this.initialValue = false,
  });

  Map<String, dynamic> toJson() => {
        'pin': pin,
        'mode': mode.name,
        if (interrupt != null) 'interrupt': interrupt!.name,
        'initialValue': initialValue,
      };

  factory GpioConfig.fromJson(Map<String, dynamic> json) => GpioConfig(
        pin: json['pin'] as int,
        mode: GpioMode.values.byName(json['mode'] as String),
        interrupt: json['interrupt'] != null
            ? GpioInterrupt.values.byName(json['interrupt'] as String)
            : null,
        initialValue: json['initialValue'] as bool? ?? false,
      );
}

/// I2C configuration
class I2cConfig {
  final int bus;
  final int address;
  final int? frequency;

  const I2cConfig({
    required this.bus,
    required this.address,
    this.frequency,
  });

  Map<String, dynamic> toJson() => {
        'bus': bus,
        'address': address,
        if (frequency != null) 'frequency': frequency,
      };

  factory I2cConfig.fromJson(Map<String, dynamic> json) => I2cConfig(
        bus: json['bus'] as int,
        address: json['address'] as int,
        frequency: json['frequency'] as int?,
      );
}

/// SPI configuration
class SpiConfig {
  final int device;
  final int speed;
  final int mode;
  final int bitsPerWord;

  const SpiConfig({
    required this.device,
    this.speed = 1000000, // 1MHz default
    this.mode = 0,
    this.bitsPerWord = 8,
  });

  Map<String, dynamic> toJson() => {
        'device': device,
        'speed': speed,
        'mode': mode,
        'bitsPerWord': bitsPerWord,
      };

  factory SpiConfig.fromJson(Map<String, dynamic> json) => SpiConfig(
        device: json['device'] as int,
        speed: json['speed'] as int? ?? 1000000,
        mode: json['mode'] as int? ?? 0,
        bitsPerWord: json['bitsPerWord'] as int? ?? 8,
      );
}

/// PWM configuration
class PwmConfig {
  final int channel;
  final double frequency;
  final double dutyCycle;

  const PwmConfig({
    required this.channel,
    required this.frequency,
    this.dutyCycle = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'frequency': frequency,
        'dutyCycle': dutyCycle,
      };

  factory PwmConfig.fromJson(Map<String, dynamic> json) => PwmConfig(
        channel: json['channel'] as int,
        frequency: (json['frequency'] as num).toDouble(),
        dutyCycle: (json['dutyCycle'] as num?)?.toDouble() ?? 0.0,
      );
}

/// UART configuration
class UartConfig {
  final String port;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final String parity;

  const UartConfig({
    required this.port,
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 'none',
  });

  Map<String, dynamic> toJson() => {
        'port': port,
        'baudRate': baudRate,
        'dataBits': dataBits,
        'stopBits': stopBits,
        'parity': parity,
      };

  factory UartConfig.fromJson(Map<String, dynamic> json) => UartConfig(
        port: json['port'] as String,
        baudRate: json['baudRate'] as int? ?? 9600,
        dataBits: json['dataBits'] as int? ?? 8,
        stopBits: json['stopBits'] as int? ?? 1,
        parity: json['parity'] as String? ?? 'none',
      );
}

/// ADC configuration
class AdcConfig {
  final int channel;
  final int resolution;
  final int samples;
  final double referenceVoltage;

  const AdcConfig({
    required this.channel,
    this.resolution = 12,
    this.samples = 1,
    this.referenceVoltage = 3.3,
  });

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'resolution': resolution,
        'samples': samples,
        'referenceVoltage': referenceVoltage,
      };

  factory AdcConfig.fromJson(Map<String, dynamic> json) => AdcConfig(
        channel: json['channel'] as int,
        resolution: json['resolution'] as int? ?? 12,
        samples: json['samples'] as int? ?? 1,
        referenceVoltage:
            (json['referenceVoltage'] as num?)?.toDouble() ?? 3.3,
      );
}

/// Modbus modes
enum ModbusMode { rtu, tcp }

/// Modbus configuration
class ModbusConfig {
  final ModbusMode mode;
  final String? port; // For RTU
  final int? baudRate; // For RTU
  final String? host; // For TCP
  final int? tcpPort; // For TCP
  final int timeout;

  const ModbusConfig({
    required this.mode,
    this.port,
    this.baudRate,
    this.host,
    this.tcpPort,
    this.timeout = 1000,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        if (port != null) 'port': port,
        if (baudRate != null) 'baudRate': baudRate,
        if (host != null) 'host': host,
        if (tcpPort != null) 'port': tcpPort,
        'timeout': timeout,
      };

  factory ModbusConfig.fromJson(Map<String, dynamic> json) => ModbusConfig(
        mode: ModbusMode.values.byName(json['mode'] as String),
        port: json['port'] as String?,
        baudRate: json['baudRate'] as int?,
        host: json['host'] as String?,
        tcpPort: json['port'] as int?,
        timeout: json['timeout'] as int? ?? 1000,
      );
}

/// Resource types
enum ResourceType {
  gpio,
  i2c,
  spi,
  pwm,
  uart,
  adc,
  dac,
  timer,
  modbus,
}

/// Base hardware resource
abstract class HardwareResource {
  final String id;
  final ResourceType type;
  final Map<String, dynamic> config;

  const HardwareResource({
    required this.id,
    required this.type,
    required this.config,
  });
}