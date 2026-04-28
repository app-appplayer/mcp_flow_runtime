/// Core MCP Flow Runtime engine

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:event_bus/event_bus.dart';
import 'package:cron/cron.dart' as cron_pkg;

import '../types/flow_types.dart';
import '../types/runtime_types.dart';
import '../types/hardware_types.dart';
import '../errors/flow_errors.dart' as flow_errors;
import '../errors/flow_errors.dart' show FlowValidationError, ConcreteFlowError;
import '../hal/hal_interface.dart';
import '../hal/hal_factory.dart';
import '../hal/mock_hal_factory.dart';
import '../hal/providers/mqtt_provider.dart';
import '../state/state_manager.dart';
import '../state/state_store.dart';
import '../parser/json_parser.dart';
import '../parser/validator.dart';
import 'scheduler.dart';
import 'process_executor.dart';
import 'action_executor.dart';
import '../expression/expression_evaluator.dart';
import 'package:expressions/expressions.dart';
import '../channels/channel_interface.dart';
import '../utils/debounce.dart';
import 'watchdog.dart';
import '../state/encrypted_state_store.dart';
import 'backup_manager.dart';
import '../services/service_manager.dart';
import 'circuit_breaker.dart';
import '../mcp/client_capabilities.dart';

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

/// Flow event for custom events
class FlowEvent extends RuntimeEvent {
  final String name;
  final dynamic data;
  FlowEvent(this.name, {this.data});
}

/// Resource event from hardware resources
class ResourceEvent extends RuntimeEvent {
  final String resource;
  final String event;
  final dynamic data;
  ResourceEvent(this.resource, this.event, {this.data});
}

/// MCP notify event for external notifications
class McpNotifyEvent extends RuntimeEvent {
  final String resource;
  final String event;
  final dynamic data;
  McpNotifyEvent({
    required this.resource,
    required this.event,
    this.data,
  });
}

/// Main MCP Flow Runtime
class McpFlowRuntime {
  final Logger _logger = Logger('McpFlowRuntime');
  final RuntimeConfig config;
  final EventBus _eventBus = EventBus();
  
  late final HardwareAbstractionLayer _hal;
  late StateManager _stateManager;
  late final ProcessScheduler _scheduler;
  late ProcessExecutor _executor;
  
  FlowDefinition? _flowDefinition;
  RuntimeStatus _status = RuntimeStatus.created;
  DateTime? _startTime;
  
  final Map<String, Channel> _channels = {};
  final Map<String, Timer> _scheduledTimers = {};
  final Map<String, cron_pkg.Cron> _cronJobs = {};
  final Map<String, dynamic> _resources = {};
  final Set<String> _stoppedProcesses = {};
  final Map<String, String> _configEnvironment = {};
  final Map<String, Debouncer> _debouncers = {};
  final List<StreamSubscription> _channelSubscriptions = [];
  
  ProcessWatchdog? _processWatchdog;
  RuntimeWatchdog? _runtimeWatchdog;
  Timer? _runtimeHeartbeatTimer;
  
  McpConfig? _mcpConfig;
  BackupManager? _backupManager;
  ClientCapabilityDetector? _clientCapabilityDetector;
  
  final CircuitBreakerManager _circuitBreakerManager = CircuitBreakerManager();
  
