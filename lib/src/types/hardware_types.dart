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
  final int? clockHz;

  const I2cConfig({
    required this.bus,
    required this.address,
    this.clockHz,
  });

  Map<String, dynamic> toJson() => {
        'bus': bus,
        'address': address,
        if (clockHz != null) 'clockHz': clockHz,
      };

  factory I2cConfig.fromJson(Map<String, dynamic> json) => I2cConfig(
        bus: json['bus'] as int,
        address: json['address'] as int,
        clockHz: json['clockHz'] as int?,
      );
}

/// SPI configuration
class SpiConfig {
  final int bus;
  final int device;
  final int clockHz;
  final int? mode;
  final int? bitsPerWord;

  const SpiConfig({
    required this.bus,
    required this.device,
    this.clockHz = 1000000, // 1MHz default
    this.mode,
    this.bitsPerWord,
  });

  Map<String, dynamic> toJson() => {
        'bus': bus,
        'device': device,
        'clockHz': clockHz,
        if (mode != null) 'mode': mode,
        if (bitsPerWord != null) 'bitsPerWord': bitsPerWord,
      };

  factory SpiConfig.fromJson(Map<String, dynamic> json) => SpiConfig(
        bus: json['bus'] as int,
        device: json['device'] as int,
        clockHz: json['clockHz'] as int? ?? 1000000,
        mode: json['mode'] as int?,
        bitsPerWord: json['bitsPerWord'] as int?,
      );
}

/// PWM configuration
class PwmConfig {
  final int channel;
  final double? frequencyHz;
  final double dutyPercent;

  const PwmConfig({
    required this.channel,
    this.frequencyHz,
    this.dutyPercent = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'channel': channel,
        if (frequencyHz != null) 'frequencyHz': frequencyHz,
        'dutyPercent': dutyPercent,
      };

  factory PwmConfig.fromJson(Map<String, dynamic> json) => PwmConfig(
        channel: json['channel'] as int,
        frequencyHz: (json['frequencyHz'] as num?)?.toDouble(),
        dutyPercent: (json['dutyPercent'] as num?)?.toDouble() ?? 0.0,
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
    required this.baudRate,
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
        baudRate: json['baudRate'] as int,
        dataBits: json['dataBits'] as int? ?? 8,
        stopBits: json['stopBits'] as int? ?? 1,
        parity: json['parity'] as String? ?? 'none',
      );
}

/// ADC configuration
class AdcConfig {
  final int channel;
  final int resolution;
  final double referenceVoltage;

  const AdcConfig({
    required this.channel,
    this.resolution = 12,
    this.referenceVoltage = 3.3,
  });

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'resolution': resolution,
        'referenceVoltage': referenceVoltage,
      };

  factory AdcConfig.fromJson(Map<String, dynamic> json) => AdcConfig(
        channel: json['channel'] as int,
        resolution: json['resolution'] as int? ?? 12,
        referenceVoltage:
            (json['referenceVoltage'] as num?)?.toDouble() ?? 3.3,
      );
}

/// DAC configuration
class DacConfig {
  final int channel;
  final int resolution;
  final double referenceVoltage;

  const DacConfig({
    required this.channel,
    this.resolution = 12,
    this.referenceVoltage = 3.3,
  });

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'resolution': resolution,
        'referenceVoltage': referenceVoltage,
      };

  factory DacConfig.fromJson(Map<String, dynamic> json) => DacConfig(
        channel: json['channel'] as int,
        resolution: json['resolution'] as int? ?? 12,
        referenceVoltage:
            (json['referenceVoltage'] as num?)?.toDouble() ?? 3.3,
      );
}

/// Modbus modes
enum ModbusMode { rtu, tcp }

/// Modbus configuration
class ModbusConfig {
  final ModbusMode mode;
  final dynamic address; // TCP host (String) or RTU port (String)
  final int? port; // TCP port number
  final int? unitId;
  final int? baudRate;

  const ModbusConfig({
    required this.mode,
    required this.address,
    this.port,
    this.unitId,
    this.baudRate,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'address': address,
        if (port != null) 'port': port,
        if (unitId != null) 'unitId': unitId,
        if (baudRate != null) 'baudRate': baudRate,
      };

  factory ModbusConfig.fromJson(Map<String, dynamic> json) => ModbusConfig(
        mode: ModbusMode.values.byName(json['mode'] as String),
        address: json['address'],
        port: json['port'] as int?,
        unitId: json['unitId'] as int?,
        baudRate: json['baudRate'] as int?,
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
  mqtt,
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