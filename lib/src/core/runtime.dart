/// Core MCP Flow Runtime engine

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:event_bus/event_bus.dart';

import '../types/flow_types.dart';
import '../types/runtime_types.dart';
import '../errors/flow_errors.dart';
import '../hal/hal_interface.dart';
import '../hal/hal_factory.dart';
import '../state/state_manager.dart';
import '../parser/json_parser.dart';
import '../parser/validator.dart';
import 'scheduler.dart';
import 'process_executor.dart';

/// Runtime events
class RuntimeEvent {
  final DateTime timestamp;
  RuntimeEvent() : timestamp = DateTime.now();
}

class RuntimeStartedEvent extends RuntimeEvent {}
class RuntimeStoppedEvent extends RuntimeEvent {}
class RuntimeErrorEvent extends RuntimeEvent {
  final dynamic error;
  final StackTrace? stackTrace;
  RuntimeErrorEvent(this.error, this.stackTrace);
}

class ProcessStartedEvent extends RuntimeEvent {
  final String processId;
  ProcessStartedEvent(this.processId);
}

class ProcessCompletedEvent extends RuntimeEvent {
  final String processId;
  final ProcessState state;
  ProcessCompletedEvent(this.processId, this.state);
}

/// Main MCP Flow Runtime
class McpFlowRuntime {
  final Logger _logger = Logger('McpFlowRuntime');
  final RuntimeConfig config;
  final EventBus _eventBus = EventBus();
  
  late final HardwareAbstractionLayer _hal;
  late final StateManager _stateManager;
  late final ProcessScheduler _scheduler;
  late final ProcessExecutor _executor;
  
  FlowDefinition? _flowDefinition;
  RuntimeStatus _status = RuntimeStatus.stopped;
  DateTime? _startTime;
  
  final Map<String, StreamController> _channels = {};
  final Map<String, dynamic> _resources = {};
  
  McpFlowRuntime({
    RuntimeConfig? config,
    HardwareAbstractionLayer? hal,
  }) : config = config ?? const RuntimeConfig() {
    _hal = hal ?? HalFactory().createHal();
    _stateManager = StateManager();
    _scheduler = ProcessScheduler(
      maxProcesses: this.config.maxProcesses,
      tickRateMs: this.config.tickRateMs,
    );
    _executor = ProcessExecutor(
      hal: _hal,
      stateManager: _stateManager,
      channels: _channels,
      resources: _resources,
      config: this.config,
    );
  }

  /// Get runtime status
  RuntimeStatus get status => _status;
  
  /// Get event bus for monitoring
  EventBus get eventBus => _eventBus;
  
  /// Get state event bus for monitoring state changes
  EventBus get stateEventBus => _stateManager.eventBus;
  
  /// Get runtime statistics
  RuntimeStatistics getStatistics() {
    final now = DateTime.now();
    final uptime = _startTime != null ? now.difference(_startTime!) : Duration.zero;
    
    return RuntimeStatistics(
      status: _status,
      startedAt: _startTime ?? now,
      uptime: uptime,
      totalProcesses: _scheduler.totalProcesses,
      activeProcesses: _scheduler.activeProcesses,
      completedProcesses: _scheduler.completedProcesses,
      errorProcesses: _scheduler.errorProcesses,
      resourceUsage: _getResourceUsage(),
      actionCounts: _executor.actionCounts,
    );
  }

  /// Load flow definition from JSON
  Future<void> loadFlow(Map<String, dynamic> json) async {
    _logger.info('Loading flow definition');
    
    try {
      // Parse JSON
      final parser = JsonFlowParser();
      final flow = parser.parse(json);
      
      // Validate flow
      final validator = FlowValidator();
      final errors = validator.validate(flow);
      
      if (errors.isNotEmpty) {
        throw FlowValidationError(
          'Flow validation failed with ${errors.length} errors',
          field: 'flow',
          value: errors,
        );
      }
      
      _flowDefinition = flow;
      await _initializeFlow(flow);
      
      _logger.info('Flow loaded successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to load flow', e, stackTrace);
      rethrow;
    }
  }

  /// Load flow from file
  Future<void> loadFlowFromFile(String path) async {
    final parser = JsonFlowParser();
    final json = await parser.loadFromFile(path);
    await loadFlow(json);
  }

