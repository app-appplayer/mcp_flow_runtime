/// Flow DSL type definitions

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'flow_types.g.dart';

/// Flow definition root
@JsonSerializable()
class FlowDefinition extends Equatable {
  @JsonKey(name: r'$schema')
  final String? schema;
  final String version;
  final FlowMetadata? metadata;
  final Map<String, dynamic>? configuration;
  final Map<String, ResourceDefinition> resources;
  final Map<String, StateDefinition> state;
  final Map<String, ChannelDefinition>? channels;
  final SynchronizationDefinition? synchronization;
  final List<ProcessDefinition> processes;
  final List<EventDefinition>? events;
  @JsonKey(name: 'ui_definitions')
  final Map<String, dynamic>? uiDefinitions;

  const FlowDefinition({
    this.schema,
    required this.version,
    this.metadata,
    this.configuration,
    this.resources = const {},
    this.state = const {},
    this.channels,
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

/// Flow metadata
@JsonSerializable()
class FlowMetadata extends Equatable {
  final String name;
  final String? description;
  final String? author;
  final DateTime? created;
  final DateTime? modified;
  final List<String>? tags;

  const FlowMetadata({
    required this.name,
    this.description,
    this.author,
    this.created,
    this.modified,
    this.tags,
  });

  factory FlowMetadata.fromJson(Map<String, dynamic> json) =>
      _$FlowMetadataFromJson(json);

  Map<String, dynamic> toJson() => _$FlowMetadataToJson(this);

  @override
  List<Object?> get props =>
      [name, description, author, created, modified, tags];
}

/// Resource definition
@JsonSerializable()
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
}

/// State definition
@JsonSerializable()
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
  final List<dynamic>? enum$;

  const StateConstraints({
    this.min,
    this.max,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.enum$,
  });

  factory StateConstraints.fromJson(Map<String, dynamic> json) =>
      _$StateConstraintsFromJson(json);

  Map<String, dynamic> toJson() => _$StateConstraintsToJson(this);

  @override
  List<Object?> get props =>
      [min, max, minLength, maxLength, pattern, enum$];
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

/// Process definition
@JsonSerializable()
class ProcessDefinition extends Equatable {
  final String id;
  final String? name;
  final String? description;
  final bool enabled;
  final TriggerDefinition? trigger;
  final bool loop;
  final ProcessPriority priority;
  final List<ActionDefinition> steps;
  final List<ActionDefinition>? error;
  final List<ActionDefinition>? finally$;
  final McpProcessBinding? mcp;
  final ProcessSecurityConfig? security;

  const ProcessDefinition({
    required this.id,
    this.name,
    this.description,
    this.enabled = true,
    this.trigger,
    this.loop = false,
    this.priority = ProcessPriority.normal,
    required this.steps,
    this.error,
    this.finally$,
    this.mcp,
    this.security,
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
        mcp,
        security,
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
}

/// Trigger definition
@JsonSerializable()
class TriggerDefinition extends Equatable {
  final TriggerType type;
  final String? event;
  final String? condition;
  final int? interval;
  final String? cron;

  const TriggerDefinition({
    required this.type,
    this.event,
    this.condition,
    this.interval,
    this.cron,
  });

  factory TriggerDefinition.fromJson(Map<String, dynamic> json) =>
      _$TriggerDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$TriggerDefinitionToJson(this);

  @override
  List<Object?> get props => [type, event, condition, interval, cron];
}

/// Action definition
@JsonSerializable()
class ActionDefinition extends Equatable {
  final String action;
  final Map<String, dynamic>? params;
  final String? bindTo;
  final String? condition;
  final int? timeout;
  final RetryConfig? retry;
  final ErrorHandlingConfig? errorHandling;

  // Control flow specific fields
  final List<ActionDefinition>? then; // for if
  final List<ActionDefinition>? else$; // for if
  @JsonKey(name: 'do')
  final List<ActionDefinition>? do$; // for while/for
  final Map<String, List<ActionDefinition>>? cases; // for switch
  final dynamic value; // for switch
  final List<ParallelBranch>? branches; // for parallel
  final String? join; // for parallel

  const ActionDefinition({
    required this.action,
    this.params,
    this.bindTo,
    this.condition,
    this.timeout,
    this.retry,
    this.errorHandling,
    this.then,
    this.else$,
    this.do$,
    this.cases,
    this.value,
    this.branches,
    this.join,
  });

  factory ActionDefinition.fromJson(Map<String, dynamic> json) =>
      _$ActionDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$ActionDefinitionToJson(this);

  @override
  List<Object?> get props => [
        action,
        params,
        bindTo,
        condition,
        timeout,
        retry,
        errorHandling,
        then,
        else$,
        do$,
        cases,
        value,
        branches,
        join,
      ];
}

/// Parallel branch
@JsonSerializable()
class ParallelBranch extends Equatable {
  final String id;
  final List<ActionDefinition> steps;

  const ParallelBranch({
    required this.id,
    required this.steps,
  });

  factory ParallelBranch.fromJson(Map<String, dynamic> json) =>
      _$ParallelBranchFromJson(json);

  Map<String, dynamic> toJson() => _$ParallelBranchToJson(this);

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
  @JsonValue('shared_memory')
  sharedMemory,
  @JsonValue('pipe')
  pipe,
}

/// Channel definition
@JsonSerializable()
class ChannelDefinition extends Equatable {
  final ChannelType type;
  final int? capacity;
  final String? overflow;
  final bool persistent;
  final int? size;
  final bool? mutex;

  const ChannelDefinition({
    required this.type,
    this.capacity,
    this.overflow,
    this.persistent = false,
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

/// MCP process binding
@JsonSerializable()
class McpProcessBinding extends Equatable {
  final bool expose;
  final McpToolInfo? tool;

  const McpProcessBinding({
    this.expose = false,
    this.tool,
  });

  factory McpProcessBinding.fromJson(Map<String, dynamic> json) =>
      _$McpProcessBindingFromJson(json);

  Map<String, dynamic> toJson() => _$McpProcessBindingToJson(this);

  @override
  List<Object?> get props => [expose, tool];
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

// Placeholder classes - to be implemented
@JsonSerializable()
class SynchronizationDefinition extends Equatable {
  const SynchronizationDefinition();

  factory SynchronizationDefinition.fromJson(Map<String, dynamic> json) =>
      _$SynchronizationDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$SynchronizationDefinitionToJson(this);

  @override
  List<Object?> get props => [];
}

@JsonSerializable()
class EventDefinition extends Equatable {
  final String id;
  final String type;
  final String source;

  const EventDefinition({
    required this.id,
    required this.type,
    required this.source,
  });

  factory EventDefinition.fromJson(Map<String, dynamic> json) =>
      _$EventDefinitionFromJson(json);

  Map<String, dynamic> toJson() => _$EventDefinitionToJson(this);

  @override
  List<Object?> get props => [id, type, source];
}

@JsonSerializable()
class SecurityConfig extends Equatable {
  const SecurityConfig();

  factory SecurityConfig.fromJson(Map<String, dynamic> json) =>
      _$SecurityConfigFromJson(json);

  Map<String, dynamic> toJson() => _$SecurityConfigToJson(this);

  @override
  List<Object?> get props => [];
}

@JsonSerializable()
class SafetyConfig extends Equatable {
  const SafetyConfig();

  factory SafetyConfig.fromJson(Map<String, dynamic> json) =>
      _$SafetyConfigFromJson(json);

  Map<String, dynamic> toJson() => _$SafetyConfigToJson(this);

  @override
  List<Object?> get props => [];
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
  const StateSecurityConfig();

  factory StateSecurityConfig.fromJson(Map<String, dynamic> json) =>
      _$StateSecurityConfigFromJson(json);

  Map<String, dynamic> toJson() => _$StateSecurityConfigToJson(this);

  @override
  List<Object?> get props => [];
}

@JsonSerializable()
class ProcessSecurityConfig extends Equatable {
  const ProcessSecurityConfig();

  factory ProcessSecurityConfig.fromJson(Map<String, dynamic> json) =>
      _$ProcessSecurityConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ProcessSecurityConfigToJson(this);

  @override
  List<Object?> get props => [];
}