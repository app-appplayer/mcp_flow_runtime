/// Action executor for MCP Flow Runtime

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:expressions/expressions.dart';

import '../types/flow_types.dart';
import '../types/runtime_types.dart';
import '../types/hardware_types.dart';
import '../errors/flow_errors.dart';
import '../hal/hal_interface.dart';
import '../state/state_manager.dart';

/// Action executor implementation
class ActionExecutor {
  final Logger _logger = Logger('ActionExecutor');
  final HardwareAbstractionLayer hal;
  final StateManager stateManager;
  final Map<String, StreamController> channels;
  final Map<String, dynamic> resources;
  final RuntimeConfig config;
  
  ActionExecutor({
    required this.hal,
    required this.stateManager,
    required this.channels,
    required this.resources,
    required this.config,
  });

  /// Execute an action
  Future<dynamic> execute(
    ActionDefinition action,
    ExecutionContext context,
  ) async {
    switch (action.action) {
      // State actions
      case 'setState':
        return _executeSetState(action, context);
      case 'getState':
        return _executeGetState(action, context);
        
      // GPIO actions
      case 'gpioWrite':
        return _executeGpioWrite(action, context);
      case 'gpioRead':
        return _executeGpioRead(action, context);
      case 'gpioConfig':
        return _executeGpioConfig(action, context);
        
      // I2C actions
      case 'i2cWrite':
        return _executeI2cWrite(action, context);
      case 'i2cRead':
        return _executeI2cRead(action, context);
        
      // SPI actions
      case 'spiTransfer':
        return _executeSpiTransfer(action, context);
        
      // PWM actions
      case 'pwmWrite':
        return _executePwmWrite(action, context);
      case 'pwmConfig':
        return _executePwmConfig(action, context);
        
      // UART actions
      case 'uartWrite':
        return _executeUartWrite(action, context);
      case 'uartRead':
        return _executeUartRead(action, context);
        
      // ADC actions
      case 'adcRead':
        return _executeAdcRead(action, context);
        
      // Modbus actions
      case 'modbusRead':
        return _executeModbusRead(action, context);
      case 'modbusWrite':
        return _executeModbusWrite(action, context);
        
      // Channel actions
      case 'channelSend':
        return _executeChannelSend(action, context);
      case 'channelReceive':
        return _executeChannelReceive(action, context);
        
      // Utility actions
      case 'log':
        return _executeLog(action, context);
      case 'delay':
        return _executeDelay(action, context);
      case 'expression':
        return _executeExpression(action, context);
      case 'function':
        return _executeFunction(action, context);
      case 'httpRequest':
        return _executeHttpRequest(action, context);
      case 'fileRead':
        return _executeFileRead(action, context);
      case 'fileWrite':
        return _executeFileWrite(action, context);
        
      default:
        throw ProcessExecutionError(
          'Unknown action type: ${action.action}',
          processId: context.process.id,
          actionType: action.action,
        );
    }
  }

  /// Evaluate a condition expression
  Future<bool> evaluateCondition(
    String condition,
    ExecutionContext context,
  ) async {
    final result = await evaluateExpression(condition, context);
    if (result is bool) {
      return result;
    }
    // Truthy evaluation
    return result != null && result != 0 && result != '' && result != false;
  }

  /// Evaluate an expression
  Future<dynamic> evaluateExpression(
    String expression,
    ExecutionContext context,
  ) async {
    try {
      // Create variable context
      final variables = <String, dynamic>{
        ...context.globalState,
        ...context.process.variables,
        ...context.args,
      };

      // Parse and evaluate expression
      final expr = Expression.parse(expression);
      final evaluator = const ExpressionEvaluator();
      return evaluator.eval(expr, variables);
    } catch (e) {
      _logger.warning('Failed to evaluate expression: $expression', e);
      throw ProcessExecutionError(
        'Expression evaluation failed: $e',
        processId: context.process.id,
        cause: e,
      );
    }
  }

  // State actions

