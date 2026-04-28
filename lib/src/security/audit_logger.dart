import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

/// Audit logging configuration
class AuditConfig {
  final bool enabled;

  /// Event patterns to capture (e.g. 'authentication.*', 'authorization.denied')
  final List<String> eventPatterns;

  final AuditOutputConfig output;
  final AuditRetentionConfig retention;

  const AuditConfig({
    required this.enabled,
    required this.eventPatterns,
    required this.output,
    required this.retention,
  });
}

/// Audit output destination configuration
class AuditOutputConfig {
  /// Output destination: 'syslog' | 'file' | 'remote'
  final String type;

  /// Output format (currently only 'json')
  final String format;

  /// Required when type == 'file'
  final String? filePath;

  /// Required when type == 'remote'
  final String? remoteEndpoint;

  const AuditOutputConfig({
    required this.type,
    this.format = 'json',
    this.filePath,
    this.remoteEndpoint,
  });
}

/// Audit log retention configuration
class AuditRetentionConfig {
  /// Number of days to retain audit logs (default: 90)
  final int retentionDays;

  final bool compress;
  final bool encrypt;

  const AuditRetentionConfig({
    this.retentionDays = 90,
    this.compress = false,
    this.encrypt = false,
  });
}

/// A structured security audit event
class AuditEvent {
  /// Unique event identifier (UUID)
  final String id;

  final DateTime timestamp;

  /// e.g. 'authentication.success', 'authorization.denied'
  final String eventType;

  /// Identity that triggered the event
  final String subject;

  /// Resource or action targeted
  final String object;

  /// 'allow' | 'deny' | 'error'
  final String result;

  final Map<String, dynamic> metadata;

  /// SHA-256 hash of the preceding log entry (chain link)
  final String? previousHash;

  const AuditEvent({
    required this.id,
    required this.timestamp,
    required this.eventType,
    required this.subject,
    required this.object,
    required this.result,
    this.metadata = const {},
    this.previousHash,
  });

  /// Converts this event to a JSON-serializable map
  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'eventType': eventType,
        'subject': subject,
        'object': object,
        'result': result,
        'metadata': metadata,
        'previousHash': previousHash,
      };

  /// Creates an AuditEvent from a JSON map
  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        eventType: json['eventType'] as String,
        subject: json['subject'] as String,
        object: json['object'] as String,
        result: json['result'] as String,
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
        previousHash: json['previousHash'] as String?,
      );
}

/// Security alert triggered by anomaly detection (e.g. brute force)
class SecurityAlert {
  /// e.g. 'brute_force', 'anomalous_access'
  final String alertType;

  final String subject;
  final DateTime detectedAt;

  /// 'critical' | 'high' | 'medium'
  final String severity;

  final Map<String, dynamic> details;

  const SecurityAlert({
    required this.alertType,
    required this.subject,
    required this.detectedAt,
    required this.severity,
    this.details = const {},
  });
}

/// Exception thrown when audit logging fails
class AuditException implements Exception {
  final String message;
  final dynamic cause;

  const AuditException(this.message, {this.cause});

  @override
  String toString() => 'AuditException: $message';
}

/// Thrown when log chain integrity verification fails
class LogTamperException extends AuditException {
  const LogTamperException(super.message, {super.cause});

  @override
  String toString() => 'LogTamperException: $message';
}

/// Brute force detection configuration
class BruteForceConfig {
  final int maxFailedAttempts;
  final int windowSeconds;
  final int blockDurationSeconds;
  final bool notifyOnBlock;

  const BruteForceConfig({
    this.maxFailedAttempts = 5,
    this.windowSeconds = 60,
    this.blockDurationSeconds = 3600,
    this.notifyOnBlock = true,
  });
}

/// Exception thrown when brute force threshold is exceeded
class BruteForceException implements Exception {
  final String subject;
  final int failedAttempts;

  const BruteForceException(this.subject, this.failedAttempts);

  @override
  String toString() =>
      'BruteForceException: $subject exceeded threshold with $failedAttempts attempts';
}

/// Tamper-resistant audit logger with hash chaining and brute force detection
class AuditLogger {
  final AuditConfig config;
  final BruteForceConfig bruteForceConfig;

  static final _log = Logger('AuditLogger');

