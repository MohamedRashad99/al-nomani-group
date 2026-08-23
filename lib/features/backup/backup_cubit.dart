import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/l10n/app_strings.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../../domain/services/backup_export_service.dart';

class BackupState extends Equatable {
  final SyncHealth? health;
  final bool busy;
  final String? message;
  final bool success;
  final String? exportJson;

  const BackupState({
    this.health,
    this.busy = false,
    this.message,
    this.success = false,
    this.exportJson,
  });

  BackupState copyWith({
    SyncHealth? health,
    bool? busy,
    String? message,
    bool? success,
    String? exportJson,
  }) {
    return BackupState(
      health: health ?? this.health,
      busy: busy ?? this.busy,
      message: message,
      success: success ?? false,
      exportJson: exportJson ?? this.exportJson,
    );
  }

  @override
  List<Object?> get props => [health, busy, message, success, exportJson];
}

class BackupCubit extends Cubit<BackupState> {
  BackupCubit(this._engine, this._queue, this._exporter)
    : super(const BackupState());

  final SyncEngine _engine;
  final SyncQueueRepository _queue;
  final BackupExportService _exporter;

  void _emitIfOpen(BackupState next) {
    if (!isClosed) emit(next);
  }

  Future<void> refresh() async {
    _emitIfOpen(state.copyWith(busy: true, message: null));
    final health = await _engine.health();
    _emitIfOpen(state.copyWith(busy: false, health: health, message: null));
  }

  Future<void> syncNow() async {
    _emitIfOpen(state.copyWith(busy: true, message: null, success: false));
    await _engine.syncNow(force: true);
    if (isClosed) return;
    _emitIfOpen(await _resultState());
  }

  Future<void> fullBackup() async {
    _emitIfOpen(state.copyWith(busy: true, message: null, success: false));
    await _engine.syncNow(force: true);
    if (isClosed) return;
    _emitIfOpen(await _resultState());
  }

  Future<void> retryFailed() async {
    _emitIfOpen(state.copyWith(busy: true, message: null, success: false));
    await _queue.retryFailed();
    await _engine.syncNow(force: true);
    if (isClosed) return;
    _emitIfOpen(await _resultState());
  }

  Future<void> exportLocal() async {
    _emitIfOpen(state.copyWith(busy: true, message: null, success: false));
    final json = await _exporter.exportJson();
    _emitIfOpen(
      state.copyWith(
        busy: false,
        exportJson: json,
        success: true,
        message: 'تم تجهيز النسخة الاحتياطية المحلية.',
      ),
    );
  }

  Future<BackupState> _resultState() async {
    final health = await _engine.health();
    final failed = health.failed > 0 || health.backupFailed > 0;
    return state.copyWith(
      busy: false,
      health: health,
      success: !failed,
      message: failed
          ? health.backupLastError ??
                health.lastError ??
                'اكتملت المحاولة مع أخطاء.'
          : S.syncSuccess,
    );
  }
}
