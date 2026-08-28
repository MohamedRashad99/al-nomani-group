import 'dart:async';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import 'firebase_actor.dart';
import 'firebase_sync_service.dart';
import 'google_sheets_live_sync.dart';

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

  static const checking = SyncHealth(
    lastSuccessfulSync: null,
    nextScheduledSync: null,
    lastFullBackup: null,
    pending: 0,
    failed: 0,
    synced: 0,
    lastError: null,
    online: true,
    statusAr: 'جارٍ التحقق من Firebase',
    backupConfigured: true,
    backupPending: 0,
    backupFailed: 0,
    backupLastError: null,
    backupDiagnostic: 'جارٍ التحقق من Firebase',
    serverReachable: true,
    serverAuthenticated: true,
  );
}

class SyncEngine {
  SyncEngine({
    required ErpStore store,
    required DeviceIdStore devices,
    required AppConfig config,
    FirebaseSyncService? firebase,
    GoogleSheetsLiveSync? sheets,
    Connectivity? connectivity,
  }) : _store = store,
       _devices = devices,
       _config = config,
       _firebase = firebase ?? FirebaseSyncService(),
       _sheets = sheets,
       _connectivity = connectivity ?? Connectivity();

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AppConfig _config;
  final FirebaseSyncService _firebase;
  final GoogleSheetsLiveSync? _sheets;
  final Connectivity _connectivity;
  Timer? _sheetsTimer;
  Future<void>? _sheetsPush;

  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> maybeSyncAfterLocalWrite() async {
    _sheetsTimer?.cancel();
    _sheetsTimer = Timer(const Duration(seconds: 20), () {
      unawaited(syncNow(force: true));
    });
  }

  Future<int> intervalDays() async {
    final raw =
        await _devices.getPref(SyncConfigKeys.syncIntervalDays) ??
        await _store.getSetting(SyncConfigKeys.syncIntervalDays);
    return int.tryParse(raw ?? '') ?? _config.syncIntervalDays;
  }

  Future<SyncMode> mode() async {
    final raw =
        await _devices.getPref(SyncConfigKeys.syncMode) ??
        await _store.getSetting(SyncConfigKeys.syncMode);
    return switch (raw) {
      'nearRealtime' || 'near_realtime' => SyncMode.nearRealtime,
      'scheduled' => SyncMode.scheduled,
      _ => _config.syncMode,
    };
  }

  Future<void> saveSyncSettings({
    required SyncMode mode,
    required int days,
  }) async {
    await _devices.setPref(SyncConfigKeys.syncMode, mode.name);
    await _devices.setPref(SyncConfigKeys.syncIntervalDays, '$days');
    await _store.putSetting(SyncConfigKeys.syncMode, mode.name);
    await _store.putSetting(SyncConfigKeys.syncIntervalDays, '$days');
    await _devices.setPref(
      SyncConfigKeys.nextScheduledSyncAt,
      DateTime.now().toUtc().add(Duration(days: days)).toIso8601String(),
    );
    if (mode == SyncMode.nearRealtime) {
      await syncNow(force: true);
    }
  }

  Future<void> maybeRunScheduled() async {
    if (await mode() != SyncMode.scheduled) return;
    unawaited(syncNow(force: false));
  }

  Future<void> syncNow({required bool force}) async {
    if (!await isOnline() && !force) return;
    if (_sheetsPush != null) {
      await _sheetsPush;
      return;
    }
    final work = _pushSheets();
    _sheetsPush = work;
    try {
      await work;
    } finally {
      if (identical(_sheetsPush, work)) {
        _sheetsPush = null;
      }
    }
  }

  Future<void> _pushSheets() async {
    try {
      final sheets = _sheets;
      if (sheets != null) {
        await sheets.pushAll();
      }
      await _devices.setPref(
        SyncConfigKeys.lastSuccessfulSyncAt,
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (error) {
      debugPrint('Sync/sheets push failed: $error');
      await _devices.setPref(SyncConfigKeys.lastSyncError, '$error');
    }
  }

  Future<void> recordAuthenticatedSession({
    required String userId,
    required String username,
    required String displayName,
    required String roleId,
  }) async {
    await _firebase.recordAuthenticatedSession(
      actor: FirebaseActor(
        userId: userId,
        username: username,
        displayName: displayName,
        roleId: roleId,
      ),
      deviceId: await _devices.deviceId(),
      sessionId: newId(),
    );
  }

  Future<SyncHealth> health() async {
    final online = await isOnline();
    final lastRaw = await _devices.getPref(SyncConfigKeys.lastSuccessfulSyncAt);
    final error = await _devices.getPref(SyncConfigKeys.lastSyncError);
    final fb = await _firebase.health();
    return SyncHealth(
      lastSuccessfulSync: lastRaw == null ? null : DateTime.tryParse(lastRaw),
      nextScheduledSync: null,
      lastFullBackup: lastRaw == null ? null : DateTime.tryParse(lastRaw),
      pending: 0,
      failed: fb.ok ? 0 : 1,
      synced: fb.records,
      lastError: error ?? fb.error,
      online: online,
      statusAr: fb.ok
          ? 'البيانات محفوظة في Firebase'
          : (fb.error ?? 'تعذر الاتصال بـ Firebase'),
      backupConfigured: fb.ok,
      backupPending: 0,
      backupFailed: fb.ok ? 0 : 1,
      backupLastError: fb.error,
      backupDiagnostic: fb.ok
          ? 'Firebase جاهز'
          : fb.error,
      serverReachable: fb.ok,
      serverAuthenticated: fb.ok,
      spreadsheetUrl: _config.googleLiveSpreadsheetId.isEmpty
          ? null
          : 'https://docs.google.com/spreadsheets/d/${_config.googleLiveSpreadsheetId}/edit',
    );
  }
}