  Future<void> _executeSetState(ActionDefinition action, ExecutionContext context) async {
    final variable = action.params?['variable'] as String?;
    final value = action.params?['value'];
    
    if (variable == null) {
      throw ProcessExecutionError(
        'setState requires variable parameter',
        processId: context.process.id,
        actionType: 'setState',
      );
    }

    // Evaluate value if it's an expression
    final evaluatedValue = value is String && value.startsWith('=')
        ? await evaluateExpression(value.substring(1), context)
        : value;

    context.setVariable(variable, evaluatedValue);
    _logger.fine('Set state: $variable = $evaluatedValue');
  }

  Future<dynamic> _executeGetState(ActionDefinition action, ExecutionContext context) async {
    final variable = action.params?['variable'] as String?;
    
    if (variable == null) {
      throw ProcessExecutionError(
        'getState requires variable parameter',
        processId: context.process.id,
        actionType: 'getState',
      );
    }

    return context.getVariable(variable);
  }

  // GPIO actions

  Future<void> _executeGpioWrite(ActionDefinition action, ExecutionContext context) async {
    final pin = action.params?['pin'] as int?;
    final value = action.params?['value'];
    
    if (pin == null || value == null) {
      throw ProcessExecutionError(
        'gpioWrite requires pin and value parameters',
        processId: context.process.id,
        actionType: 'gpioWrite',
      );
    }

    final provider = hal.getProvider<GpioProvider>(ResourceType.gpio);
    if (provider == null) {
      throw HardwareError(
        'GPIO provider not available',
        resourceId: 'gpio',
        resourceType: 'gpio',
      );
    }

    final boolValue = value is bool ? value : value == 1 || value == 'high';
    await provider.writePin(pin, boolValue);
    _logger.fine('GPIO write: pin $pin = $boolValue');
  }

  Future<bool> _executeGpioRead(ActionDefinition action, ExecutionContext context) async {
    final pin = action.params?['pin'] as int?;
    
    if (pin == null) {
      throw ProcessExecutionError(
        'gpioRead requires pin parameter',
        processId: context.process.id,
        actionType: 'gpioRead',
      );
    }

    final provider = hal.getProvider<GpioProvider>(ResourceType.gpio);
    if (provider == null) {
      throw HardwareError(
        'GPIO provider not available',
        resourceId: 'gpio',
        resourceType: 'gpio',
      );
    }

    final value = await provider.readPin(pin);
    _logger.fine('GPIO read: pin $pin = $value');
    return value;
  }

  Future<void> _executeGpioConfig(ActionDefinition action, ExecutionContext context) async {
    final pin = action.params?['pin'] as int?;
    final mode = action.params?['mode'] as String?;
    
    if (pin == null || mode == null) {
      throw ProcessExecutionError(
        'gpioConfig requires pin and mode parameters',
        processId: context.process.id,
        actionType: 'gpioConfig',
      );
    }

    final provider = hal.getProvider<GpioProvider>(ResourceType.gpio);
    if (provider == null) {
      throw HardwareError(
        'GPIO provider not available',
        resourceId: 'gpio',
        resourceType: 'gpio',
      );
    }

    final gpioMode = GpioMode.values.byName(mode);
    final config = GpioConfig(pin: pin, mode: gpioMode);
    
    await provider.configurePin(config);
    _logger.fine('GPIO config: pin $pin mode $mode');
  }

  // I2C actions

  Future<void> _executeI2cWrite(ActionDefinition action, ExecutionContext context) async {
    final bus = action.params?['bus'] as int? ?? 0;
    final address = action.params?['address'] as int?;
    final data = action.params?['data'];
    
    if (address == null || data == null) {
      throw ProcessExecutionError(
        'i2cWrite requires address and data parameters',
        processId: context.process.id,
        actionType: 'i2cWrite',
      );
    }

    final provider = hal.getProvider<I2cProvider>(ResourceType.i2c);
    if (provider == null) {
      throw HardwareError(
        'I2C provider not available',
        resourceId: 'i2c',
        resourceType: 'i2c',
      );
    }

    final i2cBus = await provider.openBus(bus);
    try {
      final bytes = _toBytes(data);
      await i2cBus.write(address, bytes);
      _logger.fine('I2C write: bus $bus, address 0x${address.toRadixString(16)}, ${bytes.length} bytes');
    } finally {
      await i2cBus.close();
    }
  }

