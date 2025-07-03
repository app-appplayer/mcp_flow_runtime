# MCP Flow Runtime 구현 계획 (Dart)

## 📋 프로젝트 개요

### 프로젝트명: `mcp_flow_runtime`
- **기반**: makemind의 `mcp_server` 패키지
- **언어**: Dart
- **대상 플랫폼**: Linux, macOS, Windows (임베디드 시스템 포함)
- **목표**: MCP Flow DSL v1.0 스펙의 완전한 구현

## 🏗️ 아키텍처 설계

### 1. 전체 구조
```
mcp_flow_runtime/
├── lib/
│   ├── src/
│   │   ├── core/               # 핵심 런타임 엔진
│   │   │   ├── runtime.dart
│   │   │   ├── scheduler.dart
│   │   │   ├── process_executor.dart
│   │   │   └── action_executor.dart
│   │   ├── hal/                # Hardware Abstraction Layer
│   │   │   ├── hal_interface.dart
│   │   │   ├── hal_factory.dart
│   │   │   └── providers/
│   │   │       ├── linux_hal.dart
│   │   │       ├── macos_hal.dart
│   │   │       ├── windows_hal.dart
│   │   │       └── mock_hal.dart
│   │   ├── state/              # 상태 관리
│   │   │   ├── state_manager.dart
│   │   │   ├── state_store.dart
│   │   │   └── persistence.dart
│   │   ├── actions/            # 액션 구현
│   │   │   ├── hardware/
│   │   │   ├── control_flow/
│   │   │   ├── state/
│   │   │   └── system/
│   │   ├── mcp/                # MCP 통합
│   │   │   ├── flow_mcp_server.dart
│   │   │   ├── tool_registry.dart
│   │   │   └── resource_registry.dart
│   │   ├── parser/             # DSL 파서
│   │   │   ├── json_parser.dart
│   │   │   ├── compact_parser.dart
│   │   │   └── validator.dart
│   │   └── security/           # 보안
│   │       ├── auth_manager.dart
│   │       ├── permission_checker.dart
│   │       └── encryption.dart
│   └── mcp_flow_runtime.dart
├── bin/
│   └── mcp_flow_runtime.dart   # 실행 파일
├── test/
├── example/
└── pubspec.yaml
```

## 🛠️ 구현 단계

### Phase 1: 기본 구조 구축 (2주)
```dart
// lib/src/mcp/flow_mcp_server.dart
import 'package:mcp_server/mcp_server.dart';

class FlowMcpServer extends McpServer {
  final FlowRuntime runtime;
  final ToolRegistry toolRegistry;
  final ResourceRegistry resourceRegistry;
  
  FlowMcpServer({
    required this.runtime,
    super.serverInfo = const ServerInfo(
      name: 'MCP Flow Runtime',
      version: '1.0.0',
    ),
  });
  
  @override
  Future<void> initialize() async {
    await super.initialize();
    
    // 표준 MCP 도구 등록
    _registerStandardTools();
    _registerStandardResources();
    
    // Flow DSL 로드
    await runtime.initialize();
  }
}
```

### Phase 2: HAL 구현 (2주)
```dart
// lib/src/hal/hal_interface.dart
abstract class HardwareAbstractionLayer {
  // GPIO
  Future<void> gpioWrite(int pin, bool value);
  Future<bool> gpioRead(int pin);
  Future<void> gpioConfig(int pin, GpioMode mode);
  
  // I2C
  Future<Uint8List> i2cRead(int bus, int address, int register, int length);
  Future<void> i2cWrite(int bus, int address, int register, Uint8List data);
  
  // PWM
  Future<void> pwmSet(int channel, double frequency, double dutyCycle);
  
  // Modbus
  Future<ModbusClient> modbusConnect(ModbusConfig config);
  Future<List<bool>> modbusReadCoils(ModbusClient client, int slaveId, int start, int count);
  
  // 플랫폼 탐지
  static HardwareAbstractionLayer create() {
    if (Platform.isLinux) return LinuxHAL();
    if (Platform.isMacOS) return MacOSHAL();
    if (Platform.isWindows) return WindowsHAL();
    throw UnsupportedError('Platform not supported');
  }
}
```

