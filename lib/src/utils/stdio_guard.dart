import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';

/// Guards stdio streams to prevent conflicts by always isolating process execution
class StdioGuard {
  static final Logger _logger = Logger('StdioGuard');
  
  /// Always mark stdio as in use to ensure process isolation
  static bool get isStdioInUse => true;
  
  /// Deprecated - stdio is always protected
  static void markStdioInUse() {
    _logger.fine('Stdio protection is always enabled');
  }
  
  /// Deprecated - stdio is always protected
  static void markStdioAvailable() {
    _logger.fine('Stdio protection is always enabled');
  }
  
  
  /// Always run process with output capture to prevent stdio conflicts
  static Future<ProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) async {
    _logger.info('Running process isolated: $executable ${arguments.join(" ")}');
    
    // Always run process with output captured to avoid stdio conflicts
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
    );
    
    // Capture output to logger instead of stdout/stderr
    final stdoutData = <int>[];
    final stderrData = <int>[];
    
    final stdoutSub = process.stdout.listen((data) {
      stdoutData.addAll(data);
      final line = String.fromCharCodes(data).trim();
      if (line.isNotEmpty) {
        _logger.fine('[Process STDOUT] $line');
      }
    });
    
    final stderrSub = process.stderr.listen((data) {
      stderrData.addAll(data);
      final line = String.fromCharCodes(data).trim();
      if (line.isNotEmpty) {
        _logger.warning('[Process STDERR] $line');
      }
    });
    
    final exitCode = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();
    
    return ProcessResult(
      process.pid,
      exitCode,
      stdoutEncoding?.decode(stdoutData) ?? stdoutData,
      stderrEncoding?.decode(stderrData) ?? stderrData,
    );
  }

  /// Run a process and stream its stdout output line by line
  static Stream<String> runProcessStream(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
  }) {
    final controller = StreamController<String>();

    () async {
      try {
        _logger.info('Streaming process: $executable ${arguments.join(" ")}');

        final process = await Process.start(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          includeParentEnvironment: includeParentEnvironment,
          runInShell: runInShell,
        );

        // Stream stdout lines to the controller
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            controller.add(line);
          },
          onError: (Object error) {
            controller.addError(error);
          },
        );

        // Log stderr lines
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (line.isNotEmpty) {
            _logger.warning('[Process STDERR] $line');
          }
        });

        // Close the controller when the process exits
        final exitCode = await process.exitCode;
        if (exitCode != 0) {
          _logger.warning('Process exited with code $exitCode');
        }
        await controller.close();
      } catch (e) {
        controller.addError(e);
        await controller.close();
      }
    }();

    return controller.stream;
  }
}