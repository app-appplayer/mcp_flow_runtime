import 'dart:async';

/// A debounce utility that delays function execution until after a specified
/// duration has passed since the last invocation.
class Debouncer {
  final Duration delay;
  Timer? _timer;
  bool _disposed = false;

  Debouncer({required this.delay});

  /// Whether a debounced call is pending.
  bool get isPending => _timer?.isActive ?? false;

  /// Debounces the given function. The function will only be called after
  /// [delay] has passed without any new calls. Noop after dispose().
  void call(void Function() callback) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  /// Cancels any pending debounced calls.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Disposes the debouncer and cancels any pending calls.
  /// After dispose, call() becomes a noop.
  void dispose() {
    _disposed = true;
    cancel();
  }
}

/// Creates a debounced version of a function that delays invoking the function
/// until after [delay] milliseconds have elapsed since the last time it was invoked.
typedef DebouncedFunction<T> = void Function(T arg);

DebouncedFunction<T> createDebouncedFunction<T>(
  void Function(T) fn,
  Duration delay,
) {
  final debouncer = Debouncer(delay: delay);
  return (T arg) => debouncer.call(() => fn(arg));
}