  Future<List<int>> _executeI2cRead(ActionDefinition action, ExecutionContext context) async {
    final bus = action.params?['bus'] as int? ?? 0;
    final address = action.params?['address'] as int?;
    final length = action.params?['length'] as int?;
    
    if (address == null || length == null) {
      throw ProcessExecutionError(
        'i2cRead requires address and length parameters',
        processId: context.process.id,
        actionType: 'i2cRead',
      );
    }

    final provider = hal.getProvider<I2cProvider>(ResourceType.i2c);
    if (provider == null) {
      throw HardwareError(
        'I2C provider not available',
        resourceId: 'i2c',
        resourceType: 'i2c',
      );
    }

    final i2cBus = await provider.openBus(bus);
    try {
      final data = await i2cBus.read(address, length);
      _logger.fine('I2C read: bus $bus, address 0x${address.toRadixString(16)}, ${data.length} bytes');
      return data.toList();
    } finally {
      await i2cBus.close();
    }
  }

  // SPI actions

  Future<List<int>> _executeSpiTransfer(ActionDefinition action, ExecutionContext context) async {
    final device = action.params?['device'] as int? ?? 0;
    final data = action.params?['data'];
    
    if (data == null) {
      throw ProcessExecutionError(
        'spiTransfer requires data parameter',
        processId: context.process.id,
        actionType: 'spiTransfer',
      );
    }

    final provider = hal.getProvider<SpiProvider>(ResourceType.spi);
    if (provider == null) {
      throw HardwareError(
        'SPI provider not available',
        resourceId: 'spi',
        resourceType: 'spi',
      );
    }

    final spiDevice = await provider.openDevice(SpiConfig(device: device));
    try {
      final bytes = _toBytes(data);
      final result = await spiDevice.transfer(bytes);
      _logger.fine('SPI transfer: device $device, ${bytes.length} bytes');
      return result.toList();
    } finally {
      await spiDevice.close();
    }
  }

  // PWM actions

  Future<void> _executePwmWrite(ActionDefinition action, ExecutionContext context) async {
    final channel = action.params?['channel'] as int?;
    final dutyCycle = action.params?['dutyCycle'] as num?;
    
    if (channel == null || dutyCycle == null) {
      throw ProcessExecutionError(
        'pwmWrite requires channel and dutyCycle parameters',
        processId: context.process.id,
        actionType: 'pwmWrite',
      );
    }

    final provider = hal.getProvider<PwmProvider>(ResourceType.pwm);
    if (provider == null) {
      throw HardwareError(
        'PWM provider not available',
        resourceId: 'pwm',
        resourceType: 'pwm',
      );
    }

    await provider.setDutyCycle(channel, dutyCycle.toDouble());
    _logger.fine('PWM write: channel $channel, duty cycle $dutyCycle');
  }

  Future<void> _executePwmConfig(ActionDefinition action, ExecutionContext context) async {
    final channel = action.params?['channel'] as int?;
    final frequency = action.params?['frequency'] as num?;
    
    if (channel == null || frequency == null) {
      throw ProcessExecutionError(
        'pwmConfig requires channel and frequency parameters',
        processId: context.process.id,
        actionType: 'pwmConfig',
      );
    }

    final provider = hal.getProvider<PwmProvider>(ResourceType.pwm);
    if (provider == null) {
      throw HardwareError(
        'PWM provider not available',
        resourceId: 'pwm',
        resourceType: 'pwm',
      );
    }

    final config = PwmConfig(
      channel: channel,
      frequency: frequency.toDouble(),
    );
    
    await provider.configureChannel(config);
    _logger.fine('PWM config: channel $channel, frequency $frequency Hz');
  }

  // UART actions

