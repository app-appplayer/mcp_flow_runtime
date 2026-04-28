import 'package:logging/logging.dart';

/// Compliance configuration
class ComplianceConfig {
  /// Supported values: 'iec62443-sl3', 'nist-csf-1.1', 'cc-eal4plus', 'gdpr', 'hipaa'
  final List<String> enabledStandards;

  const ComplianceConfig({required this.enabledStandards});
}

/// Result of evaluating a single compliance control
class ControlResult {
  /// e.g. 'IEC62443-AC-1', 'NIST-PR.AC-1'
  final String controlId;

  final String description;
  final bool passed;
  final String? failureReason;

  const ControlResult({
    required this.controlId,
    required this.description,
    required this.passed,
    this.failureReason,
  });
}

/// Compliance evaluation report
class ComplianceReport {
  final DateTime generatedAt;

  /// Map from standard identifier to its control results
  final Map<String, List<ControlResult>> results;

  const ComplianceReport({
    required this.generatedAt,
    required this.results,
  });
}

/// Compliance checker callback for evaluating system state
typedef ComplianceCheck = bool Function();

/// Manages compliance checking against defined standards.
///
/// Acts as a checklist evaluator that reports compliance status.
/// System components register their compliance state via [registerCheck].
class ComplianceManager {
  final ComplianceConfig config;

  static final _log = Logger('ComplianceManager');

  /// Registered compliance checks: controlId -> check function
  final Map<String, ComplianceCheck> _checks = {};

  ComplianceManager(this.config);

  /// Registers a compliance check for a specific control.
  /// The [check] function returns true if the control is satisfied.
  void registerCheck(String controlId, ComplianceCheck check) {
    _checks[controlId] = check;
  }

  /// Evaluates the current runtime configuration against all enabled compliance standards.
  /// Returns a [ComplianceReport] summarising pass/fail status per control.
  Future<ComplianceReport> generateReport() async {
    final results = <String, List<ControlResult>>{};

    for (final standard in config.enabledStandards) {
      final controls = _getControlsForStandard(standard);
      final controlResults = <ControlResult>[];

      for (final control in controls) {
        final check = _checks[control.controlId];
        final passed = check?.call() ?? false;

        controlResults.add(ControlResult(
          controlId: control.controlId,
          description: control.description,
          passed: passed,
          failureReason: passed
              ? null
              : (check == null
                  ? 'No compliance check registered'
                  : 'Control requirement not met'),
        ));
      }

      results[standard] = controlResults;
    }

    final report = ComplianceReport(
      generatedAt: DateTime.now(),
      results: results,
    );

    final totalControls =
        results.values.fold<int>(0, (sum, list) => sum + list.length);
    final passingControls = results.values.fold<int>(
      0,
      (sum, list) => sum + list.where((c) => c.passed).length,
    );
    _log.info(
      'Compliance report generated: $passingControls/$totalControls controls passing',
    );

    return report;
  }

  /// Returns the list of control IDs that are currently failing for the given [standard].
  Future<List<String>> getFailingControls(String standard) async {
    final controls = _getControlsForStandard(standard);
    final failing = <String>[];

    for (final control in controls) {
      final check = _checks[control.controlId];
      if (check == null || !check()) {
        failing.add(control.controlId);
      }
    }

    return failing;
  }

  /// Returns the defined controls for a compliance standard
  List<_ControlDefinition> _getControlsForStandard(String standard) {
    switch (standard) {
      case 'iec62443-sl3':
        return _iec62443Controls;
      case 'nist-csf-1.1':
        return _nistCsfControls;
      case 'cc-eal4plus':
        return _ccEal4Controls;
      case 'gdpr':
        return _gdprControls;
      case 'hipaa':
        return _hipaaControls;
      default:
        _log.warning('Unknown compliance standard: $standard');
        return [];
    }
  }
}

/// Internal control definition used for mapping
class _ControlDefinition {
  final String controlId;
  final String description;

  const _ControlDefinition(this.controlId, this.description);
}

// IEC 62443 SL3 controls
const _iec62443Controls = [
  _ControlDefinition('IEC62443-AC-1', 'Access control: user identification and authentication'),
  _ControlDefinition('IEC62443-AC-2', 'Access control: role-based access enforcement'),
  _ControlDefinition('IEC62443-UC-1', 'Use control: process authorization'),
  _ControlDefinition('IEC62443-DI-1', 'Data integrity: communication integrity verification'),
  _ControlDefinition('IEC62443-DI-2', 'Data integrity: tamper-resistant audit logging'),
  _ControlDefinition('IEC62443-DC-1', 'Data confidentiality: encryption at rest'),
  _ControlDefinition('IEC62443-DC-2', 'Data confidentiality: encryption in transit'),
  _ControlDefinition('IEC62443-AV-1', 'Availability: denial of service protection'),
];

// NIST CSF 1.1 controls
const _nistCsfControls = [
  _ControlDefinition('NIST-ID.AM-1', 'Identify: asset management and inventory'),
  _ControlDefinition('NIST-PR.AC-1', 'Protect: identity and access management'),
  _ControlDefinition('NIST-PR.AC-4', 'Protect: access permissions and authorizations'),
  _ControlDefinition('NIST-PR.DS-1', 'Protect: data-at-rest protection'),
  _ControlDefinition('NIST-PR.DS-2', 'Protect: data-in-transit protection'),
  _ControlDefinition('NIST-DE.CM-1', 'Detect: continuous monitoring'),
  _ControlDefinition('NIST-DE.CM-7', 'Detect: unauthorized activity monitoring'),
  _ControlDefinition('NIST-RS.RP-1', 'Respond: response planning execution'),
  _ControlDefinition('NIST-RC.RP-1', 'Recover: recovery planning execution'),
];

// Common Criteria EAL4+ controls
const _ccEal4Controls = [
  _ControlDefinition('CC-FDP-1', 'User data protection: access control policy'),
  _ControlDefinition('CC-FIA-1', 'Identification and authentication: user authentication'),
  _ControlDefinition('CC-FAU-1', 'Security audit: audit data generation'),
  _ControlDefinition('CC-FCS-1', 'Cryptographic support: key management'),
  _ControlDefinition('CC-FPT-1', 'Protection of the TSF: domain separation'),
  _ControlDefinition('CC-ADV-1', 'Development: security architecture description'),
];

// GDPR controls
const _gdprControls = [
  _ControlDefinition('GDPR-ART25-1', 'Privacy by Design: data protection by design'),
  _ControlDefinition('GDPR-ART32-1', 'Security of processing: encryption of personal data'),
  _ControlDefinition('GDPR-ART32-2', 'Security of processing: access control to personal data'),
  _ControlDefinition('GDPR-ART17-1', 'Right to erasure: data deletion capability'),
  _ControlDefinition('GDPR-ART20-1', 'Right to data portability: data export capability'),
  _ControlDefinition('GDPR-ART30-1', 'Records of processing: audit trail maintenance'),
];

// HIPAA controls
const _hipaaControls = [
  _ControlDefinition('HIPAA-164.312a1', 'Access control: unique user identification'),
  _ControlDefinition('HIPAA-164.312a2iv', 'Access control: encryption and decryption'),
  _ControlDefinition('HIPAA-164.312b', 'Audit controls: audit log generation'),
  _ControlDefinition('HIPAA-164.312c1', 'Integrity: data integrity mechanisms'),
  _ControlDefinition('HIPAA-164.312e1', 'Transmission security: encryption in transit'),
  _ControlDefinition('HIPAA-164.312e2', 'Transmission security: integrity controls'),
];
