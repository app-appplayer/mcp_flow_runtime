// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flow_types.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FlowDefinition _$FlowDefinitionFromJson(Map<String, dynamic> json) =>
    FlowDefinition(
      schema: json[r'$schema'] as String?,
      version: json['version'] as String,
      metadata: json['metadata'] == null
          ? null
          : FlowMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      configuration: json['configuration'] as Map<String, dynamic>?,
      resources: (json['resources'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(
                k, ResourceDefinition.fromJson(e as Map<String, dynamic>)),
          ) ??
          const {},
      state: (json['state'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(
                k, StateDefinition.fromJson(e as Map<String, dynamic>)),
          ) ??
          const {},
      channels: (json['channels'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, ChannelDefinition.fromJson(e as Map<String, dynamic>)),
      ),
      synchronization: json['synchronization'] == null
          ? null
          : SynchronizationDefinition.fromJson(
              json['synchronization'] as Map<String, dynamic>),
      processes: (json['processes'] as List<dynamic>)
          .map((e) => ProcessDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      events: (json['events'] as List<dynamic>?)
          ?.map((e) => EventDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      uiDefinitions: json['ui_definitions'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$FlowDefinitionToJson(FlowDefinition instance) =>
    <String, dynamic>{
      r'$schema': instance.schema,
      'version': instance.version,
      'metadata': instance.metadata,
      'configuration': instance.configuration,
      'resources': instance.resources,
      'state': instance.state,
      'channels': instance.channels,
      'synchronization': instance.synchronization,
      'processes': instance.processes,
      'events': instance.events,
      'ui_definitions': instance.uiDefinitions,
    };

FlowMetadata _$FlowMetadataFromJson(Map<String, dynamic> json) => FlowMetadata(
      name: json['name'] as String,
      description: json['description'] as String?,
      author: json['author'] as String?,
      created: json['created'] == null
          ? null
          : DateTime.parse(json['created'] as String),
      modified: json['modified'] == null
          ? null
          : DateTime.parse(json['modified'] as String),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$FlowMetadataToJson(FlowMetadata instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'author': instance.author,
      'created': instance.created?.toIso8601String(),
      'modified': instance.modified?.toIso8601String(),
      'tags': instance.tags,
    };

ResourceDefinition _$ResourceDefinitionFromJson(Map<String, dynamic> json) =>
    ResourceDefinition(
      type: json['type'] as String,
      config: json['config'] as Map<String, dynamic>,
      capabilities: (json['capabilities'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      mcp: json['mcp'] == null
          ? null
          : McpResourceBinding.fromJson(json['mcp'] as Map<String, dynamic>),
      security: json['security'] == null
          ? null
          : SecurityConfig.fromJson(json['security'] as Map<String, dynamic>),
      safety: json['safety'] == null
          ? null
          : SafetyConfig.fromJson(json['safety'] as Map<String, dynamic>),
      errorHandling: json['errorHandling'] == null
          ? null
          : ErrorHandlingConfig.fromJson(
              json['errorHandling'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ResourceDefinitionToJson(ResourceDefinition instance) =>
    <String, dynamic>{
      'type': instance.type,
      'config': instance.config,
      'capabilities': instance.capabilities,
      'mcp': instance.mcp,
      'security': instance.security,
      'safety': instance.safety,
      'errorHandling': instance.errorHandling,
    };

StateDefinition _$StateDefinitionFromJson(Map<String, dynamic> json) =>
    StateDefinition(
      type: $enumDecode(_$StateTypeEnumMap, json['type']),
      initial: json['initial'],
      persistent: json['persistent'] as bool? ?? false,
      constraints: json['constraints'] == null
          ? null
          : StateConstraints.fromJson(
              json['constraints'] as Map<String, dynamic>),
      security: json['security'] == null
          ? null
          : StateSecurityConfig.fromJson(
              json['security'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$StateDefinitionToJson(StateDefinition instance) =>
    <String, dynamic>{
      'type': _$StateTypeEnumMap[instance.type]!,
      'initial': instance.initial,
      'persistent': instance.persistent,
      'constraints': instance.constraints,
      'security': instance.security,
    };

const _$StateTypeEnumMap = {
  StateType.boolean: 'boolean',
  StateType.number: 'number',
  StateType.string: 'string',
  StateType.object: 'object',
  StateType.array: 'array',
};

StateConstraints _$StateConstraintsFromJson(Map<String, dynamic> json) =>
    StateConstraints(
      min: json['min'] as num?,
      max: json['max'] as num?,
      minLength: (json['minLength'] as num?)?.toInt(),
      maxLength: (json['maxLength'] as num?)?.toInt(),
      pattern: json['pattern'] as String?,
      enum$: json[r'enum$'] as List<dynamic>?,
    );

Map<String, dynamic> _$StateConstraintsToJson(StateConstraints instance) =>
    <String, dynamic>{
      'min': instance.min,
      'max': instance.max,
      'minLength': instance.minLength,
      'maxLength': instance.maxLength,
      'pattern': instance.pattern,
      r'enum$': instance.enum$,
    };

ProcessDefinition _$ProcessDefinitionFromJson(Map<String, dynamic> json) =>
    ProcessDefinition(
      id: json['id'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      trigger: json['trigger'] == null
          ? null
          : TriggerDefinition.fromJson(json['trigger'] as Map<String, dynamic>),
      loop: json['loop'] as bool? ?? false,
      priority:
          $enumDecodeNullable(_$ProcessPriorityEnumMap, json['priority']) ??
              ProcessPriority.normal,
      steps: (json['steps'] as List<dynamic>)
          .map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      error: (json['error'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      finally$: (json[r'finally$'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      mcp: json['mcp'] == null
          ? null
          : McpProcessBinding.fromJson(json['mcp'] as Map<String, dynamic>),
      security: json['security'] == null
          ? null
          : ProcessSecurityConfig.fromJson(
              json['security'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ProcessDefinitionToJson(ProcessDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'enabled': instance.enabled,
      'trigger': instance.trigger,
      'loop': instance.loop,
      'priority': _$ProcessPriorityEnumMap[instance.priority]!,
      'steps': instance.steps,
      'error': instance.error,
      r'finally$': instance.finally$,
      'mcp': instance.mcp,
      'security': instance.security,
    };

const _$ProcessPriorityEnumMap = {
  ProcessPriority.low: 'low',
  ProcessPriority.normal: 'normal',
  ProcessPriority.high: 'high',
  ProcessPriority.realtime: 'realtime',
};

TriggerDefinition _$TriggerDefinitionFromJson(Map<String, dynamic> json) =>
    TriggerDefinition(
      type: $enumDecode(_$TriggerTypeEnumMap, json['type']),
      event: json['event'] as String?,
      condition: json['condition'] as String?,
      interval: (json['interval'] as num?)?.toInt(),
      cron: json['cron'] as String?,
    );

Map<String, dynamic> _$TriggerDefinitionToJson(TriggerDefinition instance) =>
    <String, dynamic>{
      'type': _$TriggerTypeEnumMap[instance.type]!,
      'event': instance.event,
      'condition': instance.condition,
      'interval': instance.interval,
      'cron': instance.cron,
    };

const _$TriggerTypeEnumMap = {
  TriggerType.manual: 'manual',
  TriggerType.startup: 'startup',
  TriggerType.event: 'event',
  TriggerType.condition: 'condition',
  TriggerType.schedule: 'schedule',
};

ActionDefinition _$ActionDefinitionFromJson(Map<String, dynamic> json) =>
    ActionDefinition(
      action: json['action'] as String,
      params: json['params'] as Map<String, dynamic>?,
      bindTo: json['bindTo'] as String?,
      condition: json['condition'] as String?,
      timeout: (json['timeout'] as num?)?.toInt(),
      retry: json['retry'] == null
          ? null
          : RetryConfig.fromJson(json['retry'] as Map<String, dynamic>),
      errorHandling: json['errorHandling'] == null
          ? null
          : ErrorHandlingConfig.fromJson(
              json['errorHandling'] as Map<String, dynamic>),
      then: (json['then'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      else$: (json[r'else$'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      do$: (json['do'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      cases: (json['cases'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
            k,
            (e as List<dynamic>)
                .map(
                    (e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
                .toList()),
      ),
      value: json['value'],
      branches: (json['branches'] as List<dynamic>?)
          ?.map((e) => ParallelBranch.fromJson(e as Map<String, dynamic>))
          .toList(),
      join: json['join'] as String?,
    );

Map<String, dynamic> _$ActionDefinitionToJson(ActionDefinition instance) =>
    <String, dynamic>{
      'action': instance.action,
      'params': instance.params,
      'bindTo': instance.bindTo,
      'condition': instance.condition,
      'timeout': instance.timeout,
      'retry': instance.retry,
      'errorHandling': instance.errorHandling,
      'then': instance.then,
      r'else$': instance.else$,
      'do': instance.do$,
      'cases': instance.cases,
      'value': instance.value,
      'branches': instance.branches,
      'join': instance.join,
    };

ParallelBranch _$ParallelBranchFromJson(Map<String, dynamic> json) =>
    ParallelBranch(
      id: json['id'] as String,
      steps: (json['steps'] as List<dynamic>)
          .map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ParallelBranchToJson(ParallelBranch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'steps': instance.steps,
    };

RetryConfig _$RetryConfigFromJson(Map<String, dynamic> json) => RetryConfig(
      count: (json['count'] as num).toInt(),
      delayMs: (json['delayMs'] as num).toInt(),
      backoff: json['backoff'] as String?,
      maxDelayMs: (json['maxDelayMs'] as num?)?.toInt(),
      retryConditions: (json['retryConditions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      stopConditions: (json['stopConditions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$RetryConfigToJson(RetryConfig instance) =>
    <String, dynamic>{
      'count': instance.count,
      'delayMs': instance.delayMs,
      'backoff': instance.backoff,
      'maxDelayMs': instance.maxDelayMs,
      'retryConditions': instance.retryConditions,
      'stopConditions': instance.stopConditions,
    };

ChannelDefinition _$ChannelDefinitionFromJson(Map<String, dynamic> json) =>
    ChannelDefinition(
      type: $enumDecode(_$ChannelTypeEnumMap, json['type']),
      capacity: (json['capacity'] as num?)?.toInt(),
      overflow: json['overflow'] as String?,
      persistent: json['persistent'] as bool? ?? false,
      size: (json['size'] as num?)?.toInt(),
      mutex: json['mutex'] as bool?,
    );

Map<String, dynamic> _$ChannelDefinitionToJson(ChannelDefinition instance) =>
    <String, dynamic>{
      'type': _$ChannelTypeEnumMap[instance.type]!,
      'capacity': instance.capacity,
      'overflow': instance.overflow,
      'persistent': instance.persistent,
      'size': instance.size,
      'mutex': instance.mutex,
    };

const _$ChannelTypeEnumMap = {
  ChannelType.queue: 'queue',
  ChannelType.pubsub: 'pubsub',
  ChannelType.sharedMemory: 'shared_memory',
  ChannelType.pipe: 'pipe',
};

McpResourceBinding _$McpResourceBindingFromJson(Map<String, dynamic> json) =>
    McpResourceBinding(
      expose: json['expose'] as bool? ?? false,
      resource: json['resource'] == null
          ? null
          : McpResourceInfo.fromJson(json['resource'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$McpResourceBindingToJson(McpResourceBinding instance) =>
    <String, dynamic>{
      'expose': instance.expose,
      'resource': instance.resource,
    };

McpResourceInfo _$McpResourceInfoFromJson(Map<String, dynamic> json) =>
    McpResourceInfo(
      uri: json['uri'] as String,
      name: json['name'] as String,
      mimeType: json['mimeType'] as String?,
      updateIntervalMs: (json['updateIntervalMs'] as num?)?.toInt(),
    );

Map<String, dynamic> _$McpResourceInfoToJson(McpResourceInfo instance) =>
    <String, dynamic>{
      'uri': instance.uri,
      'name': instance.name,
      'mimeType': instance.mimeType,
      'updateIntervalMs': instance.updateIntervalMs,
    };

McpProcessBinding _$McpProcessBindingFromJson(Map<String, dynamic> json) =>
    McpProcessBinding(
      expose: json['expose'] as bool? ?? false,
      tool: json['tool'] == null
          ? null
          : McpToolInfo.fromJson(json['tool'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$McpProcessBindingToJson(McpProcessBinding instance) =>
    <String, dynamic>{
      'expose': instance.expose,
      'tool': instance.tool,
    };

McpToolInfo _$McpToolInfoFromJson(Map<String, dynamic> json) => McpToolInfo(
      name: json['name'] as String,
      description: json['description'] as String,
      inputSchema: json['inputSchema'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$McpToolInfoToJson(McpToolInfo instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'inputSchema': instance.inputSchema,
    };

SynchronizationDefinition _$SynchronizationDefinitionFromJson(
        Map<String, dynamic> json) =>
    SynchronizationDefinition();

Map<String, dynamic> _$SynchronizationDefinitionToJson(
        SynchronizationDefinition instance) =>
    <String, dynamic>{};

EventDefinition _$EventDefinitionFromJson(Map<String, dynamic> json) =>
    EventDefinition(
      id: json['id'] as String,
      type: json['type'] as String,
      source: json['source'] as String,
    );

Map<String, dynamic> _$EventDefinitionToJson(EventDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'source': instance.source,
    };

SecurityConfig _$SecurityConfigFromJson(Map<String, dynamic> json) =>
    SecurityConfig();

Map<String, dynamic> _$SecurityConfigToJson(SecurityConfig instance) =>
    <String, dynamic>{};

SafetyConfig _$SafetyConfigFromJson(Map<String, dynamic> json) =>
    SafetyConfig();

Map<String, dynamic> _$SafetyConfigToJson(SafetyConfig instance) =>
    <String, dynamic>{};

ErrorHandlingConfig _$ErrorHandlingConfigFromJson(Map<String, dynamic> json) =>
    ErrorHandlingConfig();

Map<String, dynamic> _$ErrorHandlingConfigToJson(
        ErrorHandlingConfig instance) =>
    <String, dynamic>{};

StateSecurityConfig _$StateSecurityConfigFromJson(Map<String, dynamic> json) =>
    StateSecurityConfig();

Map<String, dynamic> _$StateSecurityConfigToJson(
        StateSecurityConfig instance) =>
    <String, dynamic>{};

ProcessSecurityConfig _$ProcessSecurityConfigFromJson(
        Map<String, dynamic> json) =>
    ProcessSecurityConfig();

Map<String, dynamic> _$ProcessSecurityConfigToJson(
        ProcessSecurityConfig instance) =>
    <String, dynamic>{};