  Future<void> _executeUartWrite(ActionDefinition action, ExecutionContext context) async {
    final port = action.params?['port'] as String?;
    final data = action.params?['data'];
    
    if (port == null || data == null) {
      throw ProcessExecutionError(
        'uartWrite requires port and data parameters',
        processId: context.process.id,
        actionType: 'uartWrite',
      );
    }

    final provider = hal.getProvider<UartProvider>(ResourceType.uart);
    if (provider == null) {
      throw HardwareError(
        'UART provider not available',
        resourceId: 'uart',
        resourceType: 'uart',
      );
    }

    final uartPort = await provider.openPort(UartConfig(port: port));
    try {
      if (data is String) {
        await uartPort.writeString(data);
      } else {
        final bytes = _toBytes(data);
        await uartPort.write(bytes);
      }
      _logger.fine('UART write: port $port');
    } finally {
      await uartPort.close();
    }
  }

  Future<String> _executeUartRead(ActionDefinition action, ExecutionContext context) async {
    final port = action.params?['port'] as String?;
    final timeout = action.params?['timeout'] as int? ?? 1000;
    
    if (port == null) {
      throw ProcessExecutionError(
        'uartRead requires port parameter',
        processId: context.process.id,
        actionType: 'uartRead',
      );
    }

    final provider = hal.getProvider<UartProvider>(ResourceType.uart);
    if (provider == null) {
      throw HardwareError(
        'UART provider not available',
        resourceId: 'uart',
        resourceType: 'uart',
      );
    }

    final uartPort = await provider.openPort(UartConfig(port: port));
    try {
      final data = await uartPort.dataStream.first.timeout(
        Duration(milliseconds: timeout),
        onTimeout: () => Uint8List(0),
      );
      final result = utf8.decode(data);
      _logger.fine('UART read: port $port, ${data.length} bytes');
      return result;
    } finally {
      await uartPort.close();
    }
  }

  // ADC actions

  Future<double> _executeAdcRead(ActionDefinition action, ExecutionContext context) async {
    final channel = action.params?['channel'] as int?;
    
    if (channel == null) {
      throw ProcessExecutionError(
        'adcRead requires channel parameter',
        processId: context.process.id,
        actionType: 'adcRead',
      );
    }

    final provider = hal.getProvider<AdcProvider>(ResourceType.adc);
    if (provider == null) {
      throw HardwareError(
        'ADC provider not available',
        resourceId: 'adc',
        resourceType: 'adc',
      );
    }

    final voltage = await provider.readVoltage(channel);
    _logger.fine('ADC read: channel $channel = $voltage V');
    return voltage;
  }

  // Modbus actions

  Future<dynamic> _executeModbusRead(ActionDefinition action, ExecutionContext context) async {
    final config = action.params?['config'] as Map<String, dynamic>?;
    final unitId = action.params?['unitId'] as int?;
    final functionCode = action.params?['function'] as String?;
    final address = action.params?['address'] as int?;
    final count = action.params?['count'] as int?;
    
    if (config == null || unitId == null || functionCode == null || 
        address == null || count == null) {
      throw ProcessExecutionError(
        'modbusRead requires config, unitId, function, address and count parameters',
        processId: context.process.id,
        actionType: 'modbusRead',
      );
    }

    final provider = hal.getProvider<ModbusProvider>(ResourceType.modbus);
    if (provider == null) {
      throw HardwareError(
        'Modbus provider not available',
        resourceId: 'modbus',
        resourceType: 'modbus',
      );
    }

    final modbusConfig = ModbusConfig.fromJson(config);
    final client = await provider.connect(modbusConfig);
    
    try {
      switch (functionCode) {
        case 'readCoils':
          return await client.readCoils(unitId, address, count);
        case 'readDiscreteInputs':
          return await client.readDiscreteInputs(unitId, address, count);
        case 'readHoldingRegisters':
          return (await client.readHoldingRegisters(unitId, address, count)).toList();
        case 'readInputRegisters':
          return (await client.readInputRegisters(unitId, address, count)).toList();
        default:
          throw ProcessExecutionError(
            'Unknown Modbus function: $functionCode',
            processId: context.process.id,
            actionType: 'modbusRead',
          );
      }
    } finally {
      await client.disconnect();
    }
  }

