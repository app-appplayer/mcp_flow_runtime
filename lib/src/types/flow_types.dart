/// Flow DSL type definitions

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'flow_types.g.dart';

/// Flow definition root
@JsonSerializable(explicitToJson: true)
class FlowDefinition extends Equatable {
  @JsonKey(name: r'$schema')
  final String? schema;
  final String version;
  final FlowMetadata metadata; // TD-004: required
  final FlowConfiguration? configuration; // TD-005: typed FlowConfiguration
  final Map<String, ResourceDefinition> resources;
  final Map<String, StateDefinition> state;
  final Map<String, ChannelDefinition> channels; // TD-006: required with default
  final SynchronizationDefinition? synchronization;
  final List<ProcessDefinition> processes;
  final List<EventDefinition>? events;
  @JsonKey(name: 'uiDefinitions')
  final Map<String, dynamic>? uiDefinitions;

  const FlowDefinition({
    this.schema,
    required this.version,
    required this.metadata,
    this.configuration,
    this.resources = const {},
    this.state = const {},
    this.channels = const {},
    this.synchronization,
    required this.processes,
    this.events,
    this.uiDefinitions,
  });

  factory FlowDefinition.fromJson(Map<String, dynamic> json) =>
      _$FlowDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$FlowDefinitionToJson(this);

  @override
  List<Object?> get props => [
        schema,
        version,
        metadata,
        configuration,
        resources,
        state,
        channels,
        synchronization,
        processes,
        events,
        uiDefinitions,
      ];
}

/// Flow configuration per DDD (TD-005)
@JsonSerializable(explicitToJson: true)
class FlowConfiguration extends Equatable {
  final Map<String, dynamic>? hal;
  final RuntimeLimitsConfig? runtime;
  final McpConfig? mcp;
  final Map<String, dynamic>? system;

  const FlowConfiguration({
    this.hal,
    this.runtime,
    this.mcp,
    this.system,
  });

  factory FlowConfiguration.fromJson(Map<String, dynamic> json) =>
      _$FlowConfigurationFromJson(json);

  Map<String, dynamic> toJson() => _$FlowConfigurationToJson(this);

  @override
  List<Object?> get props => [hal, runtime, mcp, system];
}

/// Runtime limits configuration per DDD
@JsonSerializable()
class RuntimeLimitsConfig extends Equatable {
  final int? tickRateMs;
  final int? maxProcesses;
  final int? maxMemoryKB;

  const RuntimeLimitsConfig({
    this.tickRateMs,
    this.maxProcesses,
    this.maxMemoryKB,
  });

  factory RuntimeLimitsConfig.fromJson(Map<String, dynamic> json) =>
      _$RuntimeLimitsConfigFromJson(json);

  Map<String, dynamic> toJson() => _$RuntimeLimitsConfigToJson(this);

  @override
  List<Object?> get props => [tickRateMs, maxProcesses, maxMemoryKB];
}

/// Flow metadata (TD-003: tags removed)
@JsonSerializable(explicitToJson: true)
class FlowMetadata extends Equatable {
  final String name;
  final String? description;
  final String? author;
  final DateTime? created;
  final DateTime? modified;

  const FlowMetadata({
    required this.name,
    this.description,
    this.author,
    this.created,
    this.modified,
  });

  factory FlowMetadata.fromJson(Map<String, dynamic> json) =>
      _$FlowMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$FlowMetadataToJson(this);

  @override
  List<Object?> get props =>
      [name, description, author, created, modified];
}

/// Resource definition
@JsonSerializable(explicitToJson: true)
class ResourceDefinition extends Equatable {
  final String type;
  final Map<String, dynamic> config;
  final List<String>? capabilities;
  final McpResourceBinding? mcp;
  final SecurityConfig? security;
  final SafetyConfig? safety;
  final ErrorHandlingConfig? errorHandling;

  const ResourceDefinition({
    required this.type,
    required this.config,
    this.capabilities,
    this.mcp,
    this.security,
    this.safety,
    this.errorHandling,
  });

  factory ResourceDefinition.fromJson(Map<String, dynamic> json) =>
      _$ResourceDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$ResourceDefinitionToJson(this);

  @override
  List<Object?> get props =>
      [type, config, capabilities, mcp, security, safety, errorHandling];
}

/// State variable types
enum StateType {
  @JsonValue('boolean')
  boolean,
  @JsonValue('number')
  number,
  @JsonValue('string')
  string,
  @JsonValue('object')
  object,
  @JsonValue('array')
  array,
  @JsonValue('any')
  any,
}

