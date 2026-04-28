/// MemoryService - Memory management abstraction for MCP Flow Runtime
///
/// MOD-SVC-006: Provides heap allocation/free, shared memory, and memory-mapped
/// file abstractions. The default implementation uses Dart-level tracking;
/// POSIX shared memory and mmap require FFI and are stubbed.
import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'system_service_registry.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// Handle to an allocated memory region.
class MemoryHandle {
  final int id;
  final int size;

  const MemoryHandle({required this.id, required this.size});

  @override
  String toString() => 'MemoryHandle(id=$id, size=$size)';
}

/// Handle to a POSIX shared memory segment.
class SharedMemoryHandle extends MemoryHandle {
  final String name;
  final int fd;

  const SharedMemoryHandle({
    required super.id,
    required super.size,
    required this.name,
    required this.fd,
  });

  @override
  String toString() => 'SharedMemoryHandle(name=$name, id=$id, size=$size)';
}

/// Handle to a memory-mapped file region.
class MappedFileHandle extends MemoryHandle {
  final String filePath;
  final String mode;

  const MappedFileHandle({
    required super.id,
    required super.size,
    required this.filePath,
    required this.mode,
  });

  @override
  String toString() =>
      'MappedFileHandle(file=$filePath, id=$id, size=$size, mode=$mode)';
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by memory operations.
class MemoryServiceException implements Exception {
  final String serviceId = 'memory';
  final String operation;
  final String message;
  final dynamic cause;
  final int? requestedSize;

  const MemoryServiceException({
    required this.operation,
    required this.message,
    this.cause,
    this.requestedSize,
  });

  @override
  String toString() => 'MemoryServiceException($operation): $message';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract memory service.
abstract class MemoryService extends SystemService {
  /// Allocates [size] bytes on the heap. Returns a handle.
  Future<MemoryHandle> allocate(int size);

  /// Frees the memory referenced by [handle].
  Future<void> free(MemoryHandle handle);

  /// Reads [length] bytes from [handle] at [offset].
  Future<Uint8List> read(MemoryHandle handle, {int offset = 0, int? length});

  /// Writes [data] to [handle] at [offset].
  Future<void> write(MemoryHandle handle, Uint8List data, {int offset = 0});

  /// Creates a named POSIX shared memory segment of [size] bytes.
  Future<SharedMemoryHandle> sharedCreate(
    String name,
    int size, {
    String permissions = 'rw',
  });

  /// Attaches to an existing named shared memory segment.
  Future<SharedMemoryHandle> sharedAttach(String name);

  /// Detaches from the shared memory segment, releasing the mapping.
  Future<void> sharedDetach(SharedMemoryHandle handle);

  /// Maps [length] bytes of [filePath] starting at [offset] into memory.
  Future<MappedFileHandle> mapFile(
    String filePath, {
    String mode = 'readonly',
    int offset = 0,
    int? length,
  });
}

// ---------------------------------------------------------------------------
// Dart-level implementation (no FFI)
// ---------------------------------------------------------------------------

/// Memory service using Dart-level byte buffers for heap allocation.
/// Shared memory and memory-mapped files are stubbed as they require FFI.
class DartMemoryService extends MemoryService {
  final Logger _log = Logger('DartMemoryService');
  bool _ready = false;

  int _nextId = 1;
  final Map<int, Uint8List> _buffers = {};

  @override
  Future<void> initialize() async {
    _ready = true;
    _log.info('DartMemoryService initialized');
  }

  @override
  Future<void> dispose() async {
    _buffers.clear();
    _ready = false;
    _log.info('DartMemoryService disposed');
  }

  @override
  bool get isReady => _ready;

  @override
  Future<MemoryHandle> allocate(int size) async {
    if (size <= 0) {
      throw MemoryServiceException(
        operation: 'allocate',
        message: 'Size must be positive',
        requestedSize: size,
      );
    }
    try {
      final id = _nextId++;
      _buffers[id] = Uint8List(size);
      _log.fine('Allocated $size bytes with handle $id');
      return MemoryHandle(id: id, size: size);
    } catch (e) {
      throw MemoryServiceException(
        operation: 'allocate',
        message: 'OUT_OF_MEMORY',
        cause: e,
        requestedSize: size,
      );
    }
  }