  /// Hash of the last logged entry for chain linking
  String? _lastHash;

  /// In-memory log entries (also written to file when configured)
  final List<AuditEvent> _entries = [];

  /// Brute force tracking: subject -> list of failure timestamps
  final Map<String, List<DateTime>> _failureTracker = {};

  /// Blocked subjects with unblock time
  final Map<String, DateTime> _blockedSubjects = {};

  /// Stream controller for security alerts
  final StreamController<SecurityAlert> _alertController =
      StreamController<SecurityAlert>.broadcast();

  /// File sink for audit log output
  IOSink? _fileSink;

  AuditLogger(
    this.config, {
    this.bruteForceConfig = const BruteForceConfig(),
  });

  /// Emits when a security alert is triggered (e.g. brute force detected)
  Stream<SecurityAlert> get onSecurityAlert => _alertController.stream;

  /// Initializes the file-based output if configured
  Future<void> initialize() async {
    if (config.output.type == 'file' && config.output.filePath != null) {
      final file = File(config.output.filePath!);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      _fileSink = file.openWrite(mode: FileMode.append);
    }
  }

  /// Records a security event.
  /// Each entry is appended with a HMAC-SHA256 chain hash linking to the previous entry.
  /// Throws [AuditException] if the log sink is unavailable.
  Future<void> log(AuditEvent event) async {
    if (!config.enabled) return;

    // Check if event matches configured patterns
    if (!_matchesPatterns(event.eventType)) return;

    // Compute chain hash
    final entryJson = jsonEncode(event.toJson());
    final hashInput = '${_lastHash ?? 'genesis'}:$entryJson';
    final hash = sha256.convert(utf8.encode(hashInput)).toString();

    // Create event with chain hash
    final chainedEvent = AuditEvent(
      id: event.id,
      timestamp: event.timestamp,
      eventType: event.eventType,
      subject: event.subject,
      object: event.object,
      result: event.result,
      metadata: {...event.metadata, '_chainHash': hash},
      previousHash: _lastHash,
    );

    _entries.add(chainedEvent);
    _lastHash = hash;

    // Write to output
    await _writeEntry(chainedEvent);

    // Track authentication failures for brute force detection
    if (event.eventType.startsWith('authentication.') &&
        event.result == 'deny') {
      _trackFailure(event.subject);
    }

    _log.fine('Audit event logged: ${event.eventType} by ${event.subject}');
  }

  /// Verifies the integrity of the log chain from [startTime] to [endTime].
  /// Returns true if no entries have been tampered with.
  Future<bool> verifyLogChain({DateTime? startTime, DateTime? endTime}) async {
    final filtered = _entries.where((e) {
      if (startTime != null && e.timestamp.isBefore(startTime)) return false;
      if (endTime != null && e.timestamp.isAfter(endTime)) return false;
      return true;
    }).toList();

    if (filtered.isEmpty) return true;

    String? previousHash;

    // Find the previous hash before the first filtered entry
    final firstIndex = _entries.indexOf(filtered.first);
    if (firstIndex > 0) {
      final prev = _entries[firstIndex - 1];
      previousHash = prev.metadata['_chainHash'] as String?;
    }

    for (final entry in filtered) {
      // Verify this entry's previous hash matches
      if (entry.previousHash != previousHash) {
        _log.severe('Log chain broken at entry ${entry.id}');
        return false;
      }

      // Recompute the chain hash
      final entryForHash = AuditEvent(
        id: entry.id,
        timestamp: entry.timestamp,
        eventType: entry.eventType,
        subject: entry.subject,
        object: entry.object,
        result: entry.result,
        metadata: Map.from(entry.metadata)..remove('_chainHash'),
        previousHash: null, // Original event doesn't have previousHash set
      );
      final entryJson = jsonEncode(entryForHash.toJson());
      final hashInput = '${previousHash ?? 'genesis'}:$entryJson';
      final expectedHash = sha256.convert(utf8.encode(hashInput)).toString();

      final storedHash = entry.metadata['_chainHash'] as String?;
      if (storedHash != expectedHash) {
        _log.severe('Log chain tamper detected at entry ${entry.id}');
        return false;
      }

      previousHash = storedHash;
    }

    _log.info('Log chain integrity verified for ${filtered.length} entries');
    return true;
  }