/// State definition
@JsonSerializable(explicitToJson: true)
class StateDefinition extends Equatable {
  final StateType type;
  final dynamic initial;
  final bool persistent;
  final StateConstraints? constraints;
  final StateSecurityConfig? security;

  const StateDefinition({
    required this.type,
    this.initial,
    this.persistent = false,
    this.constraints,
    this.security,
  });

  factory StateDefinition.fromJson(Map<String, dynamic> json) =>
      _$StateDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$StateDefinitionToJson(this);

  @override
  List<Object?> get props =>
      [type, initial, persistent, constraints, security];
}

/// State constraints
@JsonSerializable()
class StateConstraints extends Equatable {
  final num? min;
  final num? max;
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  @JsonKey(name: 'enum')
  final List<dynamic>? enum$;
  final int? minItems;
  final int? maxItems;
  final String? validate; // Custom validation expression

  const StateConstraints({
    this.min,
    this.max,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.enum$,
    this.minItems,
    this.maxItems,
    this.validate,
  });

  factory StateConstraints.fromJson(Map<String, dynamic> json) =>
      _$StateConstraintsFromJson(json);

  Map<String, dynamic> toJson() => _$StateConstraintsToJson(this);

  @override
  List<Object?> get props =>
      [min, max, minLength, maxLength, pattern, enum$, minItems, maxItems, validate];
}

/// Process priorities
enum ProcessPriority {
  @JsonValue('low')
  low,
  @JsonValue('normal')
  normal,
  @JsonValue('high')
  high,
  @JsonValue('realtime')
  realtime,
}

/// Process definition (TD-009, TD-010, TD-012: aligned with Spec)
@JsonSerializable(explicitToJson: true)
class ProcessDefinition extends Equatable {
  final String id;
  final String name; // TD-009: required
  final String? description;
  final bool enabled;
  final TriggerDefinition? trigger; // TD-010: singular only
  final bool loop;
  final ProcessPriority priority;
  final List<ActionDefinition> steps;
  final List<ActionDefinition>? error;
  @JsonKey(name: 'finally')
  final List<ActionDefinition>? finally$;

  const ProcessDefinition({
    required this.id,
    required this.name,
    this.description,
    this.enabled = true,
    this.trigger,
    this.loop = false,
    this.priority = ProcessPriority.normal,
    required this.steps,
    this.error,
    this.finally$,
  });

  factory ProcessDefinition.fromJson(Map<String, dynamic> json) =>
      _$ProcessDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$ProcessDefinitionToJson(this);

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        enabled,
        trigger,
        loop,
        priority,
        steps,
        error,
        finally$,
      ];
}

/// Trigger types
enum TriggerType {
  @JsonValue('manual')
  manual,
  @JsonValue('startup')
  startup,
  @JsonValue('event')
  event,
  @JsonValue('condition')
  condition,
  @JsonValue('schedule')
  schedule,
  @JsonValue('channelReceive')
  channelReceive,
  @JsonValue('stateChange')
  stateChange,
  @JsonValue('resourceEvent')
  resourceEvent,
}

/// Trigger definition (TD-014: filter removed)
@JsonSerializable(explicitToJson: true)
class TriggerDefinition extends Equatable {
  final TriggerType type;
  final String? event;
  final String? condition;
  final int? interval;
  final String? cron;
  final int? delay;       // Initial delay for schedule triggers
  final String? variable;  // For stateChange triggers
  final String? channel;   // For channelReceive triggers
  final String? resource;  // For resourceEvent triggers
  final int? debounceMs;  // Debounce delay in milliseconds

  const TriggerDefinition({
    required this.type,
    this.event,
    this.condition,
    this.interval,
    this.cron,
    this.delay,
    this.variable,
    this.channel,
    this.resource,
    this.debounceMs,
  });

  factory TriggerDefinition.fromJson(Map<String, dynamic> json) {
    // Handle backward compatibility for 'key' field used in stateChange triggers
    if (json['type'] == 'stateChange' && json['key'] != null && json['variable'] == null) {
      json = Map<String, dynamic>.from(json);
      json['variable'] = json['key'];
    }
    return _$TriggerDefinitionFromJson(json);
  }

  Map<String, dynamic> toJson() => _$TriggerDefinitionToJson(this);

  @override
  List<Object?> get props => [type, event, condition, interval, cron, delay, variable, channel, resource, debounceMs];
}

/// Action definition (TD-015: errorHandling removed)
@JsonSerializable(explicitToJson: true)
class ActionDefinition extends Equatable {
  final String action;
  final Map<String, dynamic>? params;
  final String? bindTo;
  final String? condition;
  final int? timeout;
  final RetryConfig? retry;