  @override
  Future<void> free(MemoryHandle handle) async {
    if (_buffers.remove(handle.id) == null) {
      throw MemoryServiceException(
        operation: 'free',
        message: 'Invalid handle: ${handle.id}',
      );
    }
    _log.fine('Freed handle ${handle.id}');
  }

  @override
  Future<Uint8List> read(MemoryHandle handle,
      {int offset = 0, int? length}) async {
    final buffer = _buffers[handle.id];
    if (buffer == null) {
      throw MemoryServiceException(
        operation: 'read',
        message: 'Invalid handle: ${handle.id}',
      );
    }
    final end = offset + (length ?? (buffer.length - offset));
    if (offset < 0 || end > buffer.length) {
      throw MemoryServiceException(
        operation: 'read',
        message: 'Out of bounds: offset=$offset, length=$length, bufferSize=${buffer.length}',
      );
    }
    return Uint8List.fromList(buffer.sublist(offset, end));
  }

  @override
  Future<void> write(MemoryHandle handle, Uint8List data,
      {int offset = 0}) async {
    final buffer = _buffers[handle.id];
    if (buffer == null) {
      throw MemoryServiceException(
        operation: 'write',
        message: 'Invalid handle: ${handle.id}',
      );
    }
    if (offset < 0 || offset + data.length > buffer.length) {
      throw MemoryServiceException(
        operation: 'write',
        message: 'Out of bounds: offset=$offset, dataLength=${data.length}, bufferSize=${buffer.length}',
      );
    }
    buffer.setRange(offset, offset + data.length, data);
  }

  @override
  Future<SharedMemoryHandle> sharedCreate(
    String name,
    int size, {
    String permissions = 'rw',
  }) async {
    // TODO: Implement using dart:ffi with POSIX shm_open / mmap
    throw MemoryServiceException(
      operation: 'sharedCreate',
      message: 'Shared memory requires FFI (not implemented in DartMemoryService)',
      requestedSize: size,
    );
  }

  @override
  Future<SharedMemoryHandle> sharedAttach(String name) async {
    // TODO: Implement using dart:ffi with POSIX shm_open / mmap
    throw MemoryServiceException(
      operation: 'sharedAttach',
      message: 'Shared memory requires FFI (not implemented in DartMemoryService)',
    );
  }

  @override
  Future<void> sharedDetach(SharedMemoryHandle handle) async {
    // TODO: Implement using dart:ffi with munmap / close
    throw MemoryServiceException(
      operation: 'sharedDetach',
      message: 'Shared memory requires FFI (not implemented in DartMemoryService)',
    );
  }

  @override
  Future<MappedFileHandle> mapFile(
    String filePath, {
    String mode = 'readonly',
    int offset = 0,
    int? length,
  }) async {
    // TODO: Implement using dart:ffi with mmap
    throw MemoryServiceException(
      operation: 'mapFile',
      message: 'Memory-mapped files require FFI (not implemented in DartMemoryService)',
    );
  }
}

// ---------------------------------------------------------------------------
// Mock implementation for testing
// ---------------------------------------------------------------------------

/// In-memory mock memory service for testing.
///
/// All operations (heap, shared memory, mapped files) work with pure Dart
/// memory. Shared memory is simulated using a static [Map] so that multiple
/// [MockMemoryService] instances can share named segments.
class MockMemoryService extends MemoryService {
  bool _ready = false;

  int _nextId = 1;

  /// Heap buffers keyed by handle id.
  final Map<int, Uint8List> _buffers = {};

  /// Static shared memory segments keyed by name, allowing cross-instance sharing.
  static final Map<String, _SharedSegment> _sharedSegments = {};

  /// Mapped file regions keyed by handle id.
  final Map<int, Uint8List> _mappedFiles = {};

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    _buffers.clear();
    _mappedFiles.clear();
    _ready = false;
  }

  @override
  bool get isReady => _ready;

