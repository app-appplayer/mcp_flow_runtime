/// MediaService - Media capture and processing abstraction for MCP Flow Runtime
///
/// MOD-SVC-008: Provides camera capture, audio playback, image processing,
/// and motion detection. All methods are abstract; the stub implementation
/// throws as hardware access requires platform-specific FFI bindings.
import 'dart:async';
import 'package:logging/logging.dart';

import 'system_service_registry.dart';

// ---------------------------------------------------------------------------
// Supporting types
// ---------------------------------------------------------------------------

/// A simple rectangle defined by left, top, width, and height.
/// Replaces dart:ui Rect which is not available in pure Dart packages.
class Rect {
  final double left;
  final double top;
  final double width;
  final double height;

  const Rect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  String toString() => 'Rect($left, $top, $width, $height)';
}

/// Result of a capture operation.
class CaptureResult {
  final String path;
  final int camera;
  final DateTime timestamp;
  final String format;
  final int sizeBytes;

  const CaptureResult({
    required this.path,
    required this.camera,
    required this.timestamp,
    required this.format,
    required this.sizeBytes,
  });
}

/// Motion detection event.
class MotionEvent {
  final int camera;
  final double intensity;
  final DateTime timestamp;
  final Rect? boundingBox;

  const MotionEvent({
    required this.camera,
    required this.intensity,
    required this.timestamp,
    this.boundingBox,
  });
}

/// Base class for image processing operations.
abstract class ImageOperation {}

/// Resize an image to the given dimensions.
class ResizeOperation extends ImageOperation {
  final int width;
  final int height;

  ResizeOperation({required this.width, required this.height});
}

/// Crop an image to the given region.
class CropOperation extends ImageOperation {
  final Rect region;

  CropOperation({required this.region});
}

/// Apply a named filter to an image.
class FilterOperation extends ImageOperation {
  final String filterName;
  final Map<String, dynamic> params;

  FilterOperation({required this.filterName, this.params = const {}});
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown by media operations.
class MediaServiceException implements Exception {
  final String serviceId = 'media';
  final String operation;
  final String message;
  final dynamic cause;
  final int? camera;

  const MediaServiceException({
    required this.operation,
    required this.message,
    this.cause,
    this.camera,
  });

  @override
  String toString() =>
      'MediaServiceException($operation): $message${camera != null ? ' [camera=$camera]' : ''}';
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Abstract media service.
abstract class MediaService extends SystemService {
  /// Captures a still image from [camera] and saves it to [path].
  Future<CaptureResult> captureImage(
    int camera, {
    String resolution = '1920x1080',
    String format = 'jpeg',
    String? path,
  });

  /// Starts a video capture from [camera] for [duration], saving to [path].
  Future<CaptureResult> captureVideo(
    int camera, {
    required String path,
    Duration? duration,
    String resolution = '1920x1080',
    int fps = 30,
  });

  /// Plays the audio file at [path].
  Future<void> playAudio(String path, {double volume = 1.0});

  /// Applies [operations] to the image at [inputPath] and saves to [outputPath].
  Future<void> processImage(
    String inputPath,
    String outputPath,
    List<ImageOperation> operations,
  );

  /// Starts motion detection on [camera]. Returns a stream of motion events.
  Stream<MotionEvent> detectMotion(
    int camera, {
    double sensitivity = 0.5,
    Duration? debounce,
  });

  /// Emits when motion is detected on any monitored camera.
  Stream<MotionEvent> get onMotionDetected;

  /// Emits when a capture operation completes.
  Stream<CaptureResult> get onCaptureComplete;
}

// ---------------------------------------------------------------------------
// Stub implementation
// ---------------------------------------------------------------------------

/// Stub media service that throws for all operations.
///
/// Real implementations require platform-specific FFI bindings:
/// - Linux: V4L2 (Video for Linux 2)
/// - macOS: AVFoundation
class StubMediaService extends MediaService {
  final Logger _log = Logger('StubMediaService');
  bool _ready = false;

  final StreamController<MotionEvent> _motionController =
      StreamController<MotionEvent>.broadcast();
  final StreamController<CaptureResult> _captureController =
      StreamController<CaptureResult>.broadcast();

  @override
  Future<void> initialize() async {
    _ready = true;
    _log.info('StubMediaService initialized (no hardware support)');
  }

  @override
  Future<void> dispose() async {
    await _motionController.close();
    await _captureController.close();
    _ready = false;
    _log.info('StubMediaService disposed');
  }

  @override
  bool get isReady => _ready;

  @override
  Future<CaptureResult> captureImage(
    int camera, {
    String resolution = '1920x1080',
    String format = 'jpeg',
    String? path,
  }) async {
    throw MediaServiceException(
      operation: 'captureImage',
      message: 'DEVICE_NOT_FOUND: No camera hardware available in stub implementation',
      camera: camera,
    );
  }

