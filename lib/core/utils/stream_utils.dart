import 'dart:async';

/// Trailing debounce for bursty Firestore snapshot streams.
Stream<T> debounceStream<T>(
  Stream<T> source, {
  Duration duration = const Duration(milliseconds: 300),
}) {
  final controller = StreamController<T>.broadcast();
  StreamSubscription<T>? sub;
  Timer? timer;
  T? pending;
  var hasPending = false;
  var listeners = 0;

  void flush() {
    if (!hasPending || controller.isClosed) return;
    hasPending = false;
    controller.add(pending as T);
  }

  controller.onListen = () {
    listeners++;
    if (sub != null) return;
    sub = source.listen(
      (event) {
        pending = event;
        hasPending = true;
        timer?.cancel();
        timer = Timer(duration, flush);
      },
      onError: controller.addError,
      onDone: () {
        timer?.cancel();
        flush();
        if (!controller.isClosed) controller.close();
      },
    );
  };
  controller.onCancel = () async {
    listeners--;
    if (listeners > 0) return;
    timer?.cancel();
    await sub?.cancel();
    sub = null;
  };
  return controller.stream;
}

/// Merges void streams and only notifies after [duration] of quiet.
Stream<void> mergeAndDebounce(
  List<Stream<void>> streams, {
  Duration duration = const Duration(milliseconds: 300),
}) {
  final merged = StreamController<void>.broadcast();
  final subs = <StreamSubscription<void>>[];
  var listeners = 0;

  merged.onListen = () {
    listeners++;
    if (subs.isNotEmpty) return;
    for (final stream in streams) {
      subs.add(
        stream.listen(
          (_) {
            if (!merged.isClosed) merged.add(null);
          },
          onError: merged.addError,
        ),
      );
    }
  };
  merged.onCancel = () async {
    listeners--;
    if (listeners > 0) return;
    for (final sub in subs) {
      await sub.cancel();
    }
    subs.clear();
  };

  return debounceStream(merged.stream, duration: duration);
}
