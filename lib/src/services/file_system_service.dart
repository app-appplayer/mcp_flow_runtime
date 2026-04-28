/// FileSystemService - File system abstraction for MCP Flow Runtime
///
/// MOD-SVC-003: Provides file read/write/delete, directory operations,
/// and file watch events.
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'system_service_registry.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// Write mode for file operations.
enum FileWriteMode { overwrite, append }

/// Type of file system event.
enum FileEventType { changed, created, deleted }

/// Represents a file system change event.
class FileEvent {
  final String path;
  final FileEventType type;
  final DateTime timestamp;

  const FileEvent({
    required this.path,
    required this.type,
    required this.timestamp,
  });

  @override
  String toString() => 'FileEvent($type, $path)';
}

/// Metadata about a file or directory.
class FileStat {
  final int size;
  final DateTime modified;
  final DateTime created;
  final bool isDirectory;
  final bool isFile;
  final int mode;

  const FileStat({
    required this.size,
    required this.modified,
    required this.created,
    required this.isDirectory,
    required this.isFile,
    required this.mode,
  });
}

/// An entry in a directory listing.
class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
  });
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by file system operations.
class FileSystemServiceException implements Exception {
  final String serviceId = 'filesystem';
  final String operation;
  final String message;
  final dynamic cause;
  final String? path;

  const FileSystemServiceException({
    required this.operation,
    required this.message,
    this.cause,
    this.path,
  });

  @override
  String toString() =>
      'FileSystemServiceException($operation): $message${path != null ? ' [path=$path]' : ''}';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract file system service.
abstract class FileSystemService extends SystemService {
  /// Reads the entire contents of a file at [path].
  Future<Uint8List> read(String path, {String encoding = 'utf8'});

  /// Writes [data] to the file at [path], creating it if needed.
  Future<void> write(String path, Uint8List data,
      {FileWriteMode mode = FileWriteMode.overwrite});

  /// Appends [data] to the file at [path].
  Future<void> append(String path, Uint8List data);

  /// Deletes the file at [path].
  Future<void> delete(String path);

  /// Returns true if the file or directory at [path] exists.
  Future<bool> exists(String path);

  /// Returns metadata for the file or directory at [path].
  Future<FileStat> stat(String path);

  /// Lists entries in the directory at [path], optionally filtered by [pattern].
  Future<List<FileEntry>> list(String path, {String? pattern});

  /// Creates the directory at [path] and any missing parent directories.
  Future<void> mkdir(String path, {bool recursive = true});

  /// Removes the directory at [path].
  Future<void> rmdir(String path, {bool recursive = false});

  /// Emits a [FileEvent] whenever the file or directory at [path] changes.
  Stream<FileEvent> watch(String path);
}

// ---------------------------------------------------------------------------
// Local implementation using dart:io
// ---------------------------------------------------------------------------

/// Concrete file system service backed by [dart:io].
class LocalFileSystemService extends FileSystemService {
  final Logger _log = Logger('LocalFileSystemService');
  bool _ready = false;

  @override
  Future<void> initialize() async {
    _ready = true;
    _log.info('LocalFileSystemService initialized');
  }

  @override
  Future<void> dispose() async {
    _ready = false;
    _log.info('LocalFileSystemService disposed');
  }

  @override
  bool get isReady => _ready;

  @override
  Future<Uint8List> read(String path, {String encoding = 'utf8'}) async {
    try {
      final file = io.File(path);
      return await file.readAsBytes();
    } on io.FileSystemException catch (e) {
      throw FileSystemServiceException(
        operation: 'read',
        message: e.message,
        cause: e,
        path: path,
      );
    }
  }

  @override
  Future<void> write(String path, Uint8List data,
      {FileWriteMode mode = FileWriteMode.overwrite}) async {
    try {
      final file = io.File(path);
      if (mode == FileWriteMode.append) {
        await file.writeAsBytes(data, mode: io.FileMode.append);
      } else {
        await file.writeAsBytes(data);
      }
    } on io.FileSystemException catch (e) {
      throw FileSystemServiceException(
        operation: 'write',
        message: e.message,
        cause: e,
        path: path,
      );
    }
  }

  @override
  Future<void> append(String path, Uint8List data) async {
    await write(path, data, mode: FileWriteMode.append);
  }

  @override
  Future<void> delete(String path) async {
    try {
      final file = io.File(path);
      if (await file.exists()) {
        await file.delete();
      } else {
        throw FileSystemServiceException(
          operation: 'delete',
          message: 'FILE_NOT_FOUND',
          path: path,
        );
      }
    } on FileSystemServiceException {
      rethrow;
    } on io.FileSystemException catch (e) {
      throw FileSystemServiceException(
        operation: 'delete',
        message: e.message,
        cause: e,
        path: path,
      );
    }
  }

