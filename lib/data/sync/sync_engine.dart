import 'dart:async';
import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/config/app_config.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import 'sync_baseline_service.dart';
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
  final bool? backupConfigured;
  final int backupPending;
  final int backupFailed;
  final String? backupLastError;
  final String? backupDiagnostic;
  final bool serverReachable;
  final bool serverAuthenticated;
  final String? spreadsheetUrl;

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
    required this.backupConfigured,
    required this.backupPending,
    required this.backupFailed,
    required this.backupLastError,
    required this.backupDiagnostic,
    required this.serverReachable,
    required this.serverAuthenticated,
    this.spreadsheetUrl,
  });
}

class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required MetadataStore metadata,
    required SyncQueueRepository queue,
    required SyncBaselineService baseline,
    required AppConfig config,
    required Dio dio,
    Connectivity? connectivity,
  }) : _db = db,
       _metadata = metadata,
       _queue = queue,
       _baseline = baseline,
       _config = config,
       _dio = dio,
       _connectivity = connectivity ?? Connectivity();

  final AppDatabase _db;
  final MetadataStore _metadata;
  final SyncQueueRepository _queue;
  final SyncBaselineService _baseline;
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
      unawaited(syncNow(force: true));
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
      await _baseline.ensureEnqueued();
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
        await _refreshServerBackupHealth();
        await _finishLog(logId, 'success', 0, 0, 0, null);
        await _markSuccess();
        return;
      }

      final deviceId = await _metadata.deviceId();
      for (final item in items) {
        await _queue.markProcessing(item.id);
      }
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '${_config.apiBaseUrl}/api/v1/sync/push',
          data: {
            'device_id': deviceId,
            'app_version': _config.appVersion,
            'sync_protocol_version': _config.syncProtocolVersion,
            'operations': [
              for (final item in items)
                {
                  'operation_id': item.operationId,
                  'entity_type': item.entityType,
                  'entity_id': item.entityId,
                  'operation': item.operation,
                  'payload': jsonDecode(item.payload),
                  'version':
                      ((jsonDecode(item.payload) as Map)['version'] as num?)
                          ?.toInt() ??
                      1,
                  'created_at': item.createdAt.toIso8601String(),
                },
            ],
          },
        );
        final results = (response.data?['results'] as List?) ?? const [];
        await _storeBackupStatus(response.data?['backup']);
        final byOperation = <String, Map<String, dynamic>>{
          for (final raw in results)
            if (raw is Map)
              '${(raw['operation_id'] ?? raw['id'] ?? '')}':
                  Map<String, dynamic>.from(raw),
        };
        for (var index = 0; index < items.length; index++) {
          final item = items[index];
          final first = byOperation[item.operationId] ??
              (index < results.length && results[index] is Map
                  ? Map<String, dynamic>.from(results[index] as Map)
                  : <String, dynamic>{});
          if (first.isEmpty) {
            await _queue.markPending(item.id);
            continue;
          }
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
        }
      } on DioException catch (error) {
        final authExpired =
            error.response?.statusCode == 401 ||
            error.response?.statusCode == 403;
        final message = authExpired
            ? 'انتهت جلسة الخادم. سجّل الدخول أثناء الاتصال ثم أعد المحاولة.'
            : 'الخادم غير متاح حالياً. بقيت البيانات محفوظة محلياً.';
        for (final item in items) {
          if (authExpired) {
            await _queue.markFailed(item.id, message);
            failed++;
          } else {
            await _queue.markPending(item.id);
          }
        }
        await _metadata.set(SyncConfigKeys.lastSyncError, message);
      } catch (_) {
        for (final item in items) {
          await _queue.markPending(item.id);
        }
        await _metadata.set(
          SyncConfigKeys.lastSyncError,
          'تعذر تنفيذ العملية. بقيت البيانات محفوظة محلياً، وسيتم استكمال المزامنة لاحقاً.',
        );
      }

      await _finishLog(
        logId,
        failed == 0 ? 'success' : 'partial',
        items.length,
        accepted,
        failed,
        null,
      );
      if (failed == 0 && accepted > 0) {
        await _markSuccess();
      } else if (failed > 0) {
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
    if (!await isOnline()) {
      await _metadata.set(
        SyncConfigKeys.lastSyncError,
        'لا يوجد اتصال. تعذر تحديث ملف Google Sheets.',
      );
      return;
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_config.apiBaseUrl}/api/v1/backup/full',
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      await _storeBackupStatus(response.data);
      final failed = (response.data?['failed'] as num?)?.toInt() ?? 0;
      if (response.data?['configured'] == true && failed == 0) {
        await _metadata.set(
          SyncConfigKeys.lastFullBackupAt,
          DateTime.now().toUtc().toIso8601String(),
        );
        await _metadata.set(SyncConfigKeys.lastSyncError, '');
      } else {
        await _metadata.set(
          SyncConfigKeys.lastSyncError,
          response.data?['error']?.toString() ??
              'تعذر كتابة كل البيانات إلى Google Sheets.',
        );
      }
    } on DioException catch (error) {
      await _storeBackupStatus(error.response?.data);
      final body = error.response?.data;
      final message = body is Map
          ? (body['error'] ?? body['diagnostic'] ?? body['error_code'])
                ?.toString()
          : null;
      await _metadata.set(
        SyncConfigKeys.lastSyncError,
        message == null || message.isEmpty
            ? 'تعذر إنشاء النسخة الكاملة على الخادم.'
            : message,
      );
    }
  }

  Future<SyncHealth> health() async {
    final probe = await _probeServer();
    if (probe.reachable && probe.authenticated) {
      await _refreshServerBackupHealth();
    }
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
    final backupConfiguredRaw = await _metadata.get('backup_configured');
    final backupConfigured = backupConfiguredRaw == null
        ? null
        : backupConfiguredRaw == 'true';
    final backupPending =
        int.tryParse(await _metadata.get('backup_pending') ?? '') ?? 0;
    final backupFailed =
        int.tryParse(await _metadata.get('backup_failed') ?? '') ?? 0;
    final backupLastError = await _metadata.get('backup_last_error');
    final backupDiagnostic = await _metadata.get('backup_diagnostic');
    final statusAr = failed > 0 || backupFailed > 0
        ? 'توجد مشكلة في المزامنة'
        : pending > 0
        ? 'في انتظار المزامنة'
        : backupConfigured == false
        ? 'النسخ السحابي غير مهيأ'
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
      backupConfigured: backupConfigured,
      backupPending: backupPending,
      backupFailed: backupFailed,
      backupLastError: backupLastError,
      backupDiagnostic: backupDiagnostic,
      serverReachable: probe.reachable,
      serverAuthenticated: probe.authenticated,
      spreadsheetUrl: await _metadata.get('backup_spreadsheet_url'),
    );
  }

  Future<({bool reachable, bool authenticated})> _probeServer() async {
    if (!await isOnline()) {
      return (reachable: false, authenticated: false);
    }
    try {
      await _dio.get<Map<String, dynamic>>(
        '${_config.apiBaseUrl}/api/v1/sync/status',
      );
      return (reachable: true, authenticated: true);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        return (reachable: true, authenticated: false);
      }
      return (reachable: false, authenticated: false);
    }
  }

  Future<void> retryServerBackup() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_config.apiBaseUrl}/api/v1/backup/retry',
      );
      await _storeBackupStatus(response.data);
    } on DioException catch (error) {
      await _storeBackupStatus(error.response?.data);
    }
  }

  Future<void> _refreshServerBackupHealth() async {
    if (!await isOnline()) return;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${_config.apiBaseUrl}/api/v1/backup/health',
      );
      await _storeBackupStatus(response.data);
    } catch (_) {
      // Local health remains available while the central server is offline.
    }
  }

  Future<void> _storeBackupStatus(dynamic raw) async {
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final configured = data['configured'];
    if (configured is bool) {
      await _metadata.set('backup_configured', '$configured');
    }
    final pending = data['pending'];
    if (pending != null) {
      await _metadata.set('backup_pending', '$pending');
    }
    final failed = data['failed'];
    if (failed != null) {
      await _metadata.set('backup_failed', '$failed');
    }
    final error = data['error'] ?? data['last_error'];
    await _metadata.set('backup_last_error', error?.toString() ?? '');
    final diagnostic =
        data['diagnostic'] ?? data['configuration_error'] ?? data['error_code'];
    await _metadata.set('backup_diagnostic', diagnostic?.toString() ?? '');
    final spreadsheetUrl = data['spreadsheet_url']?.toString();
    if (spreadsheetUrl != null && spreadsheetUrl.isNotEmpty) {
      await _metadata.set('backup_spreadsheet_url', spreadsheetUrl);
    }
    if (data['processed'] != null && data['pending'] == null) {
      final remainingFailed = data['failed'];
      if (remainingFailed is num && remainingFailed == 0) {
        await _metadata.set('backup_pending', '0');
      }
    }
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
    final existing =
        await (_db.select(_db.conflicts)..where(
              (row) =>
                  row.entityType.equals(item.entityType) &
                  row.entityId.equals(item.entityId) &
                  row.status.equals('open'),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await (_db.update(
        _db.conflicts,
      )..where((row) => row.id.equals(existing.id))).write(
        ConflictsCompanion(
          localPayload: Value(item.payload),
          serverPayload: Value(jsonEncode(result['server'] ?? {})),
        ),
      );
      return;
    }
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
