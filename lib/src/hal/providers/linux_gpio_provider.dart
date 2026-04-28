/// Linux GPIO provider using sysfs interface
import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import '../../types/hardware_types.dart';
import '../hal_interface.dart';
import '../../errors/flow_errors.dart';

/// Linux GPIO provider implementation
class LinuxGpioProvider implements GpioProvider {
  final Logger _logger = Logger('LinuxGpioProvider');
  final Map<int, GpioConfig> _pinConfigs = {};
  final Map<int, StreamController<bool>> _interruptControllers = {};
  final Map<int, Timer?> _pollingTimers = {};
  final String _sysfsPath;
  bool _isReady = false;
  
  LinuxGpioProvider({String? sysfsPath}) 
    : _sysfsPath = sysfsPath ?? '/sys/class/gpio';

  @override
  String get name => 'Linux GPIO (sysfs)';

  @override
  String get version => '1.0.0';

  @override
  Set<ResourceType> get supportedTypes => {ResourceType.gpio};

  @override
  bool get isReady => _isReady;

  @override
  Map<String, dynamic> get capabilities => {
    'maxPins': 256,
    'interrupts': true,
    'pullResistors': false, // Not available via sysfs
    'interface': 'sysfs',
  };

  @override
  List<int> get availablePins {
    // On Linux, GPIO pins vary by board
    // This would need to be configured or detected
    return List.generate(32, (i) => i); // Default to 32 pins
  }

  @override
  Future<void> initialize() async {
    // Check if GPIO sysfs is available
    final gpioDir = Directory(_sysfsPath);
    if (!await gpioDir.exists()) {
      throw HardwareError(
        'GPIO sysfs interface not available at $_sysfsPath',
        resourceId: 'gpio',
        resourceType: 'gpio',
      );
    }
    _isReady = true;
    _logger.info('Linux GPIO provider initialized');
  }

  @override
  Future<void> dispose() async {
    // Unexport all pins
    for (final pin in _pinConfigs.keys.toList()) {
      await _unexportPin(pin);
    }
    
    // Cancel all polling timers
    for (final timer in _pollingTimers.values) {
      timer?.cancel();
    }
    
    // Close all interrupt controllers
    for (final controller in _interruptControllers.values) {
      await controller.close();
    }
    
    _pinConfigs.clear();
    _pollingTimers.clear();
    _interruptControllers.clear();
    _isReady = false;
  }

  @override
  Future<void> configurePin(GpioConfig config) async {
    final pin = config.pin;
    
    // Export the pin if not already done
    if (!_pinConfigs.containsKey(pin)) {
      await _exportPin(pin);
    }
    
    // Set direction
    final direction = config.mode == GpioMode.output ? 'out' : 'in';
    final directionFile = File('$_sysfsPath/gpio$pin/direction');
    await directionFile.writeAsString(direction);
    
    // Store configuration
    _pinConfigs[pin] = config;
    
    _logger.fine('Configured GPIO pin $pin as $direction');
  }

  @override
  Future<bool> readPin(int pin) async {
    if (!_pinConfigs.containsKey(pin)) {
      throw HardwareError(
        'GPIO pin $pin not configured',
        resourceId: 'gpio$pin',
        resourceType: 'gpio',
      );
    }
    
    final valueFile = File('$_sysfsPath/gpio$pin/value');
    final value = await valueFile.readAsString();
    return value.trim() == '1';
  }

  @override
  Future<void> writePin(int pin, bool value) async {
    final config = _pinConfigs[pin];
    if (config == null) {
      throw HardwareError(
        'GPIO pin $pin not configured',
        resourceId: 'gpio$pin',
        resourceType: 'gpio',
      );
    }
    
    if (config.mode != GpioMode.output) {
      throw HardwareError(
        'Cannot write to input pin $pin',
        resourceId: 'gpio$pin',
        resourceType: 'gpio',
      );
    }
    
    final valueFile = File('$_sysfsPath/gpio$pin/value');
    await valueFile.writeAsString(value ? '1' : '0');
  }