  @override
  Future<bool> exists(String path) async {
    return io.File(path).existsSync() ||
        io.Directory(path).existsSync() ||
        io.Link(path).existsSync();
  }

  @override
  Future<FileStat> stat(String path) async {
    try {
      final ioStat = await io.FileStat.stat(path);
      if (ioStat.type == io.FileSystemEntityType.notFound) {
        throw FileSystemServiceException(
          operation: 'stat',
          message: 'FILE_NOT_FOUND',
          path: path,
        );
      }
      return FileStat(
        size: ioStat.size,
        modified: ioStat.modified,
        created: ioStat.changed,
        isDirectory: ioStat.type == io.FileSystemEntityType.directory,
        isFile: ioStat.type == io.FileSystemEntityType.file,
        mode: ioStat.mode,
      );
    } on FileSystemServiceException {
      rethrow;
    } catch (e) {
      throw FileSystemServiceException(
        operation: 'stat',
        message: e.toString(),
        cause: e,
        path: path,
      );
    }
  }

  @override
  Future<List<FileEntry>> list(String path, {String? pattern}) async {
    try {
      final dir = io.Directory(path);
      if (!await dir.exists()) {
        throw FileSystemServiceException(
          operation: 'list',
          message: 'FILE_NOT_FOUND: Directory does not exist',
          path: path,
        );
      }

      final entries = <FileEntry>[];
      await for (final entity in dir.list()) {
        final name = entity.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .lastOrNull ?? '';

        // Apply glob-style pattern filter if provided
        if (pattern != null && !_matchPattern(name, pattern)) {
          continue;
        }

        final entityStat = await entity.stat();
        entries.add(FileEntry(
          name: name,
          path: entity.path,
          isDirectory:
              entityStat.type == io.FileSystemEntityType.directory,
          size: entityStat.size,
        ));
      }
      return entries;
    } on FileSystemServiceException {
      rethrow;
    } on io.FileSystemException catch (e) {
      throw FileSystemServiceException(
        operation: 'list',
        message: e.message,
        cause: e,
        path: path,
      );
    }
  }

  @override
  Future<void> mkdir(String path, {bool recursive = true}) async {
    try {
      await io.Directory(path).create(recursive: recursive);
    } on io.FileSystemException catch (e) {
      throw FileSystemServiceException(
        operation: 'mkdir',
        message: e.message,
        cause: e,
        path: path,
      );
    }
  }

  @override
  Future<void> rmdir(String path, {bool recursive = false}) async {
    try {
      await io.Directory(path).delete(recursive: recursive);
    } on io.FileSystemException catch (e) {
      throw FileSystemServiceException(
        operation: 'rmdir',
        message: e.message,
        cause: e,
        path: path,
      );
    }
  }

  @override
  Stream<FileEvent> watch(String path) {
    final entity =
        io.FileSystemEntity.isDirectorySync(path)
            ? io.Directory(path) as io.FileSystemEntity
            : io.File(path);

    return entity.watch().map((ioEvent) {
      final FileEventType type;
      if (ioEvent.type == io.FileSystemEvent.create) {
        type = FileEventType.created;
      } else if (ioEvent.type == io.FileSystemEvent.delete) {
        type = FileEventType.deleted;
      } else {
        type = FileEventType.changed;
      }
      return FileEvent(
        path: ioEvent.path,
        type: type,
        timestamp: DateTime.now(),
      );
    });
  }

  /// Simple glob-style pattern matching supporting '*' and '?' wildcards.
  bool _matchPattern(String input, String pattern) {
    final regexStr = pattern
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$regexStr\$').hasMatch(input);
  }
}

// ---------------------------------------------------------------------------
// Mock implementation for testing
// ---------------------------------------------------------------------------

/// In-memory mock file system service for testing.
///
/// Uses a [Map] to simulate files and directories without any dart:io dependency.
class MockFileSystemService extends FileSystemService {
  bool _ready = false;

  /// In-memory file storage keyed by absolute path.
  final Map<String, Uint8List> _files = {};

  /// Set of directory paths.
  final Set<String> _directories = {};

  /// Stream controller for watch events.
  final StreamController<FileEvent> _watchController =
      StreamController<FileEvent>.broadcast();

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    _files.clear();
    _directories.clear();
    await _watchController.close();
    _ready = false;
  }

  @override
  bool get isReady => _ready;

  @override
  Future<Uint8List> read(String path, {String encoding = 'utf8'}) async {
    final data = _files[path];
    if (data == null) {
      throw FileSystemServiceException(
        operation: 'read',
        message: 'FILE_NOT_FOUND',
        path: path,
      );
    }
    return Uint8List.fromList(data);
  }