  McpFlowRuntime({
    RuntimeConfig? config,
    HardwareAbstractionLayer? hal,
    StateStore? stateStore,
    BackupManager? backupManager,
  }) : config = config ?? const RuntimeConfig(),
       _backupManager = backupManager {
    _hal = hal ?? HalFactory().createHal();
    _stateManager = StateManager(store: stateStore);
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
      configEnvironment: _configEnvironment,
      circuitBreakerManager: _circuitBreakerManager,
      mcpConfig: _mcpConfig,
      emitEventCallback: (event, [data]) {
        emitEvent(event, data: data);
      },
      executeProcessCallback: (processId, args) async {
        await executeProcess(processId, args: args);
      },
      stopProcessCallback: (processId) async {
        await stopProcess(processId);
      },
      watchdogHeartbeatCallback: (processId) {
        _processWatchdog?.heartbeat(processId);
      },
    );
  }

  /// Get runtime status
  RuntimeStatus get status => _status;
  
  /// Get event bus for monitoring
  EventBus get eventBus => _eventBus;
  
  /// Get state event bus for monitoring state changes
  EventBus get stateEventBus => _stateManager.eventBus;

  /// Load flow definition from a JSON string
  Future<void> loadFlowFromJson(String jsonString) async {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return loadFlow(json);
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
      final allIssues = validator.validate(flow);
      final errors = allIssues.where((e) => e.severity == ValidationSeverity.error).toList();
      final warnings = allIssues.where((e) => e.severity == ValidationSeverity.warning).toList();

      // Log warnings
      for (final warning in warnings) {
        _logger.warning('Validation warning: $warning');
      }

      if (errors.isNotEmpty) {
        // Log validation errors for debugging
        for (final error in errors) {
          _logger.severe('Validation error: $error');
        }
        // Convert validator errors to flow error types
        final flowErrors = errors.map((e) => flow_errors.ValidationError(
          code: e.code,
          message: e.message,
          path: e.path,
        )).toList();
        throw FlowValidationError(
          'Flow validation failed with ${errors.length} errors (${errors.length} error(s))',
          errors: flowErrors,
        );
      }
      
      // Check if this is a minimal flow for dynamic state definition
      // Minimal flows are used by flowos_core for dynamic state creation
      final isMinimalFlow = flow.processes.isEmpty && 
                           flow.state.isNotEmpty &&
                           flow.metadata?.name == 'Dynamic State';
      
      // Handle state preservation on flow reload (but not for minimal flows)
      if (_flowDefinition != null && !isMinimalFlow) {
        _logger.info('Reloading flow - handling state preservation');
        
        // Backup persistent states before clearing
        final persistentStates = <String, dynamic>{};
        final allStates = _stateManager.toMap();
        
        // Check current flow's state definitions for persistent flags
        if (_flowDefinition!.state.isNotEmpty) {
          for (final entry in _flowDefinition!.state.entries) {
            if (entry.value.persistent && allStates.containsKey(entry.key)) {
              persistentStates[entry.key] = allStates[entry.key];
              _logger.fine('Preserving persistent state: ${entry.key}');
            }
          }
        }
        
        // Clear all state variables
        await _stateManager.clear();
        
        // Clear variable definitions for clean reload
        _stateManager.clearVariableDefinitions();
        
        // Load new flow
        _flowDefinition = flow;
        _executor.flowDefinition = flow;
        await _initializeFlow(flow, json);

        // Restore persistent states if they exist in new flow
        for (final entry in persistentStates.entries) {
          if (flow.state.containsKey(entry.key) && flow.state[entry.key]!.persistent) {
            try {
              await _stateManager.set(entry.key, entry.value);
              _logger.fine('Restored persistent state: ${entry.key} = ${entry.value}');
            } catch (e) {
              _logger.warning('Failed to restore persistent state ${entry.key}: $e');
            }
          }
        }
      } else if (isMinimalFlow && _flowDefinition != null) {
        // Minimal flow - just add the new state definitions without clearing existing ones
        _logger.info('Loading minimal flow for dynamic state definition');
        
        // Only initialize the new state variables
        for (final entry in flow.state.entries) {
          final name = entry.key;
          final def = entry.value;
          
          // Define the state variable if it doesn't exist
          if (!_stateManager.hasState(name)) {
            await _stateManager.defineVariable(
              name,
              type: def.type,
              initial: def.initial,
              persistent: def.persistent,
              constraints: def.constraints,
              security: def.security,
            );
            _logger.fine('Defined dynamic state variable: $name');
          }
        }
        
        // Don't update _flowDefinition for minimal flows
      } else {
        // First time loading
        _flowDefinition = flow;
        _executor.flowDefinition = flow;
        await _initializeFlow(flow, json);
      }

      // Initialize MCP configuration if present
      final mcpConfigData = flow.configuration?.mcp;
      if (mcpConfigData != null) {
        _mcpConfig = mcpConfigData;
        _logger.info('MCP configuration loaded: mode=${_mcpConfig!.mode.name}');
        
        // Initialize client capability detector
        _clientCapabilityDetector = ClientCapabilityDetector();
        
        // Update ProcessExecutor with new MCP config
        _executor = ProcessExecutor(
          hal: _hal,
          stateManager: _stateManager,
          channels: _channels,
          resources: _resources,
          config: config,
          configEnvironment: _configEnvironment,
          circuitBreakerManager: _circuitBreakerManager,
          mcpConfig: _mcpConfig,
          emitEventCallback: (event, [data]) {
            emitEvent(event, data: data);
          },
          executeProcessCallback: (processId, args) async {
            await executeProcess(processId, args: args);
          },
          stopProcessCallback: (processId) async {
            await stopProcess(processId);
          },
          watchdogHeartbeatCallback: (processId) {
            _processWatchdog?.heartbeat(processId);
          },
        );
      }

      // If runtime is running and we just loaded a new flow with processes,
      // reinitialize the processes (triggers) for the new flow
      if (_status == RuntimeStatus.running && !isMinimalFlow) {
        _logger.info('Runtime is running - reinitializing processes for new flow');
        await _reinitializeProcesses();
      }

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
    if (_status != RuntimeStatus.created && _status != RuntimeStatus.stopped) {
      throw ConcreteFlowError('RUNTIME_ERROR', 'Runtime is already running or starting');
    }
    
    _logger.info('Starting runtime');
    _status = RuntimeStatus.starting;
    
    try {
      // Initialize HAL
      await _hal.initialize();
      
      // Initialize hardware resources after HAL is ready
      await _initializeHardwareResources();
      
      // Initialize state manager
      await _stateManager.initialize();
      
      // Start scheduler
      await _scheduler.start();
      
      // Initialize all processes (startup, schedule, etc.)
      if (_flowDefinition != null) {
        await _initializeProcesses();
      }
      
      // Initialize watchdog if configured
      _initializeWatchdog();
      
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
      
      // Cancel all scheduled timers
      for (final timer in _scheduledTimers.values) {
        timer.cancel();
      }
      _scheduledTimers.clear();
      
      // Close all cron jobs
      for (final cron in _cronJobs.values) {
        cron.close();
      }
      _cronJobs.clear();
      
      // Dispose all debouncers
      for (final debouncer in _debouncers.values) {
        debouncer.dispose();
      }
      _debouncers.clear();
      
      // Stop watchdog
      _runtimeHeartbeatTimer?.cancel();
      _runtimeHeartbeatTimer = null;
      _processWatchdog?.dispose();
      _processWatchdog = null;
      _runtimeWatchdog?.dispose();
      _runtimeWatchdog = null;
      
      // Cancel all channel subscriptions
      for (final subscription in _channelSubscriptions) {
        await subscription.cancel();
      }
      _channelSubscriptions.clear();
      
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
      throw ConcreteFlowError('RUNTIME_ERROR','Runtime is not running');
    }
    
    final flow = _flowDefinition;
    if (flow == null) {
      throw ConcreteFlowError('RUNTIME_ERROR','No flow loaded');
    }
    
    final process = flow.processes.firstWhere(
      (p) => p.id == processId,
      orElse: () => throw ConcreteFlowError('RUNTIME_ERROR','Process $processId not found'),
    );
    
    await _scheduleProcess(process, args: args);
  }

  /// Stop a running process
  Future<void> stopProcess(String processId) async {
    if (_status != RuntimeStatus.running) {
      throw ConcreteFlowError('RUNTIME_ERROR','Runtime is not running');
    }
    
    // Mark the process as stopped to prevent re-scheduling
    _stoppedProcesses.add(processId);
    
    // Cancel all instances of the process by definition ID
    final stopped = _scheduler.cancelByDefinitionId(processId);
    
    if (stopped) {
      _logger.info('Stopped process: $processId');
      // Fire event for the process definition, not specific instances
      _eventBus.fire(ProcessCompletedEvent(processId, ProcessState.completed));
    } else {
      _logger.info('Process $processId marked as stopped (no active instances)');
    }
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
      throw ConcreteFlowError('RUNTIME_ERROR','Channel $channelName not found');
    }
    
    await channel.send(data);
  }

  /// Get channel stream
  Stream? getChannelStream(String channelName) {
    return _channels[channelName]?.stream;
  }

  /// Emit a custom event
  void emitEvent(String name, {dynamic data}) {
    _eventBus.fire(FlowEvent(name, data: data));
    _logger.fine('Emitted event: $name');
  }

  /// Create a backup of the current configuration and state
  Future<BackupMetadata> createBackup({
    String? description,
    Map<String, dynamic>? tags,
    bool includeState = true,
    bool includeRuntimeConfig = false,
  }) async {
    if (_flowDefinition == null) {
      throw ConcreteFlowError('RUNTIME_ERROR','No flow loaded to backup');
    }
    
    // Initialize backup manager if not provided
    _backupManager ??= BackupManager(
      backupDirectory: 'backups',
      maxBackups: 10,
    );
    
    // Collect current state if requested
    Map<String, dynamic>? state;
    if (includeState) {
      state = _stateManager.toMap();
    }
    
    // Collect runtime config if requested
    Map<String, dynamic>? runtimeConfig;
    if (includeRuntimeConfig) {
      runtimeConfig = config.toJson();
    }
    
    return await _backupManager!.createBackup(
      flow: _flowDefinition!,
      state: state,
      runtimeConfig: runtimeConfig,
      description: description,
      tags: tags,
    );
  }
  
  /// List available backups
  Future<List<BackupMetadata>> listBackups() async {
    _backupManager ??= BackupManager(
      backupDirectory: 'backups',
      maxBackups: 10,
    );
    
    return await _backupManager!.listBackups();
  }
  
  /// Restore from a backup
  Future<void> restoreBackup(String backupId, {
    bool restoreState = true,
    bool restoreRuntimeConfig = false,
  }) async {
    _backupManager ??= BackupManager(
      backupDirectory: 'backups',
      maxBackups: 10,
    );
    
    final backup = await _backupManager!.restoreBackup(backupId);
    
    // Stop runtime if running
    if (_status == RuntimeStatus.running) {
      await stop();
    }
    
    // Clear existing flow definition to allow reloading
    _flowDefinition = null;
    
    // Clear runtime state
    _resources.clear();
    _channels.clear();
    _stoppedProcesses.clear();
    _configEnvironment.clear();
    
    // Create new state manager to ensure clean state
    _stateManager = StateManager(store: _stateManager.store);
    
    // Load the flow
    await loadFlow(backup.flow.toJson());
    
    // Restore state if requested and available
    if (restoreState && backup.state != null) {
      for (final entry in backup.state!.entries) {
        if (_stateManager.hasVariable(entry.key)) {
          await _stateManager.set(entry.key, entry.value);
        }
      }
      _logger.info('Restored state from backup');
    }
    
    // Apply runtime config if requested and available
    if (restoreRuntimeConfig && backup.runtimeConfig != null) {
      // Note: Runtime config is immutable after construction
      _logger.info('Runtime config in backup (not applied): ${backup.runtimeConfig}');
    }
    
    _logger.info('Restored from backup: $backupId');
  }
  
  /// Delete a backup
  Future<void> deleteBackup(String backupId) async {
    _backupManager ??= BackupManager(
      backupDirectory: 'backups',
      maxBackups: 10,
    );
    
    await _backupManager!.deleteBackup(backupId);
  }
  
  /// Export backup to file
  Future<void> exportBackup(String backupId, String exportPath) async {
    _backupManager ??= BackupManager(
      backupDirectory: 'backups',
      maxBackups: 10,
    );
    
    await _backupManager!.exportBackup(backupId, exportPath);
  }
  
  /// Import backup from file
  Future<BackupMetadata> importBackup(String importPath) async {
    _backupManager ??= BackupManager(
      backupDirectory: 'backups',
      maxBackups: 10,
    );
    
    return await _backupManager!.importBackup(importPath);
  }
  
  /// Emit a resource event
  void emitResourceEvent(String resource, String event, {dynamic data}) {
    // In extended MCP mode, include full resource data
    dynamic eventData = data;
    if (_mcpConfig?.mode == McpMode.extended && _mcpConfig?.extendedData != false) {
      // Get resource value for extended data
      final resourceDef = _flowDefinition?.resources[resource];
      if (resourceDef != null && _resources.containsKey(resource)) {
        final resourceValue = _resources[resource];
        eventData = {
          'uri': resourceDef.mcp?.resource?.uri ?? 'resource://$resource',
          'value': resourceValue,
          'metadata': {
            'type': resourceDef.type,
            'capabilities': resourceDef.capabilities,
            'timestamp': DateTime.now().toIso8601String(),
          },
          if (data != null) 'eventData': data,
        };
      }
    }
    
    _eventBus.fire(ResourceEvent(resource, event, data: eventData));
    _logger.fine('Emitted resource event: $resource.$event' + 
                 (_mcpConfig?.mode == McpMode.extended ? ' (extended mode)' : ''));
  }

  // Private methods
  
  /// Creates a potentially debounced trigger handler
  void Function() _createTriggerHandler(
    ProcessDefinition process,
    TriggerDefinition trigger,
    void Function() handler,
  ) {
    final debounceMs = trigger.debounceMs;
    if (debounceMs != null && debounceMs > 0) {
      // Create or reuse a debouncer for this specific trigger
      final key = '${process.id}_trigger_${trigger.type}_${trigger.hashCode}';
      _debouncers[key] ??= Debouncer(delay: Duration(milliseconds: debounceMs));
      return () => _debouncers[key]!.call(handler);
    }
    return handler;
  }

  Future<void> _initializeFlow(FlowDefinition flow, Map<String, dynamic> json) async {
    // IMPORTANT: Initialize encrypted state store BEFORE applying configuration
    // This ensures persistent values are loaded with the correct encryption
    await _initializeStateStore(flow);
    
    // Apply runtime configuration
    if (flow.configuration != null) {
      _applyConfiguration(flow.configuration!);
    }
    
    // Initialize resources
    await _initializeResources(flow.resources);
    
    // Initialize state
    await _initializeState(flow.state);
    
    // Initialize channels
    if (flow.channels.isNotEmpty) {
      await _initializeChannels(flow.channels);
    }
    
    // Store flow config in global state for barrier configuration
    // Check if already defined to support flow reloading
    if (!_stateManager.hasVariable('__flow_config')) {
      await _stateManager.defineVariable('__flow_config', 
        type: StateType.object, initial: json);
    }
    await _stateManager.set('__flow_config', json);
    
    // Initialize synchronization primitives from raw JSON
    final syncData = json['synchronization'] as Map<String, dynamic>?;
    if (syncData != null) {
      await _initializeSynchronizationFromJson(syncData);
    }
    
    // Setup event listeners
    _setupEventListeners(flow.events);
  }

  void _applyConfiguration(FlowConfiguration configuration) {
    // Apply runtime limits configuration
    final runtimeLimits = configuration.runtime;
    if (runtimeLimits != null) {
      final tickRateMs = runtimeLimits.tickRateMs;
      final maxProcesses = runtimeLimits.maxProcesses;
      final maxMemoryKB = runtimeLimits.maxMemoryKB;

      if (tickRateMs != null) {
        _scheduler.setTickRate(Duration(milliseconds: tickRateMs));
        _logger.fine('Set scheduler tick rate to ${tickRateMs}ms');
      }

      if (maxProcesses != null) {
        _scheduler.setMaxProcesses(maxProcesses);
        _logger.fine('Set max processes to $maxProcesses');
      }

      if (maxMemoryKB != null) {
        // Store for monitoring
        _logger.fine('Set max memory to ${maxMemoryKB}KB');
      }
    }

    // Apply system configuration
    final systemConfig = configuration.system;
    if (systemConfig != null) {
      // Store system configuration for later use
      _logger.fine('System configuration loaded');

      // Apply environment variables from system config
      final environment = systemConfig['environment'] as Map<String, dynamic>?;
      if (environment != null) {
        _configEnvironment.clear();
        for (final entry in environment.entries) {
          _configEnvironment[entry.key] = entry.value.toString();
        }
        _logger.fine('Loaded ${_configEnvironment.length} environment variables');
      }
    }
  }

  Future<void> _initializeStateStore(FlowDefinition flow) async {
    // Check if we need encrypted state
    bool needsEncryption = false;
    for (final entry in flow.state.entries) {
      final security = entry.value.security;
      if (security?.encrypted == true) {
        needsEncryption = true;
        break;
      }
    }
    
    // If encryption is needed or persistence is configured, create appropriate store
    final systemConfig = flow.configuration?.system;
    final persistenceConfig = systemConfig?['persistence'] as Map<String, dynamic>?;
    final storeType = persistenceConfig?['type'] as String?;

    if (needsEncryption || storeType != null) {
      final actualStoreType = storeType ?? 'memory';
      final storeConfig = persistenceConfig?['config'] as Map<String, dynamic>?;

      // Get master key from configuration if provided
      final securityConfig = systemConfig?['security'] as Map<String, dynamic>?;
      final encryptionConfig = securityConfig?['encryption'] as Map<String, dynamic>?;
      final masterKey = encryptionConfig?['masterKey'] as String?;
      
      // Create store (encrypted if needed)
      final store = needsEncryption && masterKey != null
          ? EncryptedStateStoreFactory.createEncrypted(
              baseType: actualStoreType,
              encryptionKey: masterKey,
              config: storeConfig,
            )
          : StateStoreFactory.create(
              type: actualStoreType,
              config: storeConfig,
            );
      
      // Replace the state manager with one using the configured store
      await _stateManager.dispose();
      _stateManager = StateManager(store: store);
      await _stateManager.initialize();
      
      // Recreate the ProcessExecutor with the new StateManager
      _executor = ProcessExecutor(
        hal: _hal,
        stateManager: _stateManager,
        channels: _channels,
        resources: _resources,
        config: config,
        configEnvironment: _configEnvironment,
        circuitBreakerManager: _circuitBreakerManager,
        mcpConfig: _mcpConfig,
        emitEventCallback: (event, [data]) {
          emitEvent(event, data: data);
        },
        executeProcessCallback: (processId, args) async {
          await executeProcess(processId, args: args);
        },
        stopProcessCallback: (processId) async {
          await stopProcess(processId);
        },
        watchdogHeartbeatCallback: (processId) {
          _processWatchdog?.heartbeat(processId);
        },
      );
    }
  }

  Future<void> _initializeResources(Map<String, ResourceDefinition> resources) async {
    for (final entry in resources.entries) {
      final name = entry.key;
      final resource = entry.value;
      
      _logger.fine('Preparing resource: $name');
      
      // Store resource configuration for later initialization
      _resources[name] = {
        'type': resource.type,
        'config': resource.config,
        'capabilities': resource.capabilities,
      };
    }
  }

  Future<void> _initializeState(Map<String, StateDefinition> state) async {
    // Define all state variables
    for (final entry in state.entries) {
      final name = entry.key;
      final definition = entry.value;
      
      await _stateManager.defineVariable(
        name,
        type: definition.type,
        initial: definition.initial,
        persistent: definition.persistent,
        constraints: definition.constraints,
        security: definition.security,
      );
    }
    
    // Load persistent values after all variables are defined
    await _stateManager.loadPersistentValues();
  }

  Future<void> _initializeSynchronizationFromJson(Map<String, dynamic> syncData) async {
    // Store barrier counts
    final barriers = syncData['barriers'] as Map<String, dynamic>?;
    if (barriers != null) {
      _resources['__barriers__'] = {};
      for (final entry in barriers.entries) {
        final barrierConfig = entry.value as Map<String, dynamic>;
        final count = barrierConfig['count'] as int? ?? 2;
        _resources['__barriers__'][entry.key] = count;
        _logger.fine('Initialized barrier ${entry.key} with count $count');
      }
    }
    
    // Store mutex information
    final mutexes = syncData['mutexes'] as Map<String, dynamic>?;
    if (mutexes != null) {
      _resources['__mutexes__'] = mutexes;
    }
    
    // Store event information
    final events = syncData['events'] as Map<String, dynamic>?;
    if (events != null) {
      _resources['__events__'] = events;
    }
  }

  Future<void> _initializeChannels(Map<String, ChannelDefinition> channels) async {
    for (final entry in channels.entries) {
      final name = entry.key;
      final definition = entry.value;
      
      _channels[name] = ChannelFactory.create(name, definition);
      _logger.fine('Initialized ${definition.type} channel: $name');
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

  Future<void> _initializeProcesses() async {
    final flow = _flowDefinition!;
    
    // Check for auto-start configuration from system config
    var autoStartProcesses = flow.configuration?.system?['autoStart'] as List?;

    // Also check under system.autoStart nested format for backward compatibility
    final autoStartConfig = flow.configuration?.system?['autoStart'];
    if (autoStartConfig != null && autoStartConfig['enabled'] == true) {
      autoStartProcesses = autoStartConfig['processes'] as List?;
    }
    
    if (autoStartProcesses != null) {
      // Sort by priority
      final sorted = List.from(autoStartProcesses)
        ..sort((a, b) => (a['priority'] ?? 999).compareTo(b['priority'] ?? 999));
      
      for (final processConfig in sorted) {
        final processId = processConfig['processId'] as String? ?? processConfig['id'] as String?;
        if (processId == null) continue;
        
        // Find the process definition
        final process = flow.processes.firstWhere(
          (p) => p.id == processId,
          orElse: () => throw ConcreteFlowError('RUNTIME_ERROR','Auto-start process $processId not found'),
        );
        
        if (!process.enabled) continue;
        
        final delay = processConfig['delay'] as int? ?? 0;
        final critical = processConfig['critical'] as bool? ?? false;
        
        try {
          // Schedule with delay if specified
          if (delay > 0) {
            await Future.delayed(Duration(milliseconds: delay));
          }
          
          await _scheduleProcess(process);
          _logger.info('Auto-started process: $processId');
        } catch (e) {
          _logger.severe('Failed to auto-start process $processId', e);
          if (critical) {
            throw ConcreteFlowError('RUNTIME_ERROR','Critical auto-start process $processId failed: $e');
          }
        }
      }
    }
    
    // Initialize all processes based on their trigger types
    for (final process in flow.processes) {
      if (!process.enabled) continue;
      
      // Collect trigger (singular per Spec)
      final triggers = <TriggerDefinition>[];
      if (process.trigger != null) {
        triggers.add(process.trigger!);
      }
      
      // If no triggers specified, treat as manual trigger
      if (triggers.isEmpty) {
        continue;
      }
      
      // Initialize each trigger
      for (final trigger in triggers) {
        switch (trigger.type) {
          case TriggerType.startup:
            // Schedule immediately with trigger context (don't await to allow parallel startup)
            _logger.info('Scheduling startup trigger for process ${process.id}');
            _scheduleProcess(process, args: {
              'trigger': {
                'type': 'startup'
              }
            });
            break;
            
          case TriggerType.schedule:
            // Setup periodic scheduling
            final timerKey = '${process.id}_schedule_${triggers.indexOf(trigger)}';
            
            if (trigger.cron != null) {
              // Handle cron-based scheduling
              try {
                final cron = cron_pkg.Cron();
                final schedule = cron_pkg.Schedule.parse(trigger.cron!);
                
                // Handle initial delay if specified
                if (trigger.delay != null && trigger.delay! > 0) {
                  Timer(Duration(milliseconds: trigger.delay!), () {
                    if (_status == RuntimeStatus.running) {
                      // Schedule cron job after delay
                      cron.schedule(schedule, () async {
                        if (_status == RuntimeStatus.running) {
                          await _scheduleProcess(process, args: {
                            'trigger': {
                              'type': 'schedule',
                              'cron': trigger.cron,
                              'delay': trigger.delay
                            }
                          });
                        }
                      });
                      
                      // Store cron instance for cleanup
                      _cronJobs[timerKey] = cron;
                    }
                  });
                } else {
                  // No delay, start cron scheduling immediately
                  cron.schedule(schedule, () async {
                    if (_status == RuntimeStatus.running) {
                      await _scheduleProcess(process, args: {
                        'trigger': {
                          'type': 'schedule',
                          'cron': trigger.cron
                        }
                      });
                    }
                  });
                  
                  // Store cron instance for cleanup
                  _cronJobs[timerKey] = cron;
                }
                
                _logger.info('Scheduled process ${process.id} with cron expression "${trigger.cron}"' +
                            (trigger.delay != null ? ' and initial delay ${trigger.delay}ms' : ''));
              } catch (e) {
                _logger.warning('Invalid cron expression "${trigger.cron}" for process ${process.id}: $e');
              }
            } else if (trigger.interval != null) {
              // Handle interval-based scheduling
              // Handle initial delay if specified
              if (trigger.delay != null && trigger.delay! > 0) {
                // Schedule first execution after delay
                Timer(Duration(milliseconds: trigger.delay!), () {
                  // Only schedule if runtime is still running
                  if (_status == RuntimeStatus.running) {
                    _scheduleProcess(process, args: {
                      'trigger': {
                        'type': 'schedule',
                        'interval': trigger.interval,
                        'delay': trigger.delay
                      }
                    });
                    
                    // Then start periodic scheduling
                    _scheduledTimers[timerKey] = Timer.periodic(
                      Duration(milliseconds: trigger.interval!),
                      (_) {
                        // Only schedule if runtime is still running
                        if (_status == RuntimeStatus.running) {
                          _scheduleProcess(process, args: {
                            'trigger': {
                              'type': 'schedule',
                              'interval': trigger.interval
                            }
                          });
                        }
                      },
                    );
                  }
                });
              } else {
                // No delay, start immediately
                _scheduledTimers[timerKey] = Timer.periodic(
                  Duration(milliseconds: trigger.interval!),
                  (_) {
                    // Only schedule if runtime is still running
                    if (_status == RuntimeStatus.running) {
                      _scheduleProcess(process, args: {
                        'trigger': {
                          'type': 'schedule',
                          'interval': trigger.interval
                        }
                      });
                    }
                  },
                );
              }
              _logger.info('Scheduled process ${process.id} with interval ${trigger.interval}ms' +
                          (trigger.delay != null ? ' and initial delay ${trigger.delay}ms' : ''));
            }
            break;
          
          case TriggerType.condition:
            // Setup condition monitoring
            if (trigger.condition != null) {
              final timerKey = '${process.id}_condition_${triggers.indexOf(trigger)}';
              // Track previous condition state
              bool previousConditionState = false;
              
              _scheduledTimers[timerKey] = Timer.periodic(
                Duration(milliseconds: config.tickRateMs),
                (_) async {
                  // Only check condition if runtime is still running
                  if (_status != RuntimeStatus.running) return;
                  
                  try {
                    final context = ExecutionContext(
                      process: ProcessInstance(
                        id: '${process.id}_condition_check',
                        definitionId: process.id,
                      ),
                      globalState: _stateManager.toMap(),
                      resources: _resources,
                      channels: _channels,
                      args: _getSystemVariables(),
                    );
                    
                    final currentConditionState = await _evaluateConditionWithContext(trigger.condition!, context);
                    
                    // Log condition evaluation for debugging
                    _logger.fine('Condition trigger evaluation for ${process.id}: '
                        'condition="${trigger.condition}" '
                        'current=$currentConditionState '
                        'previous=$previousConditionState '
                        'trigger_value=${context.globalState['trigger_value']}');
                    
                    // Only trigger if condition changed from false to true
                    if (currentConditionState && !previousConditionState) {
                      _logger.info('Condition trigger firing for ${process.id}: condition became true');
                      await _scheduleProcess(process, args: {
                        'trigger': {
                          'type': 'condition',
                          'condition': trigger.condition
                        }
                      });
                    }
                    
                    previousConditionState = currentConditionState;
                  } catch (e) {
                    _logger.warning('Error evaluating condition for process ${process.id}', e);
                  }
                },
              );
            }
            break;
          
          case TriggerType.event:
            // Event triggers listen for specific events
            final eventName = trigger.event;
          
          if (eventName != null) {
            // Listen to flow events on the event bus
            _eventBus.on<FlowEvent>().listen((event) {
              if (event.name == eventName) {
                final handler = _createTriggerHandler(process, trigger, () {
                  // Schedule process with trigger context and event data
                  final args = Map<String, dynamic>.from(event.data ?? {});
                  args['trigger'] = {
                    'type': 'event',
                    'event': eventName,
                    'data': event.data,
                  };
                  _scheduleProcess(process, args: args);
                });
                handler();
              }
            });
            _logger.info('Event trigger for process ${process.id} listening for event: $eventName${trigger.debounceMs != null ? ' (debounce: ${trigger.debounceMs}ms)' : ''}');
          }
          break;
          
        case TriggerType.channelReceive:
          // Channel receive triggers are set up with channel listeners
          final channelName = trigger.channel ?? trigger.event;
          
          if (channelName != null) {
            final controller = _channels[channelName];
            if (controller != null) {
              final subscription = controller.stream.listen((data) async {
                // Evaluate filter if present
                if (trigger.condition != null) {
                  // Create execution context with trigger data for filter evaluation
                  final filterContext = ExecutionContext(
                    process: ProcessInstance(
                      id: 'filter_eval_${process.id}',
                      definitionId: process.id,
                      state: ProcessState.ready,
                    ),
                    globalState: _stateManager.toMap(),
                    resources: _resources,
                    channels: _channels,
                    args: {
                      'trigger': {
                        'type': 'channelReceive',
                        'channel': channelName,
                        'data': data,
                      },
                      'message': data,
                    },
                  );
                  
                  try {
                    // Evaluate filter expression
                    final actionExecutor = ActionExecutor(
                      hal: _hal,
                      stateManager: _stateManager,
                      channels: _channels,
                      resources: _resources,
                      config: config,
                      configEnvironment: {},
                    );
                    final shouldTrigger = await actionExecutor.evaluateCondition(
                      trigger.condition!,
                      filterContext,
                    );
                    
                    if (!shouldTrigger) {
                      // Filter evaluated to false, skip this message
                      return;
                    }
                  } catch (e) {
                    _logger.warning('Failed to evaluate filter for process ${process.id}: $e');
                    return;
                  }
                }
                
                // Filter passed or no filter present, schedule process
                final handler = _createTriggerHandler(process, trigger, () {
                  // Schedule process with trigger context
                  _scheduleProcess(process, args: {
                    'trigger': {
                      'type': 'channelReceive',
                      'channel': channelName,
                      'data': data,
                    },
                    'message': data, // Also provide as 'message' for convenience
                  });
                });
                handler();
              });
              _channelSubscriptions.add(subscription);
              _logger.info('Channel receive trigger for process ${process.id} on channel $channelName${trigger.debounceMs != null ? ' (debounce: ${trigger.debounceMs}ms)' : ''}${trigger.condition != null ? ' (filtered)' : ''}');
            } else {
              _logger.warning('Channel $channelName not found for process ${process.id}');
            }
          }
          break;
          
        case TriggerType.stateChange:
          // State change triggers monitor specific state variables
          final variable = trigger.variable;
          
          if (variable != null) {
            // Listen to state change events for the specific variable
            _stateManager.eventBus.on<StateChangeEvent>().listen((event) async {
              if (event.variable == variable) {
                // Check filter if present
                if (trigger.condition != null) {
                  // Create execution context with trigger data for filter evaluation
                  final filterContext = ExecutionContext(
                    process: ProcessInstance(
                      id: 'filter_eval_${process.id}',
                      definitionId: process.id,
                      state: ProcessState.ready,
                    ),
                    globalState: _stateManager.toMap(),
                    resources: _resources,
                    channels: _channels,
                    args: {
                      'trigger': {
                        'type': 'stateChange',
                        'variable': variable,
                        'previousValue': event.oldValue,
                        'currentValue': event.newValue,
                      },
                      'oldValue': event.oldValue,
                      'newValue': event.newValue,
                    },
                  );
                  
                  try {
                    // Evaluate filter expression
                    final actionExecutor = ActionExecutor(
                      hal: _hal,
                      stateManager: _stateManager,
                      channels: _channels,
                      resources: _resources,
                      config: config,
                      configEnvironment: {},
                    );
                    final shouldTrigger = await actionExecutor.evaluateCondition(
                      trigger.condition!,
                      filterContext,
                    );
                    
                    if (!shouldTrigger) {
                      return; // Skip if filter doesn't match
                    }
                  } catch (e) {
                    _logger.warning('Error evaluating filter for stateChange trigger on ${process.id}: $e');
                    return; // Skip on filter evaluation error
                  }
                }
                
                final handler = _createTriggerHandler(process, trigger, () {
                  // Schedule process with trigger context
                  _scheduleProcess(process, args: {
                    'trigger': {
                      'type': 'stateChange',
                      'variable': variable,
                      'previousValue': event.oldValue,
                      'currentValue': event.newValue,
                    }
                  });
                });
                handler();
              }
            });
            _logger.info('State change trigger for process ${process.id} monitoring variable: $variable${trigger.debounceMs != null ? ' (debounce: ${trigger.debounceMs}ms)' : ''}${trigger.condition != null ? ' (filtered)' : ''}');
          } else if (trigger.condition != null) {
            // Fallback to condition-based monitoring
            final timerKey = '${process.id}_condition_${triggers.indexOf(trigger)}';
            _scheduledTimers[timerKey] = Timer.periodic(
              Duration(milliseconds: config.tickRateMs),
              (_) async {
                try {
                  final context = ExecutionContext(
                    process: ProcessInstance(
                      id: '${process.id}_condition_check',
                      definitionId: process.id,
                    ),
                    globalState: _stateManager.toMap(),
                    resources: _resources,
                    channels: _channels,
                    args: _getSystemVariables(),
                  );
                  
                  if (await _evaluateConditionWithContext(trigger.condition!, context)) {
                    await _scheduleProcess(process, args: {
                      'trigger': {
                        'type': 'stateChange',
                        'condition': trigger.condition
                      }
                    });
                  }
                } catch (e) {
                  _logger.warning('Error evaluating condition for process ${process.id}', e);
                }
              },
            );
          }
          break;
          
        case TriggerType.resourceEvent:
          // Resource event triggers listen for events from hardware resources
          final resourceName = trigger.resource;
          final eventName = trigger.event;
          
          if (resourceName != null && eventName != null) {
            // Listen to resource events on the event bus
            _eventBus.on<ResourceEvent>().listen((event) {
              if (event.resource == resourceName && event.event == eventName) {
                final handler = _createTriggerHandler(process, trigger, () {
                  // Schedule process with resource event context
                  _scheduleProcess(process, args: {
                    'trigger': {
                      'type': 'resourceEvent',
                      'resource': resourceName,
                      'event': eventName,
                      'data': event.data,
                    }
                  });
                });
                handler();
              }
            });
            _logger.info('Resource event trigger for process ${process.id} listening for $resourceName.$eventName${trigger.debounceMs != null ? ' (debounce: ${trigger.debounceMs}ms)' : ''}');
          }
          break;
          
        case TriggerType.manual:
        case null:
          // Manual triggers don't need setup
          break;
        }
      }
    }
  }

  /// Reinitialize processes when flow is reloaded while runtime is running
  /// This cleans up existing triggers and sets up new ones
  Future<void> _reinitializeProcesses() async {
    _logger.info('Reinitializing processes for flow reload');

    // Cancel all existing scheduled timers
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    _logger.fine('Cleared ${_scheduledTimers.length} scheduled timers');

    // Close all existing cron jobs
    for (final cron in _cronJobs.values) {
      cron.close();
    }
    _cronJobs.clear();
    _logger.fine('Cleared ${_cronJobs.length} cron jobs');

    // Dispose all debouncers
    for (final debouncer in _debouncers.values) {
      debouncer.dispose();
    }
    _debouncers.clear();
    _logger.fine('Cleared ${_debouncers.length} debouncers');

    // Cancel all channel subscriptions
    for (final subscription in _channelSubscriptions) {
      await subscription.cancel();
    }
    _channelSubscriptions.clear();
    _logger.fine('Cleared ${_channelSubscriptions.length} channel subscriptions');

    // Now reinitialize all processes with their triggers
    await _initializeProcesses();

    _logger.info('Process reinitialization complete');
  }

  Future<void> _scheduleProcess(
    ProcessDefinition process, {
    Map<String, dynamic>? args,
  }) async {
    final instance = ProcessInstance(
      id: '${process.id}_${DateTime.now().millisecondsSinceEpoch}',
      definitionId: process.id,
      localContext: args,
    );
    
    // Setup process execution
    final completer = Completer<void>();
    
    _scheduler.schedule(
      instance,
      priority: _getPriorityValue(process.priority),
      onExecute: () async {
        // Start watchdog monitoring for this process
        _processWatchdog?.startMonitoring(process.id);

        try {
          _eventBus.fire(ProcessStartedEvent(instance.id));
          await _executor.execute(instance);
          _eventBus.fire(ProcessCompletedEvent(instance.id, instance.state));

          // Stop watchdog monitoring on successful completion
          _processWatchdog?.stopMonitoring(process.id);

          // Handle loop processes
          if (process.loop && instance.state == ProcessState.ready) {
            // Check if the process has been stopped
            if (!_stoppedProcesses.contains(process.id)) {
              // Re-schedule the looping process
              await _scheduleProcess(process, args: args);
              _logger.fine('Re-scheduled looping process: ${process.id}');
            } else {
              _logger.info('Skipping re-schedule of stopped looping process: ${process.id}');
            }
          }

          completer.complete();
        } catch (e, stackTrace) {
          // Check if the process completed with handled error
          if (instance.state == ProcessState.completed) {
            // Error was handled by process error handlers
            completer.complete();
            return;
          }

          // Mark as error
          instance.state = ProcessState.error;
          instance.errorMessage = e;
          _eventBus.fire(ProcessCompletedEvent(instance.id, ProcessState.error));

          // Stop watchdog monitoring on error
          _processWatchdog?.stopMonitoring(process.id);

          completer.completeError(e, stackTrace);
        }
      },
    );
    
    // Wait for process completion when called from executeProcess (manual trigger)
    // or when explicitly needed for synchronous operations
    if (process.trigger == null || process.trigger!.type == TriggerType.manual) {
      return completer.future;
    }
  }

  Future<bool> _evaluateConditionWithContext(String condition, ExecutionContext context) async {
    try {
      // Create variable context
      final variables = <String, dynamic>{
        ...context.globalState,
        ...context.process.localContext,
        ...context.args,
        // Add 'state' object for accessing state variables
        'state': context.globalState,
      };

      // Log for debugging
      _logger.fine('Evaluating condition: "$condition" with state: ${context.globalState}');

      // Handle Flow DSL expression format (strip '=' prefix if present)
      String expressionStr = condition;
      if (expressionStr.startsWith('=')) {
        expressionStr = expressionStr.substring(1);
      }
      // Also handle double curly braces format
      if (expressionStr.startsWith('{{') && expressionStr.endsWith('}}')) {
        expressionStr = expressionStr.substring(2, expressionStr.length - 2);
      }

      // Parse and evaluate expression
      _logger.fine('Parsing expression: "$expressionStr"');
      final expr = Expression.parse(expressionStr);
      final evaluator = FlowExpressionEvaluator();
      final result = evaluator.eval(expr, variables);
      
      _logger.fine('Condition evaluation result: $result (${result.runtimeType})');
      
      if (result is bool) {
        return result;
      }
      // Truthy evaluation
      return result != null && result != 0 && result != '' && result != false;
    } catch (e) {
      _logger.warning('Failed to evaluate condition: $condition', e);
      return false;
    }
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

  Map<String, dynamic> _getSystemVariables() {
    return {
      'runtime': {
        'status': _status.toString(),
        'uptime': _startTime != null ? DateTime.now().difference(_startTime!).inSeconds : 0,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'tickRateMs': config.tickRateMs,
    };
  }

  ResourceUsage _getResourceUsage() {
    try {
      // Get memory usage from /proc/self/status (Linux)
      int memoryBytes = 0;
      double cpuPercent = 0.0;
      int ioOperations = 0;
      int networkConnections = 0;

      // Memory usage from /proc/self/status
      try {
        final statusFile = File('/proc/self/status');
        if (statusFile.existsSync()) {
          final content = statusFile.readAsStringSync();
          final vmRssMatch = RegExp(r'VmRSS:\s+(\d+)\s+kB').firstMatch(content);
          if (vmRssMatch != null) {
            memoryBytes = int.parse(vmRssMatch.group(1)!) * 1024; // Convert KB to bytes
          }
        }
      } catch (e) {
        _logger.fine('Failed to read memory usage: $e');
      }

      // CPU usage from /proc/self/stat
      try {
        final statFile = File('/proc/self/stat');
        if (statFile.existsSync()) {
          final content = statFile.readAsStringSync();
          final parts = content.split(' ');
          if (parts.length >= 15) {
            final utime = int.tryParse(parts[13]) ?? 0; // User time
            final stime = int.tryParse(parts[14]) ?? 0; // System time
            final totalTime = utime + stime;
            
            // Simple CPU usage estimation (would need previous values for accurate calculation)
            if (totalTime > 0) {
              cpuPercent = (totalTime / 100.0).clamp(0.0, 100.0);
            }
          }
        }
      } catch (e) {
        _logger.fine('Failed to read CPU usage: $e');
      }

      // I/O operations from /proc/self/io
      try {
        final ioFile = File('/proc/self/io');
        if (ioFile.existsSync()) {
          final content = ioFile.readAsStringSync();
          final readBytesMatch = RegExp(r'read_bytes:\s+(\d+)').firstMatch(content);
          final writeBytesMatch = RegExp(r'write_bytes:\s+(\d+)').firstMatch(content);
          
          int readBytes = readBytesMatch != null ? int.parse(readBytesMatch.group(1)!) : 0;
          int writeBytes = writeBytesMatch != null ? int.parse(writeBytesMatch.group(1)!) : 0;
          ioOperations = readBytes + writeBytes;
        }
      } catch (e) {
        _logger.fine('Failed to read I/O statistics: $e');
      }

      // Network connections from /proc/net/tcp and /proc/net/tcp6
      try {
        int tcpConnections = 0;
        final tcpFile = File('/proc/net/tcp');
        if (tcpFile.existsSync()) {
          final lines = tcpFile.readAsLinesSync();
          tcpConnections += lines.length - 1; // Subtract header line
        }
        
        final tcp6File = File('/proc/net/tcp6');
        if (tcp6File.existsSync()) {
          final lines = tcp6File.readAsLinesSync();
          tcpConnections += lines.length - 1; // Subtract header line
        }
        
        networkConnections = tcpConnections;
      } catch (e) {
        _logger.fine('Failed to read network connections: $e');
      }

      return ResourceUsage(
        memoryBytes: memoryBytes,
        cpuPercent: cpuPercent,
        ioOperations: ioOperations,
        networkConnections: networkConnections,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      _logger.warning('Failed to get resource usage: $e');
      return ResourceUsage(
        memoryBytes: 0,
        cpuPercent: 0.0,
        ioOperations: 0,
        networkConnections: 0,
        timestamp: DateTime.now(),
      );
    }
  }

  void _initializeWatchdog() {
    // Check if watchdog is configured in runtime config or flow config
    var watchdogConfig = WatchdogConfig();
    
    // Check runtime config
    if (config.watchdogIntervalMs != null) {
      watchdogConfig = WatchdogConfig(
        enabled: true,
        timeoutMs: config.watchdogIntervalMs!,
      );
    }
    
    // Check flow configuration (overrides runtime config)
    final flowWatchdog = _flowDefinition?.configuration?.system?['safety']?['watchdog'];
    if (flowWatchdog != null && flowWatchdog is Map<String, dynamic>) {
      watchdogConfig = WatchdogConfig.fromJson(flowWatchdog);
    }
    
    if (watchdogConfig.enabled) {
      _logger.info('Initializing watchdog with timeout: ${watchdogConfig.timeoutMs}ms');
      
      // Initialize process watchdog
      _processWatchdog = ProcessWatchdog(
        config: watchdogConfig,
        onTimeout: _handleProcessTimeout,
      );
      
      // Initialize runtime watchdog
      _runtimeWatchdog = RuntimeWatchdog(
        config: watchdogConfig,
        onSystemTimeout: _handleSystemTimeout,
      );
      _runtimeWatchdog!.start();
      
      // Start runtime heartbeat timer
      _runtimeHeartbeatTimer = Timer.periodic(
        Duration(milliseconds: watchdogConfig.timeoutMs ~/ 4),
        (_) => _runtimeWatchdog!.heartbeat(),
      );
    }
    
    // Start client cleanup timer if capability detection is enabled
    if (_clientCapabilityDetector != null) {
      Timer.periodic(Duration(minutes: 1), (_) {
        _clientCapabilityDetector!.cleanup();
      });
    }
  }
  
  void _handleProcessTimeout(String processId, String action) {
    _logger.warning('Process $processId watchdog timeout, action: $action');
    
    switch (action) {
      case 'restart_process':
        // Restart the process
        executeProcess(processId).catchError((e) {
          _logger.severe('Failed to restart process $processId after watchdog timeout', e);
        });
        break;
      case 'restart_runtime':
        // Restart the entire runtime
        _logger.severe('Critical process timeout, restarting runtime');
        stop().then((_) => start()).catchError((e) {
          _logger.severe('Failed to restart runtime after watchdog timeout', e);
        });
        break;
      case 'enter_safe_mode':
        // Enter safe mode - stop all non-critical processes
        _enterSafeMode();
        break;
      default:
        _logger.warning('Unknown watchdog action: $action');
    }
  }
  
  void _handleSystemTimeout(String action) {
    _logger.severe('Runtime watchdog timeout, action: $action');
    
    switch (action) {
      case 'restart_runtime':
        // Force restart
        _status = RuntimeStatus.error;
        stop().then((_) => start()).catchError((e) {
          _logger.severe('Failed to restart runtime after system watchdog timeout', e);
        });
        break;
      case 'enter_safe_mode':
        _enterSafeMode();
        break;
      default:
        _logger.warning('Unknown system watchdog action: $action');
    }
  }
  
  void _enterSafeMode() {
    _logger.warning('Entering safe mode due to errors or resource constraints');
    
    try {
      // 1. Stop all non-critical processes
      _scheduler.cancelAll();
      
      // 2. Reset HAL to safe state
      _resetHardwareToSafeState();
      
      // 3. Clear state variables except critical ones
      _clearNonCriticalState();
      
      // 4. Restart only critical processes marked with 'critical: true'
      _restartCriticalProcesses();
      
      // 5. Reduce resource usage
      _reduceResourceUsage();
      
      // 6. Enable minimal logging to conserve resources
      Logger.root.level = Level.WARNING;
      
      _logger.info('Safe mode activated - only critical processes running');
      
    } catch (e) {
      _logger.severe('Failed to enter safe mode: $e');
      // Last resort - emergency shutdown
      _emergencyShutdown();
    }
  }
  
  void _resetHardwareToSafeState() {
    try {
      // Reset GPIO pins to safe state (inputs or low outputs)
      final gpioProvider = _hal.getProvider<GpioProvider>(ResourceType.gpio);
      if (gpioProvider != null) {
        for (int pin in gpioProvider.availablePins.take(10)) { // Only common pins
          try {
            gpioProvider.configurePin(GpioConfig(
              pin: pin,
              mode: GpioMode.input, // Safe state - input mode
            )).catchError((_) {}); // Ignore errors
          } catch (_) {}
        }
      }
      
      // Reset PWM channels to 0% duty cycle
      final pwmProvider = _hal.getProvider<PwmProvider>(ResourceType.pwm);
      if (pwmProvider != null) {
        for (int channel in pwmProvider.availableChannels.take(4)) {
          try {
            pwmProvider.setDutyCycle(channel, 0.0).catchError((_) {});
          } catch (_) {}
        }
      }
      
    } catch (e) {
      _logger.warning('Failed to reset hardware to safe state: $e');
    }
  }
  
  void _clearNonCriticalState() {
    try {
      final criticalStates = <String>{};
      
      // Identify critical state variables
      if (_flowDefinition != null) {
        for (final entry in _flowDefinition!.state.entries) {
          final stateVar = entry.value;
          if (stateVar.security?.critical == true) {
            criticalStates.add(entry.key);
          }
        }
      }
      
      // Clear non-critical state variables
      final allStates = Set<String>.from(_stateManager.getAllStates().keys);
      for (final stateName in allStates) {
        if (!criticalStates.contains(stateName)) {
          try {
            _stateManager.deleteState(stateName);
          } catch (_) {}
        }
      }
      
    } catch (e) {
      _logger.warning('Failed to clear non-critical state: $e');
    }
  }
  
  void _restartCriticalProcesses() {
    if (_flowDefinition == null) return;
    
    try {
      // Find and restart critical processes
      for (final process in _flowDefinition!.processes) {
        final isCritical = process.priority == ProcessPriority.high;
        
        if (isCritical) {
          try {
            // Mark critical process for restart
            _logger.info('Marked critical process for restart: ${process.id}');
          } catch (e) {
            _logger.warning('Failed to mark critical process ${process.id}: $e');
          }
        }
      }
    } catch (e) {
      _logger.warning('Failed to restart critical processes: $e');
    }
  }
  
  void _reduceResourceUsage() {
    try {
      // Reduce tick rate to minimum
      _scheduler.setTickRate(Duration(seconds: 5)); // 5 second intervals
      
      // Close unnecessary channels
      for (final entry in _channels.entries) {
        try {
          final channel = entry.value;
          if (channel is StreamSubscription) {
            channel.cancel();
          } else if (channel is StreamController) {
            channel.close();
          }
        } catch (_) {}
      }
      
      // Force garbage collection
      // Note: Dart doesn't expose direct GC control, but we can help
      _channels.clear();
      
    } catch (e) {
      _logger.warning('Failed to reduce resource usage: $e');
    }
  }
  
  void _emergencyShutdown() {
    _logger.severe('Initiating emergency shutdown');
    try {
      // Stop all processes immediately
      _scheduler.cancelAll();
      
      // Close all resources
      _hal.dispose().catchError((_) {});
      
      // Set status to error
      _status = RuntimeStatus.error;
      
      // Emit emergency event
      _eventBus.fire(RuntimeErrorEvent(
        'Emergency shutdown activated',
        StackTrace.current,
      ));
      
    } catch (e) {
      _logger.severe('Emergency shutdown failed: $e');
    }
  }
  

  Future<void> _initializeHardwareResources() async {
    // Setup resource event callback for mock HAL
    if (_hal is MockHardwareAbstractionLayer) {
      final mockHal = _hal as MockHardwareAbstractionLayer;
      final gpioProvider = mockHal.getProvider<GpioProvider>(ResourceType.gpio);
      if (gpioProvider is MockGpioProvider) {
        gpioProvider.onResourceEvent = (resource, event, {data}) {
          emitResourceEvent(resource, event, data: data);
        };
      }
    }
    
    for (final entry in _resources.entries) {
      final name = entry.key;
      // Skip special resources (starting with __)
      if (name.startsWith('__')) {
        continue;
      }
      
      final resource = entry.value as Map<String, dynamic>;
      final type = resource['type'] as String;
      final config = resource['config'] as Map<String, dynamic>;
      
      // Initialize hardware resources based on type
      if (type == 'gpio') {
        // Initialize GPIO pins
        final gpioProvider = _hal.getProvider<GpioProvider>(ResourceType.gpio);
        if (gpioProvider != null) {
          // Handle single pin configuration
          final singlePin = config['pin'] as int?;
          if (singlePin != null) {
            final mode = config['mode'] as String? ?? 'input';
            final initial = config['initial'] as bool? ?? false;
            
            final gpioConfig = GpioConfig(
              pin: singlePin,
              mode: mode == 'output' ? GpioMode.output : GpioMode.input,
              initialValue: initial,
            );
            await gpioProvider.configurePin(gpioConfig);
            _logger.fine('Configured GPIO pin $singlePin as $mode');
          }
          
          // Handle multiple pins configuration
          final pins = config['pins'] as Map<String, dynamic>?;
          if (pins != null) {
            for (final entry in pins.entries) {
              final pinNumber = int.tryParse(entry.key) ?? 0;
              final pinConfig = entry.value as Map<String, dynamic>;
              final direction = pinConfig['direction'] as String? ?? 'input';
              final initial = pinConfig['initial'] as bool? ?? false;
              
              // Configure the pin
              final gpioConfig = GpioConfig(
                pin: pinNumber,
                mode: direction == 'output' ? GpioMode.output : GpioMode.input,
                initialValue: initial,
              );
              await gpioProvider.configurePin(gpioConfig);
              
              _logger.fine('Configured GPIO pin $pinNumber as $direction');
            }
          }
        } else {
          _logger.warning('GPIO provider not available');
        }
      } else if (type == 'adc') {
        // Initialize ADC channels
        final channel = config['channel'] as int?;
        final resolution = config['resolution'] as int? ?? 12;
        if (channel != null) {
          final adcProvider = _hal.getProvider<AdcProvider>(ResourceType.adc);
          if (adcProvider != null) {
            final adcConfig = AdcConfig(
              channel: channel,
              resolution: resolution,
              referenceVoltage: (config['referenceVoltage'] as num?)?.toDouble() ?? 3.3,
            );
            await adcProvider.configureChannel(adcConfig);
            _logger.fine('Configured ADC channel $channel with resolution $resolution');
          }
        }
      } else if (type == 'pwm') {
        // Initialize PWM channels
        final channel = config['channel'] as int?;
        final frequency = (config['frequency'] as num?)?.toDouble() ?? 1000.0;
        if (channel != null) {
          final pwmProvider = _hal.getProvider<PwmProvider>(ResourceType.pwm);
          if (pwmProvider != null) {
            final pwmConfig = PwmConfig(
              channel: channel,
              frequencyHz: frequency,
              dutyPercent: (config['dutyCycle'] as num?)?.toDouble() ?? 0.0,
            );
            await pwmProvider.configureChannel(pwmConfig);
            _logger.fine('Configured PWM channel $channel with frequency $frequency Hz');
          }
        }
      } else if (type == 'mqtt') {
        // Initialize MQTT connection
        final mqttProvider = _hal.getProvider<MqttProvider>(ResourceType.mqtt);
        if (mqttProvider != null) {
          // Get the configuration from the stored resource info
          final resourceInfo = _resources[name] as Map<String, dynamic>;
          final mqttConfig = MqttConfig.fromJson(resourceInfo['config'] as Map<String, dynamic>);
          final client = await mqttProvider.connect(mqttConfig);
          await client.connect();
          
          // Store both the client and the original configuration
          _resources[name] = {
            'type': 'mqtt',
            'client': client,
            'config': resourceInfo['config'],
          };
          
          _logger.fine('Connected to MQTT broker ${mqttConfig.host}:${mqttConfig.port}');
        } else {
          _logger.warning('MQTT provider not available for resource $name');
        }
      } else if (type == 'i2c' || 
          type == 'spi' ||
          type == 'uart' ||
          type == 'modbus') {
        // Other hardware resources are initialized on-demand by action executors
        _logger.fine('Hardware resource $name will be initialized on first use');
      }
    }
  }

  // Service integration methods

  /// Install runtime as system service
  Future<void> installAsService(ServiceConfig config) async {
    if (_flowDefinition == null) {
      throw Exception('No flow loaded');
    }

    final serviceManager = ServiceManagerFactory.create();
    await serviceManager.install(config);
    
    _logger.info('Installed MCP Flow Runtime as service: ${config.name}');
  }

  /// Uninstall runtime service
  Future<void> uninstallService(String serviceName) async {
    final serviceManager = ServiceManagerFactory.create();
    await serviceManager.uninstall(serviceName);
    
    _logger.info('Uninstalled MCP Flow Runtime service: $serviceName');
  }

  /// Get service status
  Future<ServiceStatus> getServiceStatus(String serviceName) async {
    final serviceManager = ServiceManagerFactory.create();
    return await serviceManager.status(serviceName);
  }
  
  // MCP Integration methods
  
  /// Get current flow definition
  FlowDefinition? getFlowDefinition() => _flowDefinition;
  
  /// Get list of all processes
  List<ProcessInfo> getProcessList() {
    if (_flowDefinition == null) return [];
    
    return _flowDefinition!.processes.map((process) {
      final instance = _scheduler.getProcessInstance(process.id);
      return ProcessInfo(
        id: process.id,
        name: process.name,
        description: process.description,
        enabled: process.enabled,
        status: instance?.state ?? ProcessState.ready,
        triggerType: process.trigger?.type,
        priority: process.priority,
      );
    }).toList();
  }
  
  /// Get all state variables
  Map<String, dynamic> getAllStateVariables() {
    return _stateManager.getAll();
  }
  
  /// Get runtime statistics
  RuntimeStatistics getStatistics() {
    return RuntimeStatistics(
      totalProcessesStarted: _flowDefinition?.processes.length ?? 0,
      totalProcessesCompleted: _scheduler.completedProcesses,
      totalProcessesFailed: _scheduler.errorProcesses,
      activeProcessCount: _scheduler.activeProcesses,
      totalActionsExecuted: 0,
      actionCountByType: {},
    );
  }

  /// Register client capabilities
  void registerClient(String clientId, ClientCapabilities capabilities) {
    _clientCapabilityDetector?.registerClient(clientId, capabilities);
    _logger.info('Registered client: $clientId');
  }
  
  /// Get client capabilities
  ClientCapabilities? getClientCapabilities(String clientId) {
    return _clientCapabilityDetector?.getClientCapabilities(clientId);
  }
  
  /// Check if client supports a capability
  bool clientSupports(String clientId, String capability) {
    return _clientCapabilityDetector?.clientSupports(clientId, capability) ?? false;
  }
  
  /// Update client activity
  void updateClientActivity(String clientId) {
    _clientCapabilityDetector?.updateClientActivity(clientId);
  }
  
  /// Remove client
  void removeClient(String clientId) {
    _clientCapabilityDetector?.removeClient(clientId);
    _logger.info('Removed client: $clientId');
  }
  
  /// Check if a client is registered
  bool isClientRegistered(String clientId) {
    return _clientCapabilityDetector?.isRegistered(clientId) ?? false;
  }
  
  /// Build capability-aware response
  Map<String, dynamic> buildCapabilityAwareResponse({
    required String clientId,
    required String resource,
    required String event,
    required dynamic data,
  }) {
    if (_clientCapabilityDetector == null) {
      // No capability detection - return standard response
      return {
        'resource': resource,
        'event': event,
        'data': data,
      };
    }

    final responseBuilder = CapabilityAwareResponseBuilder(_clientCapabilityDetector!);
    return responseBuilder.buildResponse(
      clientId: clientId,
      data: {
        'resource': resource,
        'event': event,
        'data': data,
      },
      extras: _mcpConfig?.fallback,
    );
  }

  /// Start runtime in service mode
  Future<void> startAsService() async {
    // In service mode, setup signal handlers for graceful shutdown
    ProcessSignal.sigterm.watch().listen((_) async {
      _logger.info('Received SIGTERM, stopping runtime...');
      await stop();
    });

    ProcessSignal.sigint.watch().listen((_) async {
      _logger.info('Received SIGINT, stopping runtime...');
      await stop();
    });

    // Start the runtime
    await start();

    // Keep service running
    _logger.info('MCP Flow Runtime service started');
  }

  /// Create service configuration from flow
  ServiceConfig createServiceConfig({
    String? name,
    String? displayName,
    String? description,
    required String executablePath,
    List<String>? arguments,
    Map<String, String>? environment,
    String? workingDirectory,
    String? user,
    String? group,
  }) {
    final flowName = _flowDefinition?.metadata?.name ?? 'mcp-flow';
    final flowVersion = _flowDefinition?.version ?? '1.0.0';
    
    return ServiceConfig(
      name: name ?? 'mcp-flow-$flowName',
      displayName: displayName ?? 'MCP Flow Runtime - $flowName',
      description: description ?? 'MCP Flow Runtime service for $flowName v$flowVersion',
      executablePath: executablePath,
      arguments: arguments ?? [],
      environment: environment ?? {},
      workingDirectory: workingDirectory,
      user: user,
      group: group,
      autoRestart: true,
      restartDelay: Duration(seconds: 5),
      maxRestarts: 3,
    );
  }
}