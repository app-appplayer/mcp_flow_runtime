/// Backup and restore functionality for MCP Flow Runtime
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import '../types/flow_types.dart';
import '../errors/flow_errors.dart';

/// Backup metadata
class BackupMetadata {
  final String id;
  final DateTime timestamp;
  final String version;
  final String? description;
  final Map<String, dynamic>? tags;
  final String? checksum;
  final int? size;
  
  BackupMetadata({
    required this.id,
    required this.timestamp,
    required this.version,
    this.description,
    this.tags,
    this.checksum,
    this.size,
  });
  
  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as String,
      description: json['description'] as String?,
      tags: json['tags'] as Map<String, dynamic>?,
      checksum: json['checksum'] as String?,
      size: json['size'] as int?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'version': version,
    if (description != null) 'description': description,
    if (tags != null) 'tags': tags,
    if (checksum != null) 'checksum': checksum,
    if (size != null) 'size': size,
  };
}

/// Backup content
class BackupContent {
  final BackupMetadata metadata;
  final FlowDefinition flow;
  final Map<String, dynamic>? state;
  final Map<String, dynamic>? runtimeConfig;
  
  BackupContent({
    required this.metadata,
    required this.flow,
    this.state,
    this.runtimeConfig,
  });
  
  factory BackupContent.fromJson(Map<String, dynamic> json) {
    return BackupContent(
      metadata: BackupMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      flow: FlowDefinition.fromJson(json['flow'] as Map<String, dynamic>),
      state: json['state'] as Map<String, dynamic>?,
      runtimeConfig: json['runtimeConfig'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'flow': flow.toJson(),
    if (state != null) 'state': state,
    if (runtimeConfig != null) 'runtimeConfig': runtimeConfig,
  };
}

/// Backup manager for handling configuration backups
class BackupManager {
  final Logger _logger = Logger('BackupManager');
  final String backupDirectory;
  final int maxBackups;
  final bool compressBackups;
  
  BackupManager({
    required this.backupDirectory,
    this.maxBackups = 10,
    this.compressBackups = false,
  });
  
  /// Create a backup of the current configuration
  Future<BackupMetadata> createBackup({
    required FlowDefinition flow,
    Map<String, dynamic>? state,
    Map<String, dynamic>? runtimeConfig,
    String? description,
    Map<String, dynamic>? tags,
  }) async {
    try {
      // Ensure backup directory exists
      final dir = Directory(backupDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // Generate backup ID and metadata
      final id = _generateBackupId();
      final metadata = BackupMetadata(
        id: id,
        timestamp: DateTime.now(),
        version: flow.version,
        description: description,
        tags: tags,
      );
      
      // Create backup content
      final content = BackupContent(
        metadata: metadata,
        flow: flow,
        state: state,
        runtimeConfig: runtimeConfig,
      );
      
      // Serialize to JSON
      final jsonStr = const JsonEncoder.withIndent('  ').convert(content.toJson());
      final jsonBytes = utf8.encode(jsonStr);
      
      // Calculate checksum
      final checksum = sha256.convert(jsonBytes).toString();
      
      // Update metadata with checksum and size
      final updatedMetadata = BackupMetadata(
        id: metadata.id,
        timestamp: metadata.timestamp,
        version: metadata.version,
        description: metadata.description,
        tags: metadata.tags,
        checksum: checksum,
        size: jsonBytes.length,
      );
      
      // Update content with new metadata
      final finalContent = BackupContent(
        metadata: updatedMetadata,
        flow: content.flow,
        state: content.state,
        runtimeConfig: content.runtimeConfig,
      );
      
      // Write backup file
      final filename = 'backup_${id}.json${compressBackups ? '.gz' : ''}';
      final filePath = path.join(backupDirectory, filename);
      final file = File(filePath);
      
      if (compressBackups) {
        // Compress using gzip
        final compressed = gzip.encode(jsonBytes);
        await file.writeAsBytes(compressed);
      } else {
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(finalContent.toJson()));
      }
      
      _logger.info('Created backup: $filename (${jsonBytes.length} bytes)');
      
      // Clean up old backups if needed
      await _cleanupOldBackups();
      
      return updatedMetadata;
    } catch (e, stackTrace) {
      _logger.severe('Failed to create backup', e, stackTrace);
      throw ConcreteFlowError('BACKUP_ERROR', 'Backup creation failed: $e');
    }
  }
  
  /// List available backups
  Future<List<BackupMetadata>> listBackups() async {
    try {
      final dir = Directory(backupDirectory);
      if (!await dir.exists()) {
        return [];
      }
      
      final backups = <BackupMetadata>[];
      final files = await dir.list().where((entity) => 
        entity is File && 
        path.basename(entity.path).startsWith('backup_') &&
        (path.basename(entity.path).endsWith('.json') || 
         path.basename(entity.path).endsWith('.json.gz'))
      ).toList();
      
      for (final file in files) {
        try {
          final metadata = await _readBackupMetadata(file as File);
          if (metadata != null) {
            backups.add(metadata);
          }
        } catch (e) {
          _logger.warning('Failed to read backup metadata from ${file.path}', e);
        }
      }
      
      // Sort by timestamp (newest first)
      backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      return backups;
    } catch (e, stackTrace) {
      _logger.severe('Failed to list backups', e, stackTrace);
      throw ConcreteFlowError('BACKUP_ERROR', 'Failed to list backups: $e');
    }
  }
  
  /// Restore from a backup
  Future<BackupContent> restoreBackup(String backupId) async {
    try {
      final filename = await _findBackupFile(backupId);
      if (filename == null) {
        throw ConcreteFlowError('BACKUP_ERROR', 'Backup not found: $backupId');
      }

      final filePath = path.join(backupDirectory, filename);
      final file = File(filePath);

      if (!await file.exists()) {
        throw ConcreteFlowError('BACKUP_ERROR', 'Backup file not found: $filename');
      }

      // Read and decompress if needed
      late final String jsonStr;
      if (filename.endsWith('.gz')) {
        final compressed = await file.readAsBytes();
        final decompressed = gzip.decode(compressed);
        jsonStr = utf8.decode(decompressed);
      } else {
        jsonStr = await file.readAsString();
      }
      
      // Parse JSON
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final content = BackupContent.fromJson(json);
      
      // Verify checksum if present
      if (content.metadata.checksum != null) {
        final jsonBytes = utf8.encode(jsonStr);
        final actualChecksum = sha256.convert(jsonBytes).toString();
        if (actualChecksum != content.metadata.checksum) {
          _logger.warning('Backup checksum mismatch for $backupId');
        }
      }
      
      _logger.info('Restored backup: $backupId');
      return content;
    } on FlowError {
      rethrow;
    } catch (e, stackTrace) {
      _logger.severe('Failed to restore backup: $backupId', e, stackTrace);
      throw ConcreteFlowError('BACKUP_ERROR', 'Backup restoration failed: $e');
    }
  }
  
  /// Delete a backup
  Future<void> deleteBackup(String backupId) async {
    try {
      final filename = await _findBackupFile(backupId);
      if (filename == null) {
        throw ConcreteFlowError('BACKUP_ERROR', 'Backup not found: $backupId');
      }

      final filePath = path.join(backupDirectory, filename);
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        _logger.info('Deleted backup: $backupId');
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to delete backup: $backupId', e, stackTrace);
      throw ConcreteFlowError('BACKUP_ERROR', 'Backup deletion failed: $e');
    }
  }
  
  /// Export backup to a different location
  Future<void> exportBackup(String backupId, String exportPath) async {
    try {
      final filename = await _findBackupFile(backupId);
      if (filename == null) {
        throw ConcreteFlowError('BACKUP_ERROR', 'Backup not found: $backupId');
      }

      final sourcePath = path.join(backupDirectory, filename);
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        throw ConcreteFlowError('BACKUP_ERROR', 'Backup file not found: $filename');
      }

      await sourceFile.copy(exportPath);
      _logger.info('Exported backup $backupId to $exportPath');
    } catch (e, stackTrace) {
      _logger.severe('Failed to export backup: $backupId', e, stackTrace);
      throw ConcreteFlowError('BACKUP_ERROR', 'Backup export failed: $e');
    }
  }
  
  /// Import backup from an external file
  Future<BackupMetadata> importBackup(String importPath) async {
    try {
      final sourceFile = File(importPath);
      
      if (!await sourceFile.exists()) {
        throw ConcreteFlowError('BACKUP_ERROR', 'Import file not found: $importPath');
      }

      // Read and validate the backup
      final metadata = await _readBackupMetadata(sourceFile);
      if (metadata == null) {
        throw ConcreteFlowError('BACKUP_ERROR', 'Invalid backup file: $importPath');
      }
      
      // Copy to backup directory with proper naming
      final filename = 'backup_${metadata.id}.json${compressBackups ? '.gz' : ''}';
      final destPath = path.join(backupDirectory, filename);
      
      await sourceFile.copy(destPath);
      _logger.info('Imported backup: ${metadata.id}');
      
      return metadata;
    } catch (e, stackTrace) {
      _logger.severe('Failed to import backup from: $importPath', e, stackTrace);
      throw ConcreteFlowError('BACKUP_ERROR', 'Backup import failed: $e');
    }
  }
  
  // Private helper methods
  
  String _generateBackupId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return '${timestamp}_$random';
  }
  