  Future<void> _executeModbusWrite(ActionDefinition action, ExecutionContext context) async {
    final config = action.params?['config'] as Map<String, dynamic>?;
    final unitId = action.params?['unitId'] as int?;
    final functionCode = action.params?['function'] as String?;
    final address = action.params?['address'] as int?;
    final value = action.params?['value'];
    
    if (config == null || unitId == null || functionCode == null || 
        address == null || value == null) {
      throw ProcessExecutionError(
        'modbusWrite requires config, unitId, function, address and value parameters',
        processId: context.process.id,
        actionType: 'modbusWrite',
      );
    }

    final provider = hal.getProvider<ModbusProvider>(ResourceType.modbus);
    if (provider == null) {
      throw HardwareError(
        'Modbus provider not available',
        resourceId: 'modbus',
        resourceType: 'modbus',
      );
    }

    final modbusConfig = ModbusConfig.fromJson(config);
    final client = await provider.connect(modbusConfig);
    
    try {
      switch (functionCode) {
        case 'writeSingleCoil':
          await client.writeSingleCoil(unitId, address, value as bool);
          break;
        case 'writeSingleRegister':
          await client.writeSingleRegister(unitId, address, value as int);
          break;
        case 'writeMultipleCoils':
          await client.writeMultipleCoils(unitId, address, (value as List).cast<bool>());
          break;
        case 'writeMultipleRegisters':
          final values = (value as List<dynamic>).map((v) => v as int).toList();
          await client.writeMultipleRegisters(unitId, address, Uint16List.fromList(values));
          break;
        default:
          throw ProcessExecutionError(
            'Unknown Modbus function: $functionCode',
            processId: context.process.id,
            actionType: 'modbusWrite',
          );
      }
    } finally {
      await client.disconnect();
    }
  }

  // Channel actions

  Future<void> _executeChannelSend(ActionDefinition action, ExecutionContext context) async {
    final channel = action.params?['channel'] as String?;
    final data = action.params?['data'];
    
    if (channel == null || data == null) {
      throw ProcessExecutionError(
        'channelSend requires channel and data parameters',
        processId: context.process.id,
        actionType: 'channelSend',
      );
    }

    final controller = channels[channel];
    if (controller == null) {
      throw ProcessExecutionError(
        'Channel $channel not found',
        processId: context.process.id,
        actionType: 'channelSend',
      );
    }

    controller.add(data);
    _logger.fine('Channel send: $channel');
  }

  Future<dynamic> _executeChannelReceive(ActionDefinition action, ExecutionContext context) async {
    final channel = action.params?['channel'] as String?;
    final timeout = action.params?['timeout'] as int?;
    
    if (channel == null) {
      throw ProcessExecutionError(
        'channelReceive requires channel parameter',
        processId: context.process.id,
        actionType: 'channelReceive',
      );
    }

    final controller = channels[channel];
    if (controller == null) {
      throw ProcessExecutionError(
        'Channel $channel not found',
        processId: context.process.id,
        actionType: 'channelReceive',
      );
    }

    if (timeout != null) {
      return await controller.stream.first.timeout(
        Duration(milliseconds: timeout),
        onTimeout: () => null,
      );
    }
    
    return await controller.stream.first;
  }

  // Utility actions

  Future<void> _executeLog(ActionDefinition action, ExecutionContext context) async {
    final message = action.params?['message'] ?? '';
    final level = action.params?['level'] as String? ?? 'info';
    
    final evaluatedMessage = message is String && message.startsWith('=')
        ? await evaluateExpression(message.substring(1), context)
        : message;

    switch (level) {
      case 'debug':
        _logger.fine('[Process ${context.process.id}] $evaluatedMessage');
        break;
      case 'info':
        _logger.info('[Process ${context.process.id}] $evaluatedMessage');
        break;
      case 'warning':
        _logger.warning('[Process ${context.process.id}] $evaluatedMessage');
        break;
      case 'error':
        _logger.severe('[Process ${context.process.id}] $evaluatedMessage');
        break;
      default:
        _logger.info('[Process ${context.process.id}] $evaluatedMessage');
    }
  }

  Future<void> _executeDelay(ActionDefinition action, ExecutionContext context) async {
    final ms = action.params?['ms'] as int? ?? 0;
    await Future.delayed(Duration(milliseconds: ms));
    _logger.fine('Delay: ${ms}ms');
  }