### Phase 3: 프로세스 스케줄러 (2주)
```dart
// lib/src/core/scheduler.dart
class ProcessScheduler {
  final PriorityQueue<ScheduledProcess> readyQueue;
  final Map<String, Process> processes = {};
  final Map<String, Timer> timers = {};
  
  void scheduleProcess(Process process) {
    switch (process.trigger.type) {
      case TriggerType.manual:
        // 수동 실행 대기
        break;
      case TriggerType.schedule:
        // 타이머 설정
        final interval = Duration(milliseconds: process.trigger.interval);
        timers[process.id] = Timer.periodic(interval, (_) {
          enqueueProcess(process);
        });
        break;
      case TriggerType.event:
        // 이벤트 리스너 등록
        eventBus.on(process.trigger.event).listen((_) {
          enqueueProcess(process);
        });
        break;
    }
  }
}
```

### Phase 4: 액션 실행기 (2주)
```dart
// lib/src/core/action_executor.dart
class ActionExecutor {
  final Map<String, ActionHandler> handlers = {};
  final ExpressionEvaluator evaluator;
  
  Future<ActionResult> execute(Action action, ExecutionContext context) async {
    final handler = handlers[action.type];
    if (handler == null) {
      throw UnknownActionError(action.type);
    }
    
    // 파라미터 평가
    final params = await _evaluateParams(action.params, context);
    
    // 재시도 로직
    return _executeWithRetry(
      () => handler.execute(params, context),
      action.retry,
    );
  }
  
  void registerHandler(String actionType, ActionHandler handler) {
    handlers[actionType] = handler;
  }
}
```

### Phase 5: 상태 관리 (1주)
```dart
// lib/src/state/state_manager.dart
class StateManager {
  final StateStore volatileStore;
  final StateStore? persistentStore;
  final StreamController<StateChange> _changeController;
  
  Future<void> set(String key, dynamic value) async {
    final definition = stateDefinitions[key];
    if (definition == null) {
      throw UnknownStateError(key);
    }
    
    // 타입 검증
    _validateType(value, definition.type);
    
    // 값 저장
    if (definition.persistent && persistentStore != null) {
      await persistentStore.set(key, value);
    } else {
      await volatileStore.set(key, value);
    }
    
    // 변경 알림
    _changeController.add(StateChange(key, value));
  }
}
```

### Phase 6: MCP 통합 (2주)
```dart
// lib/src/mcp/tool_registry.dart
class ToolRegistry {
  final McpServer server;
  
  void registerStandardTools() {
    // Runtime Management
    server.registerTool(Tool(
      name: 'runtime.status',
      description: 'Get runtime status and statistics',
      inputSchema: {},
      handler: (params) async {
        return {
          'status': runtime.status.name,
          'uptime': runtime.uptime.inMilliseconds,
          'processCount': runtime.processCount,
          'memoryUsage': runtime.memoryUsage,
        };
      },
    ));
    
    // Process Control
    server.registerTool(Tool(
      name: 'process.start',
      description: 'Start a process',
      inputSchema: {
        'type': 'object',
        'properties': {
          'processId': {'type': 'string'},
          'args': {'type': 'object'},
        },
        'required': ['processId'],
      },
      handler: (params) async {
        await runtime.startProcess(
          params['processId'] as String,
          args: params['args'] as Map<String, dynamic>?,
        );
        return {'success': true};
      },
    ));
  }
}
```

### Phase 7: 보안 구현 (1주)
```dart
// lib/src/security/auth_manager.dart
class AuthManager {
  final Map<String, User> users = {};
  final Map<String, Role> roles = {};
  
  Future<bool> authenticate(String token) async {
    // 토큰 검증
    final claims = await verifyToken(token);
    return claims != null;
  }
  
  Future<bool> authorize(String user, String action, String? resource) async {
    final userObj = users[user];
    if (userObj == null) return false;
    
    for (final roleName in userObj.roles) {
      final role = roles[roleName];
      if (role?.hasPermission(action, resource) ?? false) {
        return true;
      }
    }
    
    return false;
  }
}
```