  Future<String?> _findBackupFile(String backupId) async {
    final dir = Directory(backupDirectory);
    if (!await dir.exists()) {
      return null;
    }
    
    final files = await dir.list().where((entity) => 
      entity is File && 
      path.basename(entity.path).contains('backup_$backupId')
    ).toList();
    
    if (files.isEmpty) {
      return null;
    }
    
    return path.basename(files.first.path);
  }
  
  Future<BackupMetadata?> _readBackupMetadata(File file) async {
    try {
      late final String jsonStr;
      if (file.path.endsWith('.gz')) {
        final compressed = await file.readAsBytes();
        final decompressed = gzip.decode(compressed);
        jsonStr = utf8.decode(decompressed);
      } else {
        jsonStr = await file.readAsString();
      }
      
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final metadata = json['metadata'] as Map<String, dynamic>?;
      
      if (metadata != null) {
        return BackupMetadata.fromJson(metadata);
      }
    } catch (e) {
      _logger.fine('Failed to read metadata from ${file.path}', e);
    }
    
    return null;
  }
  
  Future<void> _cleanupOldBackups() async {
    if (maxBackups <= 0) return;
    
    final backups = await listBackups();
    if (backups.length <= maxBackups) return;
    
    // Delete oldest backups
    final toDelete = backups.skip(maxBackups).toList();
    for (final backup in toDelete) {
      try {
        await deleteBackup(backup.id);
      } catch (e) {
        _logger.warning('Failed to cleanup old backup: ${backup.id}', e);
      }
    }
  }
}