  @override
  Future<void> write(String path, Uint8List data,
      {FileWriteMode mode = FileWriteMode.overwrite}) async {
    if (mode == FileWriteMode.append) {
      final existing = _files[path];
      if (existing != null) {
        final combined = Uint8List(existing.length + data.length);
        combined.setRange(0, existing.length, existing);
        combined.setRange(existing.length, combined.length, data);
        _files[path] = combined;
      } else {
        _files[path] = Uint8List.fromList(data);
      }
    } else {
      _files[path] = Uint8List.fromList(data);
    }
    _emitEvent(path, _files.containsKey(path) ? FileEventType.changed : FileEventType.created);
  }

  @override
  Future<void> append(String path, Uint8List data) async {
    await write(path, data, mode: FileWriteMode.append);
  }

  @override
  Future<void> delete(String path) async {
    if (_files.remove(path) == null) {
      throw FileSystemServiceException(
        operation: 'delete',
        message: 'FILE_NOT_FOUND',
        path: path,
      );
    }
    _emitEvent(path, FileEventType.deleted);
  }

  @override
  Future<bool> exists(String path) async {
    return _files.containsKey(path) || _directories.contains(path);
  }

  @override
  Future<FileStat> stat(String path) async {
    final now = DateTime.now();
    if (_files.containsKey(path)) {
      return FileStat(
        size: _files[path]!.length,
        modified: now,
        created: now,
        isDirectory: false,
        isFile: true,
        mode: 0x1A4, // 0644
      );
    }
    if (_directories.contains(path)) {
      return FileStat(
        size: 0,
        modified: now,
        created: now,
        isDirectory: true,
        isFile: false,
        mode: 0x1ED, // 0755
      );
    }
    throw FileSystemServiceException(
      operation: 'stat',
      message: 'FILE_NOT_FOUND',
      path: path,
    );
  }

  @override
  Future<List<FileEntry>> list(String path, {String? pattern}) async {
    if (!_directories.contains(path)) {
      throw FileSystemServiceException(
        operation: 'list',
        message: 'FILE_NOT_FOUND: Directory does not exist',
        path: path,
      );
    }
    final prefix = path.endsWith('/') ? path : '$path/';
    final entries = <FileEntry>[];

    // Collect files under this directory (one level deep)
    for (final filePath in _files.keys) {
      if (filePath.startsWith(prefix) && !filePath.substring(prefix.length).contains('/')) {
        final name = filePath.substring(prefix.length);
        if (pattern != null && !_matchPattern(name, pattern)) continue;
        entries.add(FileEntry(
          name: name,
          path: filePath,
          isDirectory: false,
          size: _files[filePath]!.length,
        ));
      }
    }

    // Collect subdirectories (one level deep)
    for (final dirPath in _directories) {
      if (dirPath.startsWith(prefix) && dirPath != path &&
          !dirPath.substring(prefix.length).contains('/')) {
        final name = dirPath.substring(prefix.length);
        if (pattern != null && !_matchPattern(name, pattern)) continue;
        entries.add(FileEntry(
          name: name,
          path: dirPath,
          isDirectory: true,
          size: 0,
        ));
      }
    }

    return entries;
  }

  @override
  Future<void> mkdir(String path, {bool recursive = true}) async {
    if (recursive) {
      // Create all parent directories
      final parts = path.split('/');
      var current = '';
      for (final part in parts) {
        if (part.isEmpty) {
          current = '/';
          continue;
        }
        current = current.endsWith('/') ? '$current$part' : '$current/$part';
        _directories.add(current);
      }
    } else {
      _directories.add(path);
    }
  }

  @override
  Future<void> rmdir(String path, {bool recursive = false}) async {
    if (!_directories.contains(path)) {
      throw FileSystemServiceException(
        operation: 'rmdir',
        message: 'FILE_NOT_FOUND',
        path: path,
      );
    }
    if (recursive) {
      final prefix = path.endsWith('/') ? path : '$path/';
      _files.removeWhere((key, _) => key.startsWith(prefix));
      _directories.removeWhere((d) => d == path || d.startsWith(prefix));
    } else {
      _directories.remove(path);
    }
  }

  @override
  Stream<FileEvent> watch(String path) {
    return _watchController.stream.where((event) => event.path.startsWith(path));
  }

  /// Emits a file event on the watch stream.
  void _emitEvent(String path, FileEventType type) {
    if (!_watchController.isClosed) {
      _watchController.add(FileEvent(
        path: path,
        type: type,
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Simple glob-style pattern matching supporting '*' and '?' wildcards.
  bool _matchPattern(String input, String pattern) {
    final regexStr = pattern
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$regexStr\$').hasMatch(input);
  }
}