  Future<dynamic> _executeExpression(ActionDefinition action, ExecutionContext context) async {
    final expression = action.params?['expression'] as String?;
    
    if (expression == null) {
      throw ProcessExecutionError(
        'expression action requires expression parameter',
        processId: context.process.id,
        actionType: 'expression',
      );
    }

    return await evaluateExpression(expression, context);
  }

  Future<dynamic> _executeFunction(ActionDefinition action, ExecutionContext context) async {
    final name = action.params?['name'] as String?;
    final args = action.params?['args'] as List?;
    
    if (name == null) {
      throw ProcessExecutionError(
        'function action requires name parameter',
        processId: context.process.id,
        actionType: 'function',
      );
    }

    // Built-in functions
    switch (name) {
      case 'min':
        return args?.reduce((a, b) => a < b ? a : b);
      case 'max':
        return args?.reduce((a, b) => a > b ? a : b);
      case 'sum':
        return args?.fold<num>(0, (sum, val) => sum + (val as num));
      case 'avg':
        if (args == null || args.isEmpty) return 0;
        return args.fold<num>(0, (sum, val) => sum + (val as num)) / args.length;
      case 'random':
        final min = args?[0] ?? 0;
        final max = args?[1] ?? 1;
        return min + (max - min) * (DateTime.now().millisecondsSinceEpoch % 1000) / 1000;
      default:
        throw ProcessExecutionError(
          'Unknown function: $name',
          processId: context.process.id,
          actionType: 'function',
        );
    }
  }

  Future<Map<String, dynamic>> _executeHttpRequest(ActionDefinition action, ExecutionContext context) async {
    final url = action.params?['url'] as String?;
    final method = action.params?['method'] as String? ?? 'GET';
    
    if (url == null) {
      throw ProcessExecutionError(
        'httpRequest requires url parameter',
        processId: context.process.id,
        actionType: 'httpRequest',
      );
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse(url);
      late HttpClientRequest request;
      
      switch (method.toUpperCase()) {
        case 'GET':
          request = await client.getUrl(uri);
          break;
        case 'POST':
          request = await client.postUrl(uri);
          break;
        case 'PUT':
          request = await client.putUrl(uri);
          break;
        case 'DELETE':
          request = await client.deleteUrl(uri);
          break;
        default:
          throw ProcessExecutionError(
            'Unsupported HTTP method: $method',
            processId: context.process.id,
            actionType: 'httpRequest',
          );
      }

      // Add headers
      final headers = action.params?['headers'] as Map<String, dynamic>?;
      headers?.forEach((key, value) {
        request.headers.add(key, value.toString());
      });

      // Add body
      final body = action.params?['body'];
      if (body != null) {
        if (body is String) {
          request.write(body);
        } else {
          request.write(json.encode(body));
        }
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      return {
        'status': response.statusCode,
        'headers': response.headers,
        'body': responseBody,
      };
    } finally {
      client.close();
    }
  }

  Future<String> _executeFileRead(ActionDefinition action, ExecutionContext context) async {
    final path = action.params?['path'] as String?;
    
    if (path == null) {
      throw ProcessExecutionError(
        'fileRead requires path parameter',
        processId: context.process.id,
        actionType: 'fileRead',
      );
    }

    final file = File(path);
    return await file.readAsString();
  }

  Future<void> _executeFileWrite(ActionDefinition action, ExecutionContext context) async {
    final path = action.params?['path'] as String?;
    final content = action.params?['content'];
    
    if (path == null || content == null) {
      throw ProcessExecutionError(
        'fileWrite requires path and content parameters',
        processId: context.process.id,
        actionType: 'fileWrite',
      );
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    
    if (content is String) {
      await file.writeAsString(content);
    } else {
      await file.writeAsString(json.encode(content));
    }
  }

  // Helper methods

  Uint8List _toBytes(dynamic data) {
    if (data is Uint8List) {
      return data;
    } else if (data is List<int>) {
      return Uint8List.fromList(data);
    } else if (data is String) {
      return Uint8List.fromList(data.codeUnits);
    } else {
      throw ArgumentError('Cannot convert $data to bytes');
    }
  }
}