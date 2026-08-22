import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../../domain/services/backup_export_service.dart';

class BackupState extends Equatable {
  final SyncHealth? health;
  final bool busy;
  final String? message;
  final String? exportJson;

  const BackupState({
    this.health,
    this.busy = false,
    this.message,
    this.exportJson,
  });

  BackupState copyWith({
    SyncHealth? health,
    bool? busy,
    String? message,
    String? exportJson,
  }) {
    return BackupState(
      health: health ?? this.health,
      busy: busy ?? this.busy,
      message: message,
      exportJson: exportJson ?? this.exportJson,
    );
  }

  @override
  List<Object?> get props => [health, busy, message, exportJson];
}

class BackupCubit extends Cubit<BackupState> {
  BackupCubit(this._engine, this._queue, this._exporter)
    : super(const BackupState());

  final SyncEngine _engine;
  final SyncQueueRepository _queue;
  final BackupExportService _exporter;

  Future<void> refresh() async {
    emit(state.copyWith(busy: true));
    emit(state.copyWith(busy: false, health: await _engine.health()));
  }

  Future<void> syncNow() async {
    emit(state.copyWith(busy: true, message: null));
    await _engine.syncNow(force: true);
    final health = await _engine.health();
    emit(
      state.copyWith(
        busy: false,
        health: health,
        message: health.failed > 0 || health.backupFailed > 0
            ? 'اكتملت المحاولة مع أخطاء. راجع التفاصيل أدناه.'
            : 'اكتملت المزامنة والنسخ الاحتياطي.',
      ),
    );
  }

  Future<void> fullBackup() async {
    emit(state.copyWith(busy: true, message: null));
    await _engine.syncNow(force: true);
    final afterSync = await _engine.health();
    if (!afterSync.serverReachable || !afterSync.serverAuthenticated) {
      emit(
        state.copyWith(
          busy: false,
          health: afterSync,
          message: !afterSync.serverReachable
              ? 'الخادم غير متاح. شغّل الخادم ثم أعد المحاولة لتحديث Google Sheets.'
              : 'سجّل الدخول أثناء الاتصال ثم أعد محاولة تحديث الملف.',
        ),
      );
      return;
    }
    await _engine.requestFullBackup();
    final health = await _engine.health();
    emit(
      state.copyWith(
        busy: false,
        health: health,
        message: health.backupConfigured == false
            ? 'تعذر الوصول إلى Google Sheets. أضف Service Account على الخادم وشارك الملف معه كمحرر.'
            : (health.lastError != null && health.lastError!.isNotEmpty)
            ? health.lastError
            : health.backupFailed > 0
            ? 'فشلت كتابة البيانات إلى Google Sheets. راجع التشخيص أدناه.'
            : 'تم تحديث ملف Google Sheets بكل البيانات.',
      ),
    );
  }

  Future<void> retryFailed() async {
    emit(state.copyWith(busy: true, message: null));
    await _queue.retryFailed();
    await _engine.syncNow(force: true);
    await _engine.retryServerBackup();
    final health = await _engine.health();
    emit(
      state.copyWith(
        busy: false,
        health: health,
        message: health.failed > 0 || health.backupFailed > 0
            ? 'اكتملت المحاولة مع أخطاء. راجع التفاصيل أدناه.'
            : 'اكتملت إعادة المحاولة.',
      ),
    );
  }

  Future<void> exportLocal() async {
    emit(state.copyWith(busy: true));
    final json = await _exporter.exportJson();
    emit(
      state.copyWith(
        busy: false,
        exportJson: json,
        message: 'تم تجهيز النسخة الاحتياطية المحلية.',
      ),
    );
  }
}