  @override
  Future<MemoryHandle> allocate(int size) async {
    if (size <= 0) {
      throw MemoryServiceException(
        operation: 'allocate',
        message: 'Size must be positive',
        requestedSize: size,
      );
    }
    final id = _nextId++;
    _buffers[id] = Uint8List(size);
    return MemoryHandle(id: id, size: size);
  }

  @override
  Future<void> free(MemoryHandle handle) async {
    if (_buffers.remove(handle.id) == null) {
      throw MemoryServiceException(
        operation: 'free',
        message: 'Invalid handle: ${handle.id}',
      );
    }
  }

  @override
  Future<Uint8List> read(MemoryHandle handle,
      {int offset = 0, int? length}) async {
    final buffer = _resolveBuffer(handle);
    final end = offset + (length ?? (buffer.length - offset));
    if (offset < 0 || end > buffer.length) {
      throw MemoryServiceException(
        operation: 'read',
        message: 'Out of bounds: offset=$offset, length=$length, bufferSize=${buffer.length}',
      );
    }
    return Uint8List.fromList(buffer.sublist(offset, end));
  }

  @override
  Future<void> write(MemoryHandle handle, Uint8List data,
      {int offset = 0}) async {
    final buffer = _resolveBuffer(handle);
    if (offset < 0 || offset + data.length > buffer.length) {
      throw MemoryServiceException(
        operation: 'write',
        message: 'Out of bounds: offset=$offset, dataLength=${data.length}, bufferSize=${buffer.length}',
      );
    }
    buffer.setRange(offset, offset + data.length, data);
  }

  @override
  Future<SharedMemoryHandle> sharedCreate(
    String name,
    int size, {
    String permissions = 'rw',
  }) async {
    if (size <= 0) {
      throw MemoryServiceException(
        operation: 'sharedCreate',
        message: 'Size must be positive',
        requestedSize: size,
      );
    }
    final id = _nextId++;
    final buffer = Uint8List(size);
    _sharedSegments[name] = _SharedSegment(id: id, buffer: buffer);
    return SharedMemoryHandle(id: id, size: size, name: name, fd: id);
  }

  @override
  Future<SharedMemoryHandle> sharedAttach(String name) async {
    final segment = _sharedSegments[name];
    if (segment == null) {
      throw MemoryServiceException(
        operation: 'sharedAttach',
        message: 'Shared segment not found: $name',
      );
    }
    return SharedMemoryHandle(
      id: segment.id,
      size: segment.buffer.length,
      name: name,
      fd: segment.id,
    );
  }

  @override
  Future<void> sharedDetach(SharedMemoryHandle handle) async {
    // In mock, detach is a no-op (segment remains accessible by name).
  }

  @override
  Future<MappedFileHandle> mapFile(
    String filePath, {
    String mode = 'readonly',
    int offset = 0,
    int? length,
  }) async {
    final size = length ?? 4096;
    final id = _nextId++;
    _mappedFiles[id] = Uint8List(size);
    return MappedFileHandle(
      id: id,
      size: size,
      filePath: filePath,
      mode: mode,
    );
  }

  /// Resolves the backing buffer for a given handle.
  Uint8List _resolveBuffer(MemoryHandle handle) {
    // Check heap buffers
    final heapBuf = _buffers[handle.id];
    if (heapBuf != null) return heapBuf;

    // Check shared segments
    if (handle is SharedMemoryHandle) {
      final segment = _sharedSegments[handle.name];
      if (segment != null) return segment.buffer;
    }

    // Check mapped files
    final mappedBuf = _mappedFiles[handle.id];
    if (mappedBuf != null) return mappedBuf;

    throw MemoryServiceException(
      operation: 'read/write',
      message: 'Invalid handle: ${handle.id}',
    );
  }

  /// Clears all static shared segments. Useful in test teardown.
  static void resetSharedSegments() {
    _sharedSegments.clear();
  }
}

/// Internal shared memory segment data.
class _SharedSegment {
  final int id;
  final Uint8List buffer;

  const _SharedSegment({required this.id, required this.buffer});
}
