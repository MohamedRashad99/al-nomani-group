import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/config/app_config.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import 'sync_queue_repository.dart';

class SyncHealth {
  final DateTime? lastSuccessfulSync;
  final DateTime? nextScheduledSync;
  final DateTime? lastFullBackup;
  final int pending;
  final int failed;
  final int synced;
  final String? lastError;
  final bool online;
  final String statusAr;

  const SyncHealth({
    required this.lastSuccessfulSync,
    required this.nextScheduledSync,
    required this.lastFullBackup,
    required this.pending,
    required this.failed,
    required this.synced,
    required this.lastError,
    required this.online,
    required this.statusAr,
  });
}

class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required MetadataStore metadata,
    required SyncQueueRepository queue,
    required AppConfig config,
    required Dio dio,
    Connectivity? connectivity,
  }) : _db = db,
       _metadata = metadata,
       _queue = queue,
       _config = config,
       _dio = dio,
       _connectivity = connectivity ?? Connectivity();

  final AppDatabase _db;
  final MetadataStore _metadata;
  final SyncQueueRepository _queue;
  final AppConfig _config;
  final Dio _dio;
  final Connectivity _connectivity;

  bool _running = false;

  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<int> intervalDays() async {
    final stored =
        await (_db.select(_db.settings)
              ..where((t) => t.key.equals(SyncConfigKeys.syncIntervalDays)))
            .getSingleOrNull();
    return int.tryParse(stored?.value ?? '') ?? _config.syncIntervalDays;
  }

  Future<SyncMode> mode() async {
    final stored = await (_db.select(
      _db.settings,
    )..where((t) => t.key.equals(SyncConfigKeys.syncMode))).getSingleOrNull();
    if (stored?.value == SyncMode.nearRealtime.name) {
      return SyncMode.nearRealtime;
    }
    if (stored?.value == SyncMode.scheduled.name) {
      return SyncMode.scheduled;
    }
    return _config.syncMode;
  }

  Future<void> maybeSyncAfterLocalWrite() async {
    if (await mode() == SyncMode.nearRealtime) {
      await syncNow(force: true);
    }
  }

  Future<void> maybeRunScheduled() async {
    if (await mode() != SyncMode.scheduled) return;
    final nextRaw = await _metadata.get(SyncConfigKeys.nextScheduledSyncAt);
    if (nextRaw == null) {
      await _scheduleNext(DateTime.now().toUtc());
      return;
    }
    final next = DateTime.tryParse(nextRaw);
    if (next == null || DateTime.now().toUtc().isBefore(next)) return;
    await syncNow(force: false);
  }

  Future<void> syncNow({required bool force}) async {
    if (_running) return;
    final online = await isOnline();
    if (!online) return;

    _running = true;
    final logId = newId();
    final started = DateTime.now().toUtc();
    var accepted = 0;
    var failed = 0;
    try {
      final items = await _queue.pending();
      await _db
          .into(_db.syncLogs)
          .insert(
            SyncLogsCompanion.insert(
              id: logId,
              startedAt: started,
              status: 'running',
              pendingCount: Value(items.length),
              appVersion: Value(_config.appVersion),
              syncProtocolVersion: Value(_config.syncProtocolVersion),
            ),
          );

      if (items.isEmpty) {
        await _finishLog(logId, 'success', 0, 0, 0, null);
        await _markSuccess();
        return;
      }

      final deviceId = await _metadata.deviceId();
      for (final item in items) {
        await _queue.markProcessing(item.id);
        try {
          final response = await _dio.post<Map<String, dynamic>>(
            '${_config.apiBaseUrl}/api/v1/sync/push',
            data: {
              'device_id': deviceId,
              'app_version': _config.appVersion,
              'sync_protocol_version': _config.syncProtocolVersion,
              'operations': [
                {
                  'operation_id': item.operationId,
                  'entity_type': item.entityType,
                  'entity_id': item.entityId,
                  'operation': item.operation,
                  'payload': jsonDecode(item.payload),
                  'version': 1,
                  'created_at': item.createdAt.toIso8601String(),
                },
              ],
            },
          );
          final results = (response.data?['results'] as List?) ?? const [];
          final first = results.isEmpty
              ? <String, dynamic>{}
              : results.first as Map<String, dynamic>;
          final status = first['status'] as String? ?? 'accepted';
          if (status == 'accepted' || status == 'duplicate') {
            await _queue.markSynced(item.id);
            accepted++;
          } else if (status == 'conflict') {
            await _recordConflict(item, first);
            await _queue.markFailed(item.id, 'تعارض في الإصدار');
            failed++;
          } else {
            await _queue.markFailed(
              item.id,
              first['error'] as String? ?? 'رفض الخادم العملية',
            );
            failed++;
          }
        } catch (e) {
          await _queue.markFailed(
            item.id,
            'تعذر تنفيذ العملية. تم حفظ البيانات محلياً، وسيتم استكمال المزامنة لاحقاً.',
          );
          failed++;
        }
      }

      await _finishLog(
        logId,
        failed == 0 ? 'success' : 'partial',
        items.length,
        accepted,
        failed,
        null,
      );
      if (failed == 0) {
        await _markSuccess();
      } else {
        await _metadata.set(
          SyncConfigKeys.lastSyncError,
          'فشلت بعض عمليات المزامنة',
        );
      }
    } catch (e) {
      await _finishLog(logId, 'failed', 0, accepted, failed, e.toString());
      await _metadata.set(
        SyncConfigKeys.lastSyncError,
        'تعذر تنفيذ العملية. تم حفظ البيانات محلياً، وسيتم استكمال المزامنة لاحقاً.',
      );
    } finally {
      _running = false;
    }
  }

  Future<void> requestFullBackup() async {
    if (!await isOnline()) return;
    try {
      await _dio.post('${_config.apiBaseUrl}/api/v1/backup/full');
      await _metadata.set(
        SyncConfigKeys.lastFullBackupAt,
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      await _metadata.set(
        SyncConfigKeys.lastSyncError,
        'تعذر إنشاء النسخة الكاملة على الخادم.',
      );
    }
  }

  Future<SyncHealth> health() async {
    final last = DateTime.tryParse(
      await _metadata.get(SyncConfigKeys.lastSuccessfulSyncAt) ?? '',
    );
    final next = DateTime.tryParse(
      await _metadata.get(SyncConfigKeys.nextScheduledSyncAt) ?? '',
    );
    final full = DateTime.tryParse(
      await _metadata.get(SyncConfigKeys.lastFullBackupAt) ?? '',
    );
    final pending = await _queue.countByStatus(SyncStatus.pending);
    final failed = await _queue.countByStatus(SyncStatus.failed);
    final synced = await _queue.countByStatus(SyncStatus.synced);
    final error = await _metadata.get(SyncConfigKeys.lastSyncError);
    final online = await isOnline();
    final statusAr = failed > 0
        ? 'توجد مشكلة في المزامنة'
        : pending > 0
        ? 'في انتظار المزامنة'
        : 'محمي';
    return SyncHealth(
      lastSuccessfulSync: last,
      nextScheduledSync: next,
      lastFullBackup: full,
      pending: pending,
      failed: failed,
      synced: synced,
      lastError: error,
      online: online,
      statusAr: statusAr,
    );
  }

  Future<void> _markSuccess() async {
    final now = DateTime.now().toUtc();
    await _metadata.set(
      SyncConfigKeys.lastSuccessfulSyncAt,
      now.toIso8601String(),
    );
    await _metadata.set(SyncConfigKeys.lastSyncError, '');
    await _scheduleNext(now);
  }

  Future<void> _scheduleNext(DateTime from) async {
    final days = await intervalDays();
    await _metadata.set(
      SyncConfigKeys.nextScheduledSyncAt,
      from.add(Duration(days: days)).toIso8601String(),
    );
  }

  Future<void> _finishLog(
    String id,
    String status,
    int pending,
    int accepted,
    int failed,
    String? error,
  ) async {
    await (_db.update(_db.syncLogs)..where((t) => t.id.equals(id))).write(
      SyncLogsCompanion(
        finishedAt: Value(DateTime.now().toUtc()),
        status: Value(status),
        pendingCount: Value(pending),
        acceptedCount: Value(accepted),
        failedCount: Value(failed),
        errorMessage: Value(error),
      ),
    );
  }

  Future<void> _recordConflict(
    SyncQueueData item,
    Map<String, dynamic> result,
  ) async {
    await _db
        .into(_db.conflicts)
        .insert(
          ConflictsCompanion.insert(
            id: newId(),
            entityType: item.entityType,
            entityId: item.entityId,
            localPayload: item.payload,
            serverPayload: jsonEncode(result['server'] ?? {}),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }
}