  // Control flow specific fields
  final List<ActionDefinition>? then; // for if
  @JsonKey(name: 'else')
  final List<ActionDefinition>? else$; // for if
  @JsonKey(name: 'do')
  final List<ActionDefinition>? do$; // for while/for
  @JsonKey(name: 'try')
  final List<ActionDefinition>? try$; // for try
  @JsonKey(name: 'catch')
  final List<ActionDefinition>? catch$; // for try
  @JsonKey(name: 'finally')
  final List<ActionDefinition>? finally$; // for try
  final Map<String, List<ActionDefinition>>? cases; // for switch
  final dynamic value; // for switch
  final List<BranchDefinition>? branches; // TD-016: renamed from ParallelBranch
  final String? join; // for parallel

  const ActionDefinition({
    required this.action,
    this.params,
    this.bindTo,
    this.condition,
    this.timeout,
    this.retry,
    this.then,
    this.else$,
    this.do$,
    this.try$,
    this.catch$,
    this.finally$,
    this.cases,
    this.value,
    this.branches,
    this.join,
  });

  factory ActionDefinition.fromJson(Map<String, dynamic> json) {
    // Handle branches in simple array format
    if (json['branches'] != null && json['branches'] is List) {
      final branches = json['branches'] as List;
      if (branches.isNotEmpty && branches.first is List) {
        // Convert simple array format to BranchDefinition format
        json = Map<String, dynamic>.from(json);
        json['branches'] = branches.asMap().entries.map((entry) {
          return {
            'id': 'branch_${entry.key}',
            'steps': entry.value,
          };
        }).toList();
      }
    }
    return _$ActionDefinitionFromJson(json);
  }

  Map<String, dynamic> toJson() => _$ActionDefinitionToJson(this);

  @override
  List<Object?> get props => [
        action,
        params,
        bindTo,
        condition,
        timeout,
        retry,
        then,
        else$,
        do$,
        try$,
        catch$,
        finally$,
        cases,
        value,
        branches,
        join,
      ];
}

/// Branch definition for parallel execution (TD-016: renamed from ParallelBranch)
@JsonSerializable()
class BranchDefinition extends Equatable {
  final String id;
  final List<ActionDefinition> steps;

  const BranchDefinition({
    required this.id,
    required this.steps,
  });

  factory BranchDefinition.fromJson(Map<String, dynamic> json) =>
      _$BranchDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$BranchDefinitionToJson(this);

  @override
  List<Object?> get props => [id, steps];
}

/// Retry configuration
@JsonSerializable()
class RetryConfig extends Equatable {
  final int count;
  final int delayMs;
  final String? backoff;
  final int? maxDelayMs;
  final List<String>? retryConditions;
  final List<String>? stopConditions;

  const RetryConfig({
    required this.count,
    required this.delayMs,
    this.backoff,
    this.maxDelayMs,
    this.retryConditions,
    this.stopConditions,
  });

  factory RetryConfig.fromJson(Map<String, dynamic> json) =>
      _$RetryConfigFromJson(json);

  Map<String, dynamic> toJson() => _$RetryConfigToJson(this);

  @override
  List<Object?> get props =>
      [count, delayMs, backoff, maxDelayMs, retryConditions, stopConditions];
}

/// Channel types
enum ChannelType {
  @JsonValue('queue')
  queue,
  @JsonValue('pubsub')
  pubsub,
  @JsonValue('sharedMemory')
  sharedMemory,
  @JsonValue('pipe')
  pipe,
}

/// Channel definition (TD-019: persistent is nullable)
@JsonSerializable()
class ChannelDefinition extends Equatable {
  final ChannelType type;
  final int? capacity;
  final String? overflow;
  final bool? persistent; // TD-019: nullable per Spec
  final int? size;
  final bool? mutex;

  const ChannelDefinition({
    required this.type,
    this.capacity,
    this.overflow,
    this.persistent,
    this.size,
    this.mutex,
  });

  factory ChannelDefinition.fromJson(Map<String, dynamic> json) =>
      _$ChannelDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$ChannelDefinitionToJson(this);

  @override
  List<Object?> get props =>
      [type, capacity, overflow, persistent, size, mutex];
}

/// MCP resource binding
@JsonSerializable()
class McpResourceBinding extends Equatable {
  final bool expose;
  final McpResourceInfo? resource;

  const McpResourceBinding({
    this.expose = false,
    this.resource,
  });

  factory McpResourceBinding.fromJson(Map<String, dynamic> json) =>
      _$McpResourceBindingFromJson(json);

