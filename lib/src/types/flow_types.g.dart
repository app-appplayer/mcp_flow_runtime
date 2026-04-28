// GENERATED CODE - DO NOT MODIFY BY HAND
// Manually updated to match flow_types.dart changes (2026-03-25)

part of 'flow_types.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FlowDefinition _$FlowDefinitionFromJson(Map<String, dynamic> json) =>
    FlowDefinition(
      schema: json[r'$schema'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      metadata: json['metadata'] != null
          ? FlowMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : FlowMetadata(name: json['version'] as String? ?? 'unnamed'),
      configuration: json['configuration'] == null
          ? null
          : FlowConfiguration.fromJson(
              json['configuration'] as Map<String, dynamic>),
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
            (k, e) => MapEntry(
                k, ChannelDefinition.fromJson(e as Map<String, dynamic>)),
          ) ??
          const {},
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
      uiDefinitions: json['uiDefinitions'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$FlowDefinitionToJson(FlowDefinition instance) =>
    <String, dynamic>{
      r'$schema': instance.schema,
      'version': instance.version,
      'metadata': instance.metadata.toJson(),
      'configuration': instance.configuration?.toJson(),
      'resources': instance.resources.map((k, e) => MapEntry(k, e.toJson())),
      'state': instance.state.map((k, e) => MapEntry(k, e.toJson())),
      'channels': instance.channels.map((k, e) => MapEntry(k, e.toJson())),
      'synchronization': instance.synchronization?.toJson(),
      'processes': instance.processes.map((e) => e.toJson()).toList(),
      'events': instance.events?.map((e) => e.toJson()).toList(),
      'uiDefinitions': instance.uiDefinitions,
    };

FlowConfiguration _$FlowConfigurationFromJson(Map<String, dynamic> json) =>
    FlowConfiguration(
      hal: json['hal'] as Map<String, dynamic>?,
      runtime: json['runtime'] == null
          ? null
          : RuntimeLimitsConfig.fromJson(
              json['runtime'] as Map<String, dynamic>),
      mcp: json['mcp'] == null
          ? null
          : McpConfig.fromJson(json['mcp'] as Map<String, dynamic>),
      system: json['system'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$FlowConfigurationToJson(FlowConfiguration instance) =>
    <String, dynamic>{
      'hal': instance.hal,
      'runtime': instance.runtime?.toJson(),
      'mcp': instance.mcp?.toJson(),
      'system': instance.system,
    };

RuntimeLimitsConfig _$RuntimeLimitsConfigFromJson(Map<String, dynamic> json) =>
    RuntimeLimitsConfig(
      tickRateMs: (json['tickRateMs'] as num?)?.toInt(),
      maxProcesses: (json['maxProcesses'] as num?)?.toInt(),
      maxMemoryKB: (json['maxMemoryKB'] as num?)?.toInt(),
    );

Map<String, dynamic> _$RuntimeLimitsConfigToJson(
        RuntimeLimitsConfig instance) =>
    <String, dynamic>{
      'tickRateMs': instance.tickRateMs,
      'maxProcesses': instance.maxProcesses,
      'maxMemoryKB': instance.maxMemoryKB,
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
    );

Map<String, dynamic> _$FlowMetadataToJson(FlowMetadata instance) =>
    <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'author': instance.author,
      'created': instance.created?.toIso8601String(),
      'modified': instance.modified?.toIso8601String(),
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
      'mcp': instance.mcp?.toJson(),
      'security': instance.security?.toJson(),
      'safety': instance.safety?.toJson(),
      'errorHandling': instance.errorHandling?.toJson(),
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
      'constraints': instance.constraints?.toJson(),
      'security': instance.security?.toJson(),
    };

const _$StateTypeEnumMap = {
  StateType.boolean: 'boolean',
  StateType.number: 'number',
  StateType.string: 'string',
  StateType.object: 'object',
  StateType.array: 'array',
  StateType.any: 'any',
};

StateConstraints _$StateConstraintsFromJson(Map<String, dynamic> json) =>
    StateConstraints(
      min: json['min'] as num?,
      max: json['max'] as num?,
      minLength: (json['minLength'] as num?)?.toInt(),
      maxLength: (json['maxLength'] as num?)?.toInt(),
      pattern: json['pattern'] as String?,
      enum$: json['enum'] as List<dynamic>?,
      minItems: (json['minItems'] as num?)?.toInt(),
      maxItems: (json['maxItems'] as num?)?.toInt(),
      validate: json['validate'] as String?,
    );

Map<String, dynamic> _$StateConstraintsToJson(StateConstraints instance) =>
    <String, dynamic>{
      'min': instance.min,
      'max': instance.max,
      'minLength': instance.minLength,
      'maxLength': instance.maxLength,
      'pattern': instance.pattern,
      'enum': instance.enum$,
      'minItems': instance.minItems,
      'maxItems': instance.maxItems,
      'validate': instance.validate,
    };

ProcessDefinition _$ProcessDefinitionFromJson(Map<String, dynamic> json) =>
    ProcessDefinition(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      description: json['description'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      trigger: json['trigger'] == null
          ? null
          : TriggerDefinition.fromJson(
              json['trigger'] as Map<String, dynamic>),
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
      finally$: (json['finally'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ProcessDefinitionToJson(ProcessDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'enabled': instance.enabled,
      'trigger': instance.trigger?.toJson(),
      'loop': instance.loop,
      'priority': _$ProcessPriorityEnumMap[instance.priority]!,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
      'error': instance.error?.map((e) => e.toJson()).toList(),
      'finally': instance.finally$?.map((e) => e.toJson()).toList(),
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
      delay: (json['delay'] as num?)?.toInt(),
      variable: json['variable'] as String?,
      channel: json['channel'] as String?,
      resource: json['resource'] as String?,
      debounceMs: (json['debounceMs'] as num?)?.toInt(),
    );

Map<String, dynamic> _$TriggerDefinitionToJson(TriggerDefinition instance) =>
    <String, dynamic>{
      'type': _$TriggerTypeEnumMap[instance.type]!,
      'event': instance.event,
      'condition': instance.condition,
      'interval': instance.interval,
      'cron': instance.cron,
      'delay': instance.delay,
      'variable': instance.variable,
      'channel': instance.channel,
      'resource': instance.resource,
      'debounceMs': instance.debounceMs,
    };

const _$TriggerTypeEnumMap = {
  TriggerType.manual: 'manual',
  TriggerType.startup: 'startup',
  TriggerType.event: 'event',
  TriggerType.condition: 'condition',
  TriggerType.schedule: 'schedule',
  TriggerType.channelReceive: 'channelReceive',
  TriggerType.stateChange: 'stateChange',
  TriggerType.resourceEvent: 'resourceEvent',
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
      then: (json['then'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      else$: (json['else'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      do$: (json['do'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      try$: (json['try'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      catch$: (json['catch'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      finally$: (json['finally'] as List<dynamic>?)
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
          ?.map((e) => BranchDefinition.fromJson(e as Map<String, dynamic>))
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
      'retry': instance.retry?.toJson(),
      'then': instance.then?.map((e) => e.toJson()).toList(),
      'else': instance.else$?.map((e) => e.toJson()).toList(),
      'do': instance.do$?.map((e) => e.toJson()).toList(),
      'try': instance.try$?.map((e) => e.toJson()).toList(),
      'catch': instance.catch$?.map((e) => e.toJson()).toList(),
      'finally': instance.finally$?.map((e) => e.toJson()).toList(),
      'cases': instance.cases
          ?.map((k, e) => MapEntry(k, e.map((e) => e.toJson()).toList())),
      'value': instance.value,
      'branches': instance.branches?.map((e) => e.toJson()).toList(),
      'join': instance.join,
    };

BranchDefinition _$BranchDefinitionFromJson(Map<String, dynamic> json) =>
    BranchDefinition(
      id: json['id'] as String,
      steps: (json['steps'] as List<dynamic>)
          .map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$BranchDefinitionToJson(BranchDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
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
      persistent: json['persistent'] as bool?,
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
  ChannelType.sharedMemory: 'sharedMemory',
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
      'resource': instance.resource?.toJson(),
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
    SynchronizationDefinition(
      mutexes: (json['mutexes'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, MutexDefinition.fromJson(e as Map<String, dynamic>)),
      ),
      semaphores: (json['semaphores'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
            k, SemaphoreDefinition.fromJson(e as Map<String, dynamic>)),
      ),
      barriers: (json['barriers'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, BarrierDefinition.fromJson(e as Map<String, dynamic>)),
      ),
      events: (json['events'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
            k, EventSyncDefinition.fromJson(e as Map<String, dynamic>)),
      ),
    );

Map<String, dynamic> _$SynchronizationDefinitionToJson(
        SynchronizationDefinition instance) =>
    <String, dynamic>{
      'mutexes': instance.mutexes?.map((k, e) => MapEntry(k, e.toJson())),
      'semaphores':
          instance.semaphores?.map((k, e) => MapEntry(k, e.toJson())),
      'barriers': instance.barriers?.map((k, e) => MapEntry(k, e.toJson())),
      'events': instance.events?.map((k, e) => MapEntry(k, e.toJson())),
    };

MutexDefinition _$MutexDefinitionFromJson(Map<String, dynamic> json) =>
    MutexDefinition(
      timeoutMs: (json['timeoutMs'] as num?)?.toInt(),
      priorityInheritance: json['priorityInheritance'] as bool?,
    );

Map<String, dynamic> _$MutexDefinitionToJson(MutexDefinition instance) =>
    <String, dynamic>{
      'timeoutMs': instance.timeoutMs,
      'priorityInheritance': instance.priorityInheritance,
    };

SemaphoreDefinition _$SemaphoreDefinitionFromJson(
        Map<String, dynamic> json) =>
    SemaphoreDefinition(
      initial: (json['initial'] as num).toInt(),
      max: (json['max'] as num?)?.toInt(),
    );

Map<String, dynamic> _$SemaphoreDefinitionToJson(
        SemaphoreDefinition instance) =>
    <String, dynamic>{
      'initial': instance.initial,
      'max': instance.max,
    };

BarrierDefinition _$BarrierDefinitionFromJson(Map<String, dynamic> json) =>
    BarrierDefinition(
      count: (json['count'] as num).toInt(),
      autoReset: json['autoReset'] as bool?,
    );

Map<String, dynamic> _$BarrierDefinitionToJson(BarrierDefinition instance) =>
    <String, dynamic>{
      'count': instance.count,
      'autoReset': instance.autoReset,
    };

EventSyncDefinition _$EventSyncDefinitionFromJson(
        Map<String, dynamic> json) =>
    EventSyncDefinition(
      autoReset: json['autoReset'] as bool?,
      initialState: json['initialState'] as bool?,
    );

Map<String, dynamic> _$EventSyncDefinitionToJson(
        EventSyncDefinition instance) =>
    <String, dynamic>{
      'autoReset': instance.autoReset,
      'initialState': instance.initialState,
    };

EventDefinition _$EventDefinitionFromJson(Map<String, dynamic> json) =>
    EventDefinition(
      id: json['id'] as String,
      type: json['type'] as String,
      source: json['source'] as String,
      condition: json['condition'] as String?,
      debounceMs: (json['debounceMs'] as num?)?.toInt(),
      actions: (json['actions'] as List<dynamic>?)
          ?.map((e) => ActionDefinition.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
    );

Map<String, dynamic> _$EventDefinitionToJson(EventDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'source': instance.source,
      'condition': instance.condition,
      'debounceMs': instance.debounceMs,
      'actions': instance.actions.map((e) => e.toJson()).toList(),
    };

SecurityConfig _$SecurityConfigFromJson(Map<String, dynamic> json) =>
    SecurityConfig(
      requireAuth: json['requireAuth'] as bool?,
      allowedRoles: (json['allowedRoles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      auditLog: json['auditLog'] as bool?,
      confirmationRequired: json['confirmationRequired'] as bool?,
      rateLimit: json['rateLimit'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$SecurityConfigToJson(SecurityConfig instance) =>
    <String, dynamic>{
      'requireAuth': instance.requireAuth,
      'allowedRoles': instance.allowedRoles,
      'auditLog': instance.auditLog,
      'confirmationRequired': instance.confirmationRequired,
      'rateLimit': instance.rateLimit,
    };

SafetyConfig _$SafetyConfigFromJson(Map<String, dynamic> json) => SafetyConfig(
      maxDutyCycle: (json['maxDutyCycle'] as num?)?.toDouble(),
      maxTemperature: (json['maxTemperature'] as num?)?.toDouble(),
      currentLimit: (json['currentLimit'] as num?)?.toDouble(),
      protectionAction: json['protectionAction'] as String?,
      cooldownPeriod: (json['cooldownPeriod'] as num?)?.toInt(),
    );

Map<String, dynamic> _$SafetyConfigToJson(SafetyConfig instance) =>
    <String, dynamic>{
      'maxDutyCycle': instance.maxDutyCycle,
      'maxTemperature': instance.maxTemperature,
      'currentLimit': instance.currentLimit,
      'protectionAction': instance.protectionAction,
      'cooldownPeriod': instance.cooldownPeriod,
    };

ErrorHandlingConfig _$ErrorHandlingConfigFromJson(Map<String, dynamic> json) =>
    ErrorHandlingConfig();

Map<String, dynamic> _$ErrorHandlingConfigToJson(
        ErrorHandlingConfig instance) =>
    <String, dynamic>{};

StateSecurityConfig _$StateSecurityConfigFromJson(Map<String, dynamic> json) =>
    StateSecurityConfig(
      encrypted: json['encrypted'] as bool?,
      algorithm: json['algorithm'] as String?,
      masked: json['masked'] as bool?,
      readRoles: (json['readRoles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      writeRoles: (json['writeRoles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      auditLog: json['auditLog'] as bool?,
      critical: json['critical'] as bool?,
    );

Map<String, dynamic> _$StateSecurityConfigToJson(
        StateSecurityConfig instance) =>
    <String, dynamic>{
      'encrypted': instance.encrypted,
      'algorithm': instance.algorithm,
      'masked': instance.masked,
      'readRoles': instance.readRoles,
      'writeRoles': instance.writeRoles,
      'auditLog': instance.auditLog,
      'critical': instance.critical,
    };

McpTool _$McpToolFromJson(Map<String, dynamic> json) => McpTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$McpToolToJson(McpTool instance) => <String, dynamic>{
      'name': instance.name,
      'description': instance.description,
      'inputSchema': instance.inputSchema,
    };

McpResource _$McpResourceFromJson(Map<String, dynamic> json) => McpResource(
      name: json['name'] as String,
      uri: json['uri'] as String,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      content: json['content'],
    );

Map<String, dynamic> _$McpResourceToJson(McpResource instance) =>
    <String, dynamic>{
      'name': instance.name,
      'uri': instance.uri,
      'description': instance.description,
      'mimeType': instance.mimeType,
      'content': instance.content,
    };

McpConfig _$McpConfigFromJson(Map<String, dynamic> json) => McpConfig(
      mode: $enumDecodeNullable(_$McpModeEnumMap, json['mode']) ??
          McpMode.standard,
      extendedData: json['extendedData'] as bool?,
      fallback: json['fallback'] as Map<String, dynamic>?,
      tools: (json['tools'] as List<dynamic>?)
          ?.map((e) => McpTool.fromJson(e as Map<String, dynamic>))
          .toList(),
      resources: (json['resources'] as List<dynamic>?)
          ?.map((e) => McpResource.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$McpConfigToJson(McpConfig instance) =>
    <String, dynamic>{
      'mode': _$McpModeEnumMap[instance.mode]!,
      'extendedData': instance.extendedData,
      'fallback': instance.fallback,
      'tools': instance.tools?.map((e) => e.toJson()).toList(),
      'resources': instance.resources?.map((e) => e.toJson()).toList(),
    };

const _$McpModeEnumMap = {
  McpMode.standard: 'standard',
  McpMode.extended: 'extended',
};
