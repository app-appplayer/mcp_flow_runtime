import 'package:logging/logging.dart';

import 'auth_manager.dart';
import 'rbac_manager.dart';
import 'audit_logger.dart';
import 'isolation_manager.dart';
import 'key_manager.dart';
import 'compliance_manager.dart';

// Re-export all sub-module types for convenience
export 'auth_manager.dart';
export 'rbac_manager.dart';
export 'audit_logger.dart';
export 'isolation_manager.dart';
export 'key_manager.dart';
export 'compliance_manager.dart';

/// Incident response SLA configuration
class IncidentSla {
  /// Maximum resolution time in seconds for each severity level
  final int criticalSeconds;
  final int highSeconds;
  final int mediumSeconds;

  const IncidentSla({
    this.criticalSeconds = 3600,
    this.highSeconds = 14400,
    this.mediumSeconds = 86400,
  });
}

/// Incident response configuration
class IncidentResponseConfig {
  final String contactEmail;
  final IncidentSla sla;
  final BruteForceConfig bruteForce;

  const IncidentResponseConfig({
    required this.contactEmail,
    this.sla = const IncidentSla(),
    this.bruteForce = const BruteForceConfig(),
  });
}

/// Top-level security configuration containing all sub-module settings
class SecurityConfig {
  final AuthConfig auth;
  final RbacConfig rbac;
  final AuditConfig audit;
  final IsolationConfig isolation;
  final KeyManagementConfig keyManagement;
  final ComplianceConfig compliance;
  final IncidentResponseConfig? incidentResponse;

  const SecurityConfig({
    required this.auth,
    required this.rbac,
    required this.audit,
    required this.isolation,
    required this.keyManagement,
    required this.compliance,
    this.incidentResponse,
  });
}

/// Unified security facade that coordinates all security sub-modules.
///
/// Provides a single entry point for initializing and shutting down
/// authentication, RBAC, audit logging, process isolation, key management,
/// and compliance checking.
class SecurityManager {
  final SecurityConfig config;

  final AuthManager auth;
  final RbacManager rbac;
  final AuditLogger audit;
  final IsolationManager isolation;
  final KeyManager keys;
  final ComplianceManager compliance;

  static final _log = Logger('SecurityManager');

  SecurityManager(this.config)
      : auth = AuthManager(config.auth),
        rbac = RbacManager(config.rbac),
        audit = AuditLogger(
          config.audit,
          bruteForceConfig:
              config.incidentResponse?.bruteForce ?? const BruteForceConfig(),
        ),
        isolation = IsolationManager(config.isolation),
        keys = KeyManager(config.keyManagement),
        compliance = ComplianceManager(config.compliance);

  /// Initialises all sub-managers and applies isolation/memory protection.
  Future<void> initialise() async {
    _log.info('Initializing SecurityManager');

    // Initialize audit logger first so other modules can log
    await audit.initialize();

    // Apply process isolation and memory protection
    await isolation.applyIsolation();
    await isolation.applyMemoryProtection();

    // Pre-load master key
    try {
      await keys.getMasterKey();
    } catch (e) {
      _log.warning('Could not pre-load master key: $e');
    }

    _log.info('SecurityManager initialized successfully');
  }

  /// Shuts down all sub-managers and flushes the audit log.
  Future<void> shutdown() async {
    _log.info('Shutting down SecurityManager');
    await audit.shutdown();
    _log.info('SecurityManager shut down');
  }
}