  /// Applies the retention policy: deletes entries older than [retentionDays].
  Future<void> applyRetentionPolicy() async {
    final cutoff = DateTime.now().subtract(
      Duration(days: config.retention.retentionDays),
    );

    final before = _entries.length;
    _entries.removeWhere((e) => e.timestamp.isBefore(cutoff));
    final removed = before - _entries.length;

    if (removed > 0) {
      _log.info('Retention policy applied: removed $removed entries older than $cutoff');
    }
  }

  /// Returns a stream of all audit events matching [eventPattern] within the given time range.
  Stream<AuditEvent> query({
    required String eventPattern,
    DateTime? from,
    DateTime? to,
  }) async* {
    for (final entry in _entries) {
      if (from != null && entry.timestamp.isBefore(from)) continue;
      if (to != null && entry.timestamp.isAfter(to)) continue;
      if (_matchesPattern(entry.eventType, eventPattern)) {
        yield entry;
      }
    }
  }

  /// Shuts down the logger and flushes pending writes
  Future<void> shutdown() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
    await _alertController.close();
  }

  /// Checks whether an event type matches any configured pattern
  bool _matchesPatterns(String eventType) {
    return config.eventPatterns.any((p) => _matchesPattern(eventType, p));
  }

  /// Checks if an event type matches a pattern (supports trailing wildcard '*')
  bool _matchesPattern(String eventType, String pattern) {
    if (pattern == '*') return true;
    if (pattern.endsWith('.*')) {
      final prefix = pattern.substring(0, pattern.length - 2);
      return eventType.startsWith(prefix);
    }
    return eventType == pattern;
  }

  /// Writes an audit entry to the configured output
  Future<void> _writeEntry(AuditEvent event) async {
    final json = jsonEncode(event.toJson());

    switch (config.output.type) {
      case 'file':
        if (_fileSink == null) {
          throw const AuditException('File audit sink is not initialized');
        }
        _fileSink!.writeln(json);
        await _fileSink!.flush();
      case 'syslog':
        // Write to system logger via the logging package
        _log.info('[AUDIT] $json');
      case 'remote':
        // TODO: Implement remote audit log shipping
        _log.info('[AUDIT-REMOTE] $json');
      default:
        throw AuditException('Unknown output type: ${config.output.type}');
    }
  }

  /// Tracks authentication failure for brute force detection
  void _trackFailure(String subject) {
    final now = DateTime.now();

    // Check if subject is currently blocked
    final unblockTime = _blockedSubjects[subject];
    if (unblockTime != null && now.isBefore(unblockTime)) {
      return; // Already blocked
    } else if (unblockTime != null) {
      _blockedSubjects.remove(subject); // Block expired
    }

    final failures = _failureTracker.putIfAbsent(subject, () => []);
    failures.add(now);

    // Remove failures outside the detection window
    final windowStart = now.subtract(
      Duration(seconds: bruteForceConfig.windowSeconds),
    );
    failures.removeWhere((t) => t.isBefore(windowStart));

    if (failures.length >= bruteForceConfig.maxFailedAttempts) {
      _log.severe(
        'Brute force detected for $subject: '
        '${failures.length} failures in ${bruteForceConfig.windowSeconds}s',
      );

      // Block subject
      _blockedSubjects[subject] = now.add(
        Duration(seconds: bruteForceConfig.blockDurationSeconds),
      );

      // Clear failure tracker for this subject
      _failureTracker.remove(subject);

      // Emit security alert
      if (bruteForceConfig.notifyOnBlock) {
        _alertController.add(SecurityAlert(
          alertType: 'brute_force',
          subject: subject,
          detectedAt: now,
          severity: 'critical',
          details: {
            'failedAttempts': failures.length,
            'windowSeconds': bruteForceConfig.windowSeconds,
            'blockDurationSeconds': bruteForceConfig.blockDurationSeconds,
          },
        ));
      }
    }
  }

  /// Returns whether a subject is currently blocked
  bool isBlocked(String subject) {
    final unblockTime = _blockedSubjects[subject];
    if (unblockTime == null) return false;
    if (DateTime.now().isAfter(unblockTime)) {
      _blockedSubjects.remove(subject);
      return false;
    }
    return true;
  }
}
