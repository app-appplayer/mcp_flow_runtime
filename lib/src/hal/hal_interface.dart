/// Hardware Abstraction Layer interface definitions

import 'dart:async';
import 'dart:typed_data';

import '../types/hardware_types.dart';

/// Base interface for all hardware providers
abstract class HardwareProvider {
  /// Provider name/identifier
  String get name;
  
  /// Provider version
  String get version;
  
  /// Supported resource types
  Set<ResourceType> get supportedTypes;
  
  /// Initialize the provider
  Future<void> initialize();
  
  /// Cleanup provider resources
  Future<void> dispose();
  
  /// Check if provider is ready
  bool get isReady;
  
  /// Get provider capabilities
  Map<String, dynamic> get capabilities;
}

/// GPIO interface
abstract class GpioProvider extends HardwareProvider {
  /// Configure a GPIO pin
  Future<void> configurePin(GpioConfig config);
  
  /// Read pin value
  Future<bool> readPin(int pin);
  
  /// Write pin value
  Future<void> writePin(int pin, bool value);
  
  /// Set interrupt handler
  Future<void> setInterruptHandler(
    int pin,
    GpioInterrupt trigger,
    void Function(bool value) handler,
  );
  
  /// Remove interrupt handler
  Future<void> removeInterruptHandler(int pin);
  
  /// Get available pins
  List<int> get availablePins;
}

/// I2C interface
abstract class I2cProvider extends HardwareProvider {
  /// Open I2C bus
  Future<I2cBus> openBus(int bus);
  
  /// Get available buses
  List<int> get availableBuses;
}

/// I2C bus interface
abstract class I2cBus {
  /// Bus number
  int get bus;
  
  /// Read bytes from device
  Future<Uint8List> read(int address, int length);
  
  /// Write bytes to device
  Future<void> write(int address, Uint8List data);
  
  /// Read from register
  Future<Uint8List> readRegister(int address, int register, int length);
  
  /// Write to register
  Future<void> writeRegister(int address, int register, Uint8List data);
  
  /// Close the bus
  Future<void> close();
}

/// SPI interface
abstract class SpiProvider extends HardwareProvider {
  /// Open SPI device
  Future<SpiDevice> openDevice(SpiConfig config);
  
  /// Get available devices
  List<int> get availableDevices;
}

/// SPI device interface
abstract class SpiDevice {
  /// Device configuration
  SpiConfig get config;
  
  /// Transfer data (full duplex)
  Future<Uint8List> transfer(Uint8List data);
  
  /// Write data (ignore read)
  Future<void> write(Uint8List data);
  
  /// Read data (send zeros)
  Future<Uint8List> read(int length);
  
  /// Close the device
  Future<void> close();
}

/// PWM interface
abstract class PwmProvider extends HardwareProvider {
  /// Configure PWM channel
  Future<void> configureChannel(PwmConfig config);
  
  /// Set duty cycle (0.0 - 1.0)
  Future<void> setDutyCycle(int channel, double dutyCycle);
  
  /// Set frequency
  Future<void> setFrequency(int channel, double frequency);
  
  /// Enable/disable channel
  Future<void> setEnabled(int channel, bool enabled);
  
  /// Get available channels
  List<int> get availableChannels;
}

/// UART interface
abstract class UartProvider extends HardwareProvider {
  /// Open UART port
  Future<UartPort> openPort(UartConfig config);
  
  /// Get available ports
  List<String> get availablePorts;
}

/// UART port interface
abstract class UartPort {
  /// Port configuration
  UartConfig get config;
  
  /// Read data stream
  Stream<Uint8List> get dataStream;
  
  /// Write data
  Future<void> write(Uint8List data);
  
  /// Write string
  Future<void> writeString(String data);
  
  /// Close the port
  Future<void> close();
}

/// ADC interface
abstract class AdcProvider extends HardwareProvider {
  /// Configure ADC channel
  Future<void> configureChannel(AdcConfig config);
  
  /// Read raw value
  Future<int> readRaw(int channel);
  
  /// Read voltage
  Future<double> readVoltage(int channel);
  
