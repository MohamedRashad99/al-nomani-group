import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/updates/mobile_update.dart';

enum AndroidUpdatePhase {
  idle,
  available,
  downloading,
  ready,
  failed,
  current,
}

class AndroidUpdateState {
  const AndroidUpdateState({
    this.phase = AndroidUpdatePhase.idle,
    this.offer,
    this.received = 0,
    this.total = 0,
    this.filePath,
    this.error,
    this.needsInstallPermission = false,
  });

  final AndroidUpdatePhase phase;
  final AndroidUpdateOffer? offer;
  final int received;
  final int total;
  final String? filePath;
  final String? error;
  final bool needsInstallPermission;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);

  AndroidUpdateState copyWith({
    AndroidUpdatePhase? phase,
    AndroidUpdateOffer? offer,
    int? received,
    int? total,
    String? filePath,
    String? error,
    bool? needsInstallPermission,
    bool clearError = false,
    bool clearFile = false,
  }) {
    return AndroidUpdateState(
      phase: phase ?? this.phase,
      offer: offer ?? this.offer,
      received: received ?? this.received,
      total: total ?? this.total,
      filePath: clearFile ? null : filePath ?? this.filePath,
      error: clearError ? null : error ?? this.error,
      needsInstallPermission:
          needsInstallPermission ?? this.needsInstallPermission,
    );
  }
}

class AndroidUpdateCubit extends Cubit<AndroidUpdateState> {
  AndroidUpdateCubit(this._service) : super(const AndroidUpdateState());

  final AndroidUpdateService _service;
  int? _dismissedBuild;

  Future<void> check({bool forceFetch = false}) async {
    try {
      final offer = await _service.check(forceFetch: forceFetch);
      if (isClosed) return;
      if (offer == null) {
        emit(
          AndroidUpdateState(
            phase: forceFetch
                ? AndroidUpdatePhase.current
                : AndroidUpdatePhase.idle,
          ),
        );
        return;
      }
      if (!forceFetch &&
          !offer.forceUpdate &&
          _dismissedBuild == offer.latestBuild) {
        return;
      }
      emit(AndroidUpdateState(phase: AndroidUpdatePhase.available, offer: offer));
    } catch (_) {
      if (!isClosed) emit(const AndroidUpdateState());
    }
  }

  Future<void> startDownload() async {
    final offer = state.offer;
    if (offer == null || state.phase == AndroidUpdatePhase.downloading) {
      return;
    }
    emit(
      state.copyWith(
        phase: AndroidUpdatePhase.downloading,
        received: 0,
        total: 0,
        clearError: true,
        needsInstallPermission: false,
      ),
    );
    try {
      await for (final progress in _service.download(offer)) {
        if (isClosed) return;
        emit(
          state.copyWith(
            phase: AndroidUpdatePhase.downloading,
            received: progress.received,
            total: progress.total,
          ),
        );
      }
      final path = await _service.preparedApkPath();
      if (isClosed) return;
      if (path == null) {
        emit(
          state.copyWith(
            phase: AndroidUpdatePhase.failed,
            error: 'تعذر تجهيز ملف التحديث.',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          phase: AndroidUpdatePhase.ready,
          filePath: path,
          clearError: true,
        ),
      );
      await install();
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: AndroidUpdatePhase.failed,
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> install() async {
    final path = state.filePath ?? await _service.preparedApkPath();
    if (path == null) return;
    try {
      final outcome = await _service.install(path);
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: AndroidUpdatePhase.ready,
          filePath: path,
          needsInstallPermission:
              outcome == AndroidInstallOutcome.needsPermission,
          clearError: outcome != AndroidInstallOutcome.needsPermission,
          error: outcome == AndroidInstallOutcome.needsPermission
              ? 'فعّل إذن تثبيت التطبيقات ثم اضغط تثبيت مرة أخرى.'
              : null,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: AndroidUpdatePhase.failed,
          filePath: path,
          error: error.toString(),
        ),
      );
    }
  }

  void dismiss() {
    if (state.offer?.forceUpdate == true) return;
    _dismissedBuild = state.offer?.latestBuild;
    emit(const AndroidUpdateState());
  }
}
