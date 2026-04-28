/// Log rotation functionality for MCP Flow Runtime
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

/// Log rotation configuration
class LogRotationConfig {
  /// Maximum size per log file in bytes
  final int maxFileSize;
  
  /// Maximum number of backup files to keep
  final int maxBackupFiles;
  
  /// Whether to compress rotated files
  final bool compressRotated;
  
  /// Log file path
  final String logFilePath;
  
  /// Rotation check interval
  final Duration checkInterval;
  
  const LogRotationConfig({
    this.maxFileSize = 10 * 1024 * 1024, // 10MB default
    this.maxBackupFiles = 10,
    this.compressRotated = true,
    required this.logFilePath,
    this.checkInterval = const Duration(minutes: 5),
  });
}

/// Log rotator implementation
class LogRotator {
  final Logger _logger = Logger('LogRotator');
  final LogRotationConfig config;
  final IOSink _logSink;
  Timer? _checkTimer;
  bool _isRotating = false;
  
  LogRotator({
    required this.config,
    required IOSink logSink,
  }) : _logSink = logSink;
  
  /// Start log rotation monitoring
  void start() {
    _checkTimer = Timer.periodic(config.checkInterval, (_) => _checkRotation());
    _logger.info('Started log rotation with ${config.checkInterval} check interval');
  }
  
  /// Stop log rotation monitoring
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _logger.info('Stopped log rotation');
  }
  
  /// Check if rotation is needed
  Future<void> _checkRotation() async {
    if (_isRotating) return;
    
    try {
      final logFile = File(config.logFilePath);
      if (!await logFile.exists()) return;
      
      final fileSize = await logFile.length();
      if (fileSize >= config.maxFileSize) {
        await _rotateLog();
      }
    } catch (e) {
      _logger.warning('Error checking log rotation: $e');
    }
  }
  
  /// Rotate the log file
  Future<void> _rotateLog() async {
    _isRotating = true;
    
    try {
      _logger.info('Starting log rotation');
      
      // Close current log file
      await _logSink.flush();
      await _logSink.close();
      
      // Rename existing log files
      await _renameBackupFiles();
      
      // Move current log to .1
      final currentLog = File(config.logFilePath);
      final backup1 = File('${config.logFilePath}.1');
      
      if (await currentLog.exists()) {
        await currentLog.rename(backup1.path);
        
        // Compress if configured
        if (config.compressRotated) {
          await _compressFile(backup1);
        }
      }
      
      // Clean up old files
      await _cleanupOldFiles();
      
      _logger.info('Log rotation completed');
    } catch (e) {
      _logger.severe('Error during log rotation: $e');
    } finally {
      _isRotating = false;
    }
  }
  
  /// Rename backup files (shift numbers)
  Future<void> _renameBackupFiles() async {
    // Start from the highest number and work backwards
    for (int i = config.maxBackupFiles - 1; i >= 1; i--) {
      final ext = config.compressRotated ? '.gz' : '';
      final oldFile = File('${config.logFilePath}.$i$ext');
      final newFile = File('${config.logFilePath}.${i + 1}$ext');
      
      if (await oldFile.exists()) {
        if (i + 1 <= config.maxBackupFiles) {
          await oldFile.rename(newFile.path);
        } else {
          // Delete files beyond maxBackupFiles
          await oldFile.delete();
        }
      }
    }
  }
  
  /// Compress a file using gzip
  Future<void> _compressFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final compressed = gzip.encode(bytes);
      
      final compressedFile = File('${file.path}.gz');
      await compressedFile.writeAsBytes(compressed);
      await file.delete();
    } catch (e) {
      _logger.warning('Failed to compress log file: $e');
    }
  }
  
  /// Clean up files beyond maxBackupFiles
  Future<void> _cleanupOldFiles() async {
    final dir = Directory(path.dirname(config.logFilePath));
    final baseName = path.basename(config.logFilePath);
    
    if (!await dir.exists()) return;
    
    final files = await dir.list().toList();
    final logFiles = files
        .whereType<File>()
        .where((f) => path.basename(f.path).startsWith(baseName))
        .toList();
    
    // Sort by modification time
    logFiles.sort((a, b) {
      final aTime = a.statSync().modified;
      final bTime = b.statSync().modified;
      return bTime.compareTo(aTime);
    });
    
    // Keep only the most recent files
    final totalAllowed = config.maxBackupFiles + 1; // +1 for current log
    if (logFiles.length > totalAllowed) {
      for (int i = totalAllowed; i < logFiles.length; i++) {
        try {
          await logFiles[i].delete();
          _logger.fine('Deleted old log file: ${logFiles[i].path}');
        } catch (e) {
          _logger.warning('Failed to delete old log file: $e');
        }
      }
    }
  }
  
  /// Force rotation immediately
  Future<void> forceRotate() async {
    await _rotateLog();
  }
  
  /// Get list of all log files
  Future<List<FileInfo>> getLogFiles() async {
    final dir = Directory(path.dirname(config.logFilePath));
    final baseName = path.basename(config.logFilePath);
    final files = <FileInfo>[];
    
    if (!await dir.exists()) return files;
    
    final entries = await dir.list().toList();
    for (final entry in entries) {
      if (entry is File && path.basename(entry.path).startsWith(baseName)) {
        final stat = await entry.stat();
        files.add(FileInfo(
          path: entry.path,
          size: stat.size,
          modified: stat.modified,
          isCompressed: entry.path.endsWith('.gz'),
        ));
      }
    }
    
    // Sort by modification time (newest first)
    files.sort((a, b) => b.modified.compareTo(a.modified));
    
    return files;
  }
}