  /// Read multiple samples and average
  Future<double> readAveraged(int channel, int samples);
  
  /// Get available channels
  List<int> get availableChannels;
}

/// DAC interface
abstract class DacProvider extends HardwareProvider {
  /// Configure DAC channel
  Future<void> configureChannel(DacConfig config);
  
  /// Write raw value
  Future<void> writeRaw(int channel, int value);
  
  /// Write voltage
  Future<void> writeVoltage(int channel, double voltage);
  
  /// Set output enable
  Future<void> setOutputEnabled(int channel, bool enabled);
  
  /// Get available channels
  List<int> get availableChannels;
}

/// Modbus interface
abstract class ModbusProvider extends HardwareProvider {
  /// Connect to Modbus device
  Future<ModbusClient> connect(ModbusConfig config);
}

/// Modbus client interface
abstract class ModbusClient {
  /// Configuration
  ModbusConfig get config;
  
  /// Connection status
  bool get isConnected;
  
  /// Read coils (discrete outputs)
  Future<List<bool>> readCoils(int unitId, int address, int count);
  
  /// Read discrete inputs
  Future<List<bool>> readDiscreteInputs(int unitId, int address, int count);
  
  /// Read holding registers
  Future<Uint16List> readHoldingRegisters(int unitId, int address, int count);
  
  /// Read input registers
  Future<Uint16List> readInputRegisters(int unitId, int address, int count);
  
  /// Write single coil
  Future<void> writeSingleCoil(int unitId, int address, bool value);
  
  /// Write single register
  Future<void> writeSingleRegister(int unitId, int address, int value);
  
  /// Write multiple coils
  Future<void> writeMultipleCoils(int unitId, int address, List<bool> values);
  
  /// Write multiple registers
  Future<void> writeMultipleRegisters(int unitId, int address, Uint16List values);
  
  /// Disconnect
  Future<void> disconnect();
}

/// Timer interface for periodic and one-shot timers
abstract class TimerProvider extends HardwareProvider {
  /// Start a periodic or one-shot timer
  ///
  /// [duration] - timer interval/delay
  /// [callback] - function called on timer trigger
  /// [periodic] - if true, timer repeats; if false, fires once
  /// Returns a timer ID for subsequent operations
  Future<int> start(Duration duration, void Function() callback, {bool periodic = false});

  /// Stop a running timer
  ///
  /// [timerId] - ID returned by start()
  Future<void> stop(int timerId);

  /// Check if a timer is currently running
  ///
  /// [timerId] - ID returned by start()
  bool isRunning(int timerId);
}

/// Hardware abstraction layer main interface
abstract class HardwareAbstractionLayer {
  /// Register a hardware provider
  void registerProvider(HardwareProvider provider);
  
  /// Get provider for resource type
  T? getProvider<T extends HardwareProvider>(ResourceType type);
  
  /// Get all registered providers
  List<HardwareProvider> get providers;
  
  /// Initialize all providers
  Future<void> initialize();
  
  /// Cleanup all providers
  Future<void> dispose();
  
  /// Get system information
  Map<String, dynamic> get systemInfo;
}

// --- HAL Exception Classes ---

/// Base class for all HAL-related exceptions
class HalException implements Exception {
  final String message;
  final String? providerType;
  final Object? cause;

  const HalException(this.message, {this.providerType, this.cause});

  @override
  String toString() => 'HalException[$providerType]: $message';
}

/// Thrown when a requested provider is not registered
class HalNotFoundException extends HalException {
  const HalNotFoundException(String type)
      : super('Provider not registered', providerType: type);
}

/// Thrown when provider initialization fails
class HalInitializationException extends HalException {
  const HalInitializationException(super.message, {super.cause});
}

/// Thrown when a hardware operation fails
class HalOperationException extends HalException {
  final int? errorCode;

  const HalOperationException(super.message, {this.errorCode, super.cause});
}

/// Thrown when a hardware operation times out
class HalTimeoutException extends HalException {
  const HalTimeoutException(super.message);
}

/// Thrown when OS-level permissions are insufficient
class HalPermissionException extends HalException {
  const HalPermissionException(super.message);
}