  Map<String, dynamic> toJson() => _$McpResourceBindingToJson(this);

  @override
  List<Object?> get props => [expose, resource];
}

/// MCP resource info
@JsonSerializable()
class McpResourceInfo extends Equatable {
  final String uri;
  final String name;
  final String? mimeType;
  final int? updateIntervalMs;

  const McpResourceInfo({
    required this.uri,
    required this.name,
    this.mimeType,
    this.updateIntervalMs,
  });

  factory McpResourceInfo.fromJson(Map<String, dynamic> json) =>
      _$McpResourceInfoFromJson(json);

  Map<String, dynamic> toJson() => _$McpResourceInfoToJson(this);

  @override
  List<Object?> get props => [uri, name, mimeType, updateIntervalMs];
}

/// MCP tool info
@JsonSerializable()
class McpToolInfo extends Equatable {
  final String name;
  final String description;
  final Map<String, dynamic>? inputSchema;

  const McpToolInfo({
    required this.name,
    required this.description,
    this.inputSchema,
  });

  factory McpToolInfo.fromJson(Map<String, dynamic> json) =>
      _$McpToolInfoFromJson(json);

  Map<String, dynamic> toJson() => _$McpToolInfoToJson(this);

  @override
  List<Object?> get props => [name, description, inputSchema];
}

/// Synchronization definition (TD-020: implemented with full fields)
@JsonSerializable(explicitToJson: true)
class SynchronizationDefinition extends Equatable {
  final Map<String, MutexDefinition>? mutexes;
  final Map<String, SemaphoreDefinition>? semaphores;
  final Map<String, BarrierDefinition>? barriers;
  final Map<String, EventSyncDefinition>? events;

  const SynchronizationDefinition({
    this.mutexes,
    this.semaphores,
    this.barriers,
    this.events,
  });

  factory SynchronizationDefinition.fromJson(Map<String, dynamic> json) =>
      _$SynchronizationDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$SynchronizationDefinitionToJson(this);

  @override
  List<Object?> get props => [mutexes, semaphores, barriers, events];
}

/// Mutex definition for synchronization
@JsonSerializable()
class MutexDefinition extends Equatable {
  final int? timeoutMs;
  final bool? priorityInheritance;

  const MutexDefinition({
    this.timeoutMs,
    this.priorityInheritance,
  });

  factory MutexDefinition.fromJson(Map<String, dynamic> json) =>
      _$MutexDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$MutexDefinitionToJson(this);

  @override
  List<Object?> get props => [timeoutMs, priorityInheritance];
}

/// Semaphore definition for synchronization
@JsonSerializable()
class SemaphoreDefinition extends Equatable {
  final int initial;
  final int? max;

  const SemaphoreDefinition({
    required this.initial,
    this.max,
  });

  factory SemaphoreDefinition.fromJson(Map<String, dynamic> json) =>
      _$SemaphoreDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$SemaphoreDefinitionToJson(this);

  @override
  List<Object?> get props => [initial, max];
}

/// Barrier definition for synchronization
@JsonSerializable()
class BarrierDefinition extends Equatable {
  final int count;
  final bool? autoReset;

  const BarrierDefinition({
    required this.count,
    this.autoReset,
  });

  factory BarrierDefinition.fromJson(Map<String, dynamic> json) =>
      _$BarrierDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$BarrierDefinitionToJson(this);

  @override
  List<Object?> get props => [count, autoReset];
}

/// Event synchronization definition
@JsonSerializable()
class EventSyncDefinition extends Equatable {
  final bool? autoReset;
  final bool? initialState;

  const EventSyncDefinition({
    this.autoReset,
    this.initialState,
  });

  factory EventSyncDefinition.fromJson(Map<String, dynamic> json) =>
      _$EventSyncDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$EventSyncDefinitionToJson(this);

  @override
  List<Object?> get props => [autoReset, initialState];
}

/// Event definition (TD-021: completed with missing fields)
@JsonSerializable(explicitToJson: true)
class EventDefinition extends Equatable {
  final String id;
  final String type;
  final String source;
  final String? condition;
  final int? debounceMs;
  final List<ActionDefinition> actions;

  const EventDefinition({
    required this.id,
    required this.type,
    required this.source,
    this.condition,
    this.debounceMs,
    this.actions = const [],
  });

  factory EventDefinition.fromJson(Map<String, dynamic> json) =>
      _$EventDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$EventDefinitionToJson(this);

  @override
  List<Object?> get props => [id, type, source, condition, debounceMs, actions];
}