/// File information
class FileInfo {
  final String path;
  final int size;
  final DateTime modified;
  final bool isCompressed;
  
  FileInfo({
    required this.path,
    required this.size,
    required this.modified,
    required this.isCompressed,
  });
  
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Rotating file sink for logging
class RotatingFileSink implements IOSink {
  final LogRotationConfig config;
  final LogRotator rotator;
  IOSink? _currentSink;
  File? _currentFile;
  
  factory RotatingFileSink(LogRotationConfig config) {
    final file = File(config.logFilePath);
    final sink = file.openWrite(mode: FileMode.append);
    
    final rotator = LogRotator(
      config: config,
      logSink: sink,
    );
    
    return RotatingFileSink._(
      config: config,
      rotator: rotator,
      currentSink: sink,
      currentFile: file,
    );
  }
  
  RotatingFileSink._({
    required this.config,
    required this.rotator,
    required IOSink currentSink,
    required File currentFile,
  }) : _currentSink = currentSink,
       _currentFile = currentFile {
    rotator.start();
  }
  
  @override
  Encoding get encoding => _currentSink!.encoding;
  
  @override
  set encoding(Encoding encoding) {
    _currentSink!.encoding = encoding;
  }
  
  @override
  void add(List<int> data) {
    _ensureSink();
    _currentSink!.add(data);
  }
  
  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _ensureSink();
    _currentSink!.addError(error, stackTrace);
  }
  
  @override
  Future<dynamic> addStream(Stream<List<int>> stream) {
    _ensureSink();
    return _currentSink!.addStream(stream);
  }
  
  @override
  Future<dynamic> close() async {
    rotator.stop();
    return _currentSink?.close();
  }
  
  @override
  Future<dynamic> get done => _currentSink?.done ?? Future.value();
  
  @override
  Future<dynamic> flush() {
    return _currentSink?.flush() ?? Future.value();
  }
  
  @override
  void write(Object? object) {
    _ensureSink();
    _currentSink!.write(object);
  }
  
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = ""]) {
    _ensureSink();
    _currentSink!.writeAll(objects, separator);
  }
  
  @override
  void writeCharCode(int charCode) {
    _ensureSink();
    _currentSink!.writeCharCode(charCode);
  }
  
  @override
  void writeln([Object? object = ""]) {
    _ensureSink();
    _currentSink!.writeln(object);
  }
  
  void _ensureSink() {
    if (_currentSink == null) {
      _currentFile = File(config.logFilePath);
      _currentSink = _currentFile!.openWrite(mode: FileMode.append);
    }
  }
}