### Phase 8: Compact Format (2주)
```dart
// lib/src/parser/compact_parser.dart
class CompactFormatParser {
  static const magic = [0x46, 0x43, 0x4D, 0x50]; // 'FCMP'
  
  FlowDefinition parse(Uint8List data) {
    final reader = ByteDataReader(data);
    
    // 헤더 검증
    final header = _readHeader(reader);
    if (!_validateMagic(header.magic)) {
      throw InvalidFormatError('Invalid magic number');
    }
    
    // 섹션 테이블 읽기
    final sections = _readSectionTable(reader);
    
    // 각 섹션 파싱
    final stringTable = _readStringTable(reader, sections.stringTable);
    final stateTable = _readStateTable(reader, sections.stateTable, stringTable);
    final processes = _readProcessTable(reader, sections.processTable, stringTable);
    
    return FlowDefinition(
      states: stateTable,
      processes: processes,
    );
  }
}
```

## 📦 외부 의존성

```yaml
# pubspec.yaml
name: mcp_flow_runtime
version: 1.0.0
description: MCP Flow DSL Runtime implementation

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  # MCP 기반
  mcp_server: ^1.0.0
  
  # 하드웨어 제어
  flutter_gpiod: ^0.5.0        # Linux GPIO
  dart_periphery: ^0.9.0       # I2C, SPI, UART
  modbus_client: ^1.0.0        # Modbus 프로토콜
  
  # 유틸리티
  collection: ^1.18.0
  async: ^2.11.0
  logging: ^1.2.0
  path: ^1.8.0
  
  # 보안
  crypto: ^3.0.0
  jose: ^0.3.0                 # JWT
  
  # 상태 저장
  hive: ^2.2.0                 # 경량 DB

dev_dependencies:
  test: ^1.24.0
  mockito: ^5.4.0
  build_runner: ^2.4.0
```

## 🚀 실행 예제

```dart
// bin/mcp_flow_runtime.dart
import 'package:mcp_flow_runtime/mcp_flow_runtime.dart';

void main(List<String> args) async {
  // 런타임 생성
  final runtime = FlowRuntime(
    hal: HardwareAbstractionLayer.create(),
    config: RuntimeConfig(
      maxProcesses: 50,
      maxMemoryMB: 128,
    ),
  );
  
  // MCP 서버 생성
  final server = FlowMcpServer(
    runtime: runtime,
    transport: StdioTransport(),
  );
  
  // Flow DSL 로드
  if (args.isNotEmpty) {
    await runtime.loadFlow(args[0]);
  }
  
  // 서버 시작
  await server.start();
}
```

## 📊 개발 일정

| 단계 | 기간 | 산출물 |
|------|------|--------|
| Phase 1: 기본 구조 | 2주 | MCP 서버 통합, 기본 런타임 |
| Phase 2: HAL | 2주 | 크로스 플랫폼 하드웨어 제어 |
| Phase 3: 스케줄러 | 2주 | 프로세스 스케줄링 시스템 |
| Phase 4: 액션 실행 | 2주 | 모든 액션 타입 구현 |
| Phase 5: 상태 관리 | 1주 | 상태 저장 및 영속성 |
| Phase 6: MCP 통합 | 2주 | 표준 도구/리소스 노출 |
| Phase 7: 보안 | 1주 | 인증/인가, 암호화 |
| Phase 8: Compact | 2주 | 바이너리 포맷 지원 |
| **총 기간** | **14주** | **v1.0 출시** |

## 🧪 테스트 전략

1. **단위 테스트**: 각 컴포넌트별 격리 테스트
2. **통합 테스트**: MCP 프로토콜 준수 확인
3. **하드웨어 테스트**: Mock HAL과 실제 하드웨어 테스트
4. **성능 테스트**: 메모리 사용량, 응답 시간
5. **보안 테스트**: 침투 테스트, 권한 검증

이 계획을 따라 구현하면 3-4개월 내에 프로덕션 준비가 완료된 `mcp_flow_runtime`을 완성할 수 있습니다!