  @override
  Future<CaptureResult> captureVideo(
    int camera, {
    required String path,
    Duration? duration,
    String resolution = '1920x1080',
    int fps = 30,
  }) async {
    throw MediaServiceException(
      operation: 'captureVideo',
      message: 'DEVICE_NOT_FOUND: No camera hardware available in stub implementation',
      camera: camera,
    );
  }

  @override
  Future<void> playAudio(String path, {double volume = 1.0}) async {
    throw MediaServiceException(
      operation: 'playAudio',
      message: 'Audio playback not available in stub implementation',
    );
  }

  @override
  Future<void> processImage(
    String inputPath,
    String outputPath,
    List<ImageOperation> operations,
  ) async {
    throw MediaServiceException(
      operation: 'processImage',
      message: 'Image processing not available in stub implementation',
    );
  }

  @override
  Stream<MotionEvent> detectMotion(
    int camera, {
    double sensitivity = 0.5,
    Duration? debounce,
  }) {
    throw MediaServiceException(
      operation: 'detectMotion',
      message: 'DEVICE_NOT_FOUND: No camera hardware available in stub implementation',
      camera: camera,
    );
  }

  @override
  Stream<MotionEvent> get onMotionDetected => _motionController.stream;

  @override
  Stream<CaptureResult> get onCaptureComplete => _captureController.stream;
}

// TODO: Implement V4l2MediaService for Linux using dart:ffi + V4L2
// TODO: Implement AvfMediaService for macOS using dart:ffi + AVFoundation

// ---------------------------------------------------------------------------
// Mock implementation for testing
// ---------------------------------------------------------------------------

/// Mock media service for testing that returns dummy/placeholder data.
///
/// No real hardware or platform access is required. Recording state is
/// tracked internally for assertion in tests.
class MockMediaService extends MediaService {
  bool _ready = false;
  bool _isRecording = false;

  final StreamController<MotionEvent> _motionController =
      StreamController<MotionEvent>.broadcast();
  final StreamController<CaptureResult> _captureController =
      StreamController<CaptureResult>.broadcast();

  /// Number of images captured (for testing assertions).
  int captureCount = 0;

  /// Whether a recording is currently in progress.
  bool get isRecording => _isRecording;

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  Future<void> dispose() async {
    _isRecording = false;
    await _motionController.close();
    await _captureController.close();
    _ready = false;
  }

  @override
  bool get isReady => _ready;

  @override
  Future<CaptureResult> captureImage(
    int camera, {
    String resolution = '1920x1080',
    String format = 'jpeg',
    String? path,
  }) async {
    captureCount++;
    final result = CaptureResult(
      path: path ?? '/mock/capture_$captureCount.$format',
      camera: camera,
      timestamp: DateTime.now(),
      format: format,
      sizeBytes: 1024, // Dummy size
    );
    if (!_captureController.isClosed) {
      _captureController.add(result);
    }
    return result;
  }

  @override
  Future<CaptureResult> captureVideo(
    int camera, {
    required String path,
    Duration? duration,
    String resolution = '1920x1080',
    int fps = 30,
  }) async {
    _isRecording = true;
    // Simulate recording duration if provided
    if (duration != null) {
      await Future<void>.delayed(Duration.zero);
    }
    _isRecording = false;
    final result = CaptureResult(
      path: path,
      camera: camera,
      timestamp: DateTime.now(),
      format: 'mp4',
      sizeBytes: 4096, // Dummy size
    );
    if (!_captureController.isClosed) {
      _captureController.add(result);
    }
    return result;
  }

  @override
  Future<void> playAudio(String path, {double volume = 1.0}) async {
    // No-op in mock; audio playback is simulated.
  }

  @override
  Future<void> processImage(
    String inputPath,
    String outputPath,
    List<ImageOperation> operations,
  ) async {
    // No-op in mock; image processing is simulated.
  }

  @override
  Stream<MotionEvent> detectMotion(
    int camera, {
    double sensitivity = 0.5,
    Duration? debounce,
  }) {
    return _motionController.stream.where((event) => event.camera == camera);
  }

  @override
  Stream<MotionEvent> get onMotionDetected => _motionController.stream;

  @override
  Stream<CaptureResult> get onCaptureComplete => _captureController.stream;

  /// Injects a simulated motion event for testing.
  void simulateMotion(int camera, {double intensity = 0.8}) {
    if (!_motionController.isClosed) {
      _motionController.add(MotionEvent(
        camera: camera,
        intensity: intensity,
        timestamp: DateTime.now(),
      ));
    }
  }
}