  @override
  Future<void> setInterruptHandler(
    int pin,
    GpioInterrupt trigger,
    void Function(bool value) handler,
  ) async {
    final config = _pinConfigs[pin];
    if (config == null) {
      throw HardwareError(
        'GPIO pin $pin not configured',
        resourceId: 'gpio$pin',
        resourceType: 'gpio',
      );
    }
    
    if (config.mode != GpioMode.input) {
      throw HardwareError(
        'Interrupts only available for input pins',
        resourceId: 'gpio$pin',
        resourceType: 'gpio',
      );
    }
    
    // Set edge trigger type
    final edgeFile = File('$_sysfsPath/gpio$pin/edge');
    String edge;
    switch (trigger) {
      case GpioInterrupt.rising:
        edge = 'rising';
        break;
      case GpioInterrupt.falling:
        edge = 'falling';
        break;
      case GpioInterrupt.both:
        edge = 'both';
        break;
      case GpioInterrupt.none:
        edge = 'none';
        break;
    }
    
    try {
      await edgeFile.writeAsString(edge);
    } catch (e) {
      // Edge detection might not be supported
      _logger.warning('Edge detection not supported for pin $pin, using polling');
      _setupPollingInterrupt(pin, trigger, handler);
      return;
    }
    
    // Create interrupt stream
    final controller = StreamController<bool>.broadcast();
    _interruptControllers[pin] = controller;
    
    // Start polling for changes (simplified implementation)
    // In a real implementation, this would use epoll or similar
    _setupPollingInterrupt(pin, trigger, handler);
  }

  @override
  Future<void> removeInterruptHandler(int pin) async {
    // Cancel polling timer
    _pollingTimers[pin]?.cancel();
    _pollingTimers.remove(pin);
    
    // Close interrupt controller
    await _interruptControllers[pin]?.close();
    _interruptControllers.remove(pin);
    
    // Reset edge to none
    try {
      final edgeFile = File('$_sysfsPath/gpio$pin/edge');
      await edgeFile.writeAsString('none');
    } catch (_) {
      // Ignore errors
    }
  }

  // Helper methods

  Future<void> _exportPin(int pin) async {
    try {
      final exportFile = File('$_sysfsPath/export');
      await exportFile.writeAsString('$pin');
      
      // Wait for pin to be exported
      await Future.delayed(Duration(milliseconds: 100));
    } catch (e) {
      throw HardwareError(
        'Failed to export GPIO pin $pin: $e',
        resourceId: 'gpio$pin',
        resourceType: 'gpio',
      );
    }
  }

  Future<void> _unexportPin(int pin) async {
    try {
      final unexportFile = File('$_sysfsPath/unexport');
      await unexportFile.writeAsString('$pin');
      _logger.fine('Unexported GPIO pin $pin');
    } catch (e) {
      _logger.warning('Failed to unexport GPIO pin $pin: $e');
    }
  }

  void _setupPollingInterrupt(
    int pin,
    GpioInterrupt trigger,
    void Function(bool value) handler,
  ) {
    bool lastValue = false;
    
    // Initialize last value
    readPin(pin).then((value) => lastValue = value);
    
    // Start polling
    _pollingTimers[pin] = Timer.periodic(Duration(milliseconds: 10), (_) async {
      try {
        final currentValue = await readPin(pin);
        
        if (currentValue != lastValue) {
          final shouldTrigger = 
            (trigger == GpioInterrupt.rising && currentValue && !lastValue) ||
            (trigger == GpioInterrupt.falling && !currentValue && lastValue) ||
            (trigger == GpioInterrupt.both);
            
          if (shouldTrigger) {
            handler(currentValue);
          }
          
          lastValue = currentValue;
        }
      } catch (e) {
        _logger.warning('Error polling GPIO pin $pin: $e');
      }
    });
  }
}