  /// Start the runtime
  Future<void> start() async {
    if (_status != RuntimeStatus.stopped) {
      throw FlowError('Runtime is already running or starting');
    }
    
    _logger.info('Starting runtime');
    _status = RuntimeStatus.starting;
    
    try {
      // Initialize HAL
      await _hal.initialize();
      
      // Initialize state manager
      await _stateManager.initialize();
      
      // Start scheduler
      await _scheduler.start();
      
      // Schedule startup processes
      if (_flowDefinition != null) {
        await _scheduleStartupProcesses();
      }
      
      _status = RuntimeStatus.running;
      _startTime = DateTime.now();
      _eventBus.fire(RuntimeStartedEvent());
      
      _logger.info('Runtime started successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to start runtime', e, stackTrace);
      _status = RuntimeStatus.error;
      _eventBus.fire(RuntimeErrorEvent(e, stackTrace));
      rethrow;
    }
  }

  /// Stop the runtime
  Future<void> stop() async {
    if (_status == RuntimeStatus.stopped) {
      return;
    }
    
    _logger.info('Stopping runtime');
    _status = RuntimeStatus.stopping;
    
    try {
      // Stop scheduler
      await _scheduler.stop();
      
      // Close channels
      for (final channel in _channels.values) {
        await channel.close();
      }
      _channels.clear();
      
      // Cleanup HAL
      await _hal.dispose();
      
      // Cleanup state manager
      await _stateManager.dispose();
      
      _status = RuntimeStatus.stopped;
      _eventBus.fire(RuntimeStoppedEvent());
      
      _logger.info('Runtime stopped successfully');
    } catch (e, stackTrace) {
      _logger.severe('Error during runtime shutdown', e, stackTrace);
      _status = RuntimeStatus.error;
      _eventBus.fire(RuntimeErrorEvent(e, stackTrace));
      rethrow;
    }
  }

  /// Execute a process manually
  Future<void> executeProcess(String processId, {Map<String, dynamic>? args}) async {
    if (_status != RuntimeStatus.running) {
      throw FlowError('Runtime is not running');
    }
    
    final flow = _flowDefinition;
    if (flow == null) {
      throw FlowError('No flow loaded');
    }
    
    final process = flow.processes.firstWhere(
      (p) => p.id == processId,
      orElse: () => throw FlowError('Process $processId not found'),
    );
    
    await _scheduleProcess(process, args: args);
  }

  /// Get state value
  dynamic getState(String name) {
    return _stateManager.get(name);
  }

  /// Set state value
  Future<void> setState(String name, dynamic value) async {
    await _stateManager.set(name, value);
  }

  /// Send data to a channel
  Future<void> sendToChannel(String channelName, dynamic data) async {
    final channel = _channels[channelName];
    if (channel == null) {
      throw FlowError('Channel $channelName not found');
    }
    
    channel.add(data);
  }

  /// Get channel stream
  Stream? getChannelStream(String channelName) {
    return _channels[channelName]?.stream;
  }

  // Private methods

  Future<void> _initializeFlow(FlowDefinition flow) async {
    // Initialize resources
    await _initializeResources(flow.resources);
    
    // Initialize state
    await _initializeState(flow.state);
    
    // Initialize channels
    if (flow.channels != null) {
      await _initializeChannels(flow.channels!);
    }
    
    // Setup event listeners
    _setupEventListeners(flow.events);
  }

  Future<void> _initializeResources(Map<String, ResourceDefinition> resources) async {
    for (final entry in resources.entries) {
      final name = entry.key;
      final resource = entry.value;
      
      _logger.fine('Initializing resource: $name');
      
      // Store resource configuration
      _resources[name] = {
        'type': resource.type,
        'config': resource.config,
        'capabilities': resource.capabilities,
      };
      
      // Initialize hardware resources
      if (resource.type == 'gpio' || 
          resource.type == 'i2c' || 
          resource.type == 'spi' ||
          resource.type == 'pwm' ||
          resource.type == 'uart' ||
          resource.type == 'adc' ||
          resource.type == 'modbus') {
        // Hardware resources are initialized on-demand by action executors
        _logger.fine('Hardware resource $name will be initialized on first use');
      }
    }
  }