@JsonSerializable()
class SecurityConfig extends Equatable {
  final bool? requireAuth;
  final List<String>? allowedRoles;
  final bool? auditLog;
  final bool? confirmationRequired;
  final Map<String, dynamic>? rateLimit;

  const SecurityConfig({
    this.requireAuth,
    this.allowedRoles,
    this.auditLog,
    this.confirmationRequired,
    this.rateLimit,
  });

  factory SecurityConfig.fromJson(Map<String, dynamic> json) =>
      _$SecurityConfigFromJson(json);

  Map<String, dynamic> toJson() => _$SecurityConfigToJson(this);

  @override
  List<Object?> get props => [
    requireAuth,
    allowedRoles,
    auditLog,
    confirmationRequired,
    rateLimit,
  ];
}

@JsonSerializable()
class SafetyConfig extends Equatable {
  final double? maxDutyCycle;
  final double? maxTemperature;
  final double? currentLimit;
  final String? protectionAction;
  final int? cooldownPeriod;

  const SafetyConfig({
    this.maxDutyCycle,
    this.maxTemperature,
    this.currentLimit,
    this.protectionAction,
    this.cooldownPeriod,
  });

  factory SafetyConfig.fromJson(Map<String, dynamic> json) =>
      _$SafetyConfigFromJson(json);

  Map<String, dynamic> toJson() => _$SafetyConfigToJson(this);

  @override
  List<Object?> get props => [
    maxDutyCycle,
    maxTemperature,
    currentLimit,
    protectionAction,
    cooldownPeriod,
  ];
}

@JsonSerializable()
class ErrorHandlingConfig extends Equatable {
  const ErrorHandlingConfig();

  factory ErrorHandlingConfig.fromJson(Map<String, dynamic> json) =>
      _$ErrorHandlingConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ErrorHandlingConfigToJson(this);

  @override
  List<Object?> get props => [];
}

@JsonSerializable()
class StateSecurityConfig extends Equatable {
  final bool? encrypted;
  final String? algorithm;
  final bool? masked;
  final List<String>? readRoles;
  final List<String>? writeRoles;
  final bool? auditLog;
  final bool? critical;

  const StateSecurityConfig({
    this.encrypted,
    this.algorithm,
    this.masked,
    this.readRoles,
    this.writeRoles,
    this.auditLog,
    this.critical,
  });

  factory StateSecurityConfig.fromJson(Map<String, dynamic> json) =>
      _$StateSecurityConfigFromJson(json);

  Map<String, dynamic> toJson() => _$StateSecurityConfigToJson(this);

  @override
  List<Object?> get props => [
    encrypted,
    algorithm,
    masked,
    readRoles,
    writeRoles,
    auditLog,
    critical,
  ];
}

/// MCP Tool Definition
@JsonSerializable()
class McpTool extends Equatable {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Future<dynamic> Function(Map<String, dynamic>)? handler;

  const McpTool({
    required this.name,
    this.description,
    this.inputSchema,
    this.handler,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) =>
      _$McpToolFromJson(json);

  Map<String, dynamic> toJson() => _$McpToolToJson(this);

  @override
  List<Object?> get props => [name, description, inputSchema];
}

/// MCP Resource Definition
@JsonSerializable()
class McpResource extends Equatable {
  final String name;
  final String uri;
  final String? description;
  final String? mimeType;
  final dynamic content;

  const McpResource({
    required this.name,
    required this.uri,
    this.description,
    this.mimeType,
    this.content,
  });

  factory McpResource.fromJson(Map<String, dynamic> json) =>
      _$McpResourceFromJson(json);

  Map<String, dynamic> toJson() => _$McpResourceToJson(this);

  @override
  List<Object?> get props => [name, uri, description, mimeType, content];
}

/// MCP Configuration
@JsonSerializable()
class McpConfig extends Equatable {
  final McpMode mode;
  final bool? extendedData;
  final Map<String, dynamic>? fallback;
  final List<McpTool>? tools;
  final List<McpResource>? resources;

  const McpConfig({
    this.mode = McpMode.standard,
    this.extendedData,
    this.fallback,
    this.tools,
    this.resources,
  });

  factory McpConfig.fromJson(Map<String, dynamic> json) =>
      _$McpConfigFromJson(json);

  Map<String, dynamic> toJson() => _$McpConfigToJson(this);

  @override
  List<Object?> get props => [mode, extendedData, fallback, tools, resources];
}

/// MCP Mode enum
enum McpMode {
  @JsonValue('standard')
  standard,
  @JsonValue('extended')
  extended,
}