  Future<void> _initializeState(Map<String, StateDefinition> state) async {
    for (final entry in state.entries) {
      final name = entry.key;
      final definition = entry.value;
      
      await _stateManager.defineVariable(
        name,
        type: definition.type,
        initial: definition.initial,
        persistent: definition.persistent,
        constraints: definition.constraints,
      );
    }
  }

  Future<void> _initializeChannels(Map<String, ChannelDefinition> channels) async {
    for (final entry in channels.entries) {
      final name = entry.key;
      final definition = entry.value;
      
      switch (definition.type) {
        case ChannelType.queue:
          _channels[name] = StreamController(
            sync: true,
            onListen: () => _logger.fine('Channel $name: listener added'),
            onCancel: () => _logger.fine('Channel $name: listener removed'),
          );
          break;
          
        case ChannelType.pubsub:
          _channels[name] = StreamController.broadcast(
            sync: true,
            onListen: () => _logger.fine('Channel $name: listener added'),
            onCancel: () => _logger.fine('Channel $name: listener removed'),
          );
          break;
          
        default:
          _logger.warning('Unsupported channel type: ${definition.type}');
      }
    }
  }

  void _setupEventListeners(List<EventDefinition>? events) {
    if (events == null) return;
    
    // Setup event-triggered processes
    for (final event in events) {
      _logger.fine('Setting up event listener: ${event.id}');
      // Event listeners would be implemented based on event source
    }
  }

  Future<void> _scheduleStartupProcesses() async {
    final flow = _flowDefinition!;
    
    for (final process in flow.processes) {
      if (!process.enabled) continue;
      
      if (process.trigger?.type == TriggerType.startup) {
        await _scheduleProcess(process);
      }
    }
  }

  Future<void> _scheduleProcess(
    ProcessDefinition process, {
    Map<String, dynamic>? args,
  }) async {
    final instance = ProcessInstance(
      id: '${process.id}_${DateTime.now().millisecondsSinceEpoch}',
      definition: process,
      variables: args ?? {},
    );
    
    // Setup process execution
    final completer = Completer<void>();
    
    _scheduler.schedule(
      instance,
      priority: _getPriorityValue(process.priority),
      onExecute: () async {
        try {
          _eventBus.fire(ProcessStartedEvent(instance.id));
          await _executor.execute(instance);
          _eventBus.fire(ProcessCompletedEvent(instance.id, instance.state));
          completer.complete();
        } catch (e, stackTrace) {
          instance.state = ProcessState.error;
          instance.lastError = e;
          _eventBus.fire(ProcessCompletedEvent(instance.id, ProcessState.error));
          completer.completeError(e, stackTrace);
        }
      },
    );
    
    // Handle process triggers
    if (process.trigger != null) {
      await _setupProcessTrigger(process, instance);
    }
  }

  Future<void> _setupProcessTrigger(
    ProcessDefinition process,
    ProcessInstance instance,
  ) async {
    final trigger = process.trigger!;
    
    switch (trigger.type) {
      case TriggerType.schedule:
        if (trigger.interval != null) {
          Timer.periodic(
            Duration(milliseconds: trigger.interval!),
            (_) => _scheduleProcess(process),
          );
        }
        break;
        
      case TriggerType.condition:
        if (trigger.condition != null) {
          // Monitor condition and trigger when true
          Timer.periodic(
            Duration(milliseconds: config.tickRateMs),
            (_) async {
              if (await _evaluateCondition(trigger.condition!)) {
                await _scheduleProcess(process);
              }
            },
          );
        }
        break;
        
      default:
        // Other trigger types handled elsewhere
        break;
    }
  }

  Future<bool> _evaluateCondition(String condition) async {
    // TODO: Implement expression evaluation
    return false;
  }

  int _getPriorityValue(ProcessPriority priority) {
    switch (priority) {
      case ProcessPriority.low:
        return 0;
      case ProcessPriority.normal:
        return 1;
      case ProcessPriority.high:
        return 2;
      case ProcessPriority.realtime:
        return 3;
    }
  }

  ResourceUsage _getResourceUsage() {
    // TODO: Implement actual resource monitoring
    return ResourceUsage(
      memoryBytes: 0,
      cpuPercent: 0.0,
      ioOperations: 0,
      networkConnections: 0,
      timestamp: DateTime.now(),
    );
  }
}