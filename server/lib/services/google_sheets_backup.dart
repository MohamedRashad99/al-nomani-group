import 'dart:convert';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../config/env.dart';
import '../database/postgres_db.dart';

class BackupProcessingResult {
  const BackupProcessingResult({
    required this.configured,
    required this.processed,
    required this.failed,
    this.error,
  });

  final bool configured;
  final int processed;
  final int failed;
  final String? error;

  Map<String, dynamic> toJson() => {
    'configured': configured,
    'processed': processed,
    'failed': failed,
    'status': !configured
        ? 'not_configured'
        : failed > 0
        ? 'failed'
        : 'healthy',
    if (error != null) 'error': error,
  };
}

/// Google Sheets is a backup layer only.
///
/// PostgreSQL acceptance is committed before this service handles its durable
/// outbox. A Sheets failure is retained for retry and exposed to administrators.
class GoogleSheetsBackup {
  GoogleSheetsBackup(this.env, this.db);

  final Env env;
  final PostgresDb db;

  static const tabs = {
    'product': 'Products',
    'category': 'Categories',
    'customer': 'Customers',
    'sale': 'Sales',
    'saleItem': 'Sale Items',
    'customerAccount': 'Customer Accounts',
    'customerAccountTransaction': 'Customer Accounts',
    'collection': 'Collections',
    'inventoryMovement': 'Inventory Movements',
    'user': 'Users',
    'auditLog': 'Audit Logs',
    'setting': 'Settings',
  };

  static const fullBackupTables = {
    'Products': 'products',
    'Categories': 'product_categories',
    'Customers': 'customers',
    'Sales': 'sales',
    'Sale Items': 'sale_items',
    'Customer Accounts': 'customer_account_transactions',
    'Collections': 'collections',
    'Inventory Movements': 'inventory_movements',
    'Users': 'users',
    'Audit Logs': 'audit_logs',
    'Sync Logs': 'sync_logs',
  };

  bool get isConfigured =>
      env.googleServiceAccountJson?.isNotEmpty == true &&
      env.googleLiveSpreadsheetId.isNotEmpty;

  Future<BackupProcessingResult> processPending({int limit = 100}) async {
    if (!isConfigured) {
      return const BackupProcessingResult(
        configured: false,
        processed: 0,
        failed: 0,
        error: 'بيانات اعتماد Google Sheets غير مهيأة على الخادم.',
      );
    }

    final rows = await db.query(
      '''
      SELECT id, entity_type, entity_id, payload
      FROM backup_outbox
      WHERE status IN ('pending', 'failed')
      ORDER BY created_at
      LIMIT @limit
      ''',
      params: {'limit': limit},
    );
    if (rows.isEmpty) {
      return const BackupProcessingResult(
        configured: true,
        processed: 0,
        failed: 0,
      );
    }

    var processed = 0;
    var failed = 0;
    String? lastError;
    try {
      final api = await _api();
      await _ensureTabs(api, env.googleLiveSpreadsheetId);
      for (final row in rows) {
        final outboxId = row[0] as String;
        final entityType = row[1] as String;
        final entityId = row[2] as String;
        final payload = Map<String, dynamic>.from(
          jsonDecode(row[3] as String) as Map,
        );
        try {
          final tab = tabs[entityType] ?? 'Sync Logs';
          await _upsertByStableId(
            api: api,
            spreadsheetId: env.googleLiveSpreadsheetId,
            tab: tab,
            entityId: entityId,
            payload: payload,
          );
          await db.query(
            '''
            UPDATE backup_outbox SET
              status = 'synced', synced_at = NOW(), last_attempt_at = NOW(),
              last_error = NULL
            WHERE id = @id
            ''',
            params: {'id': outboxId},
          );
          processed++;
        } catch (error) {
          final safeError = _safeError(error);
          await db.query(
            '''
            UPDATE backup_outbox SET
              status = 'failed', retry_count = retry_count + 1,
              last_attempt_at = NOW(), last_error = @error
            WHERE id = @id
            ''',
            params: {'id': outboxId, 'error': safeError},
          );
          failed++;
          lastError = safeError;
        }
      }
    } catch (error) {
      failed = rows.length;
      lastError = _safeError(error);
    }

    return BackupProcessingResult(
      configured: true,
      processed: processed,
      failed: failed,
      error: lastError,
    );
  }

  Future<BackupProcessingResult> writeFullBackup() async {
    if (env.googleServiceAccountJson?.isNotEmpty != true ||
        env.googleFullSpreadsheetId.isEmpty) {
      return const BackupProcessingResult(
        configured: false,
        processed: 0,
        failed: 0,
        error: 'ملف النسخة الكاملة أو بيانات Google غير مهيأة.',
      );
    }

    final runId = 'full-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    await db.query(
      '''
      INSERT INTO backup_runs (id, kind, spreadsheet_id, status)
      VALUES (@id, 'full', @sheet, 'running')
      ''',
      params: {'id': runId, 'sheet': env.googleFullSpreadsheetId},
    );

    var rowsWritten = 0;
    try {
      final api = await _api();
      await _ensureTabs(api, env.googleFullSpreadsheetId);
      for (final entry in fullBackupTables.entries) {
        final rows = await _tableSnapshot(entry.value);
        rowsWritten += rows.length > 1 ? rows.length - 1 : 0;
        await api.spreadsheets.values.clear(
          ClearValuesRequest(),
          env.googleFullSpreadsheetId,
          "'${entry.key}'!A:ZZ",
        );
        await api.spreadsheets.values.update(
          ValueRange(values: rows),
          env.googleFullSpreadsheetId,
          "'${entry.key}'!A1",
          valueInputOption: 'RAW',
        );
      }
      await db.query(
        '''
        UPDATE backup_runs SET
          status = 'success', finished_at = NOW(), rows_written = @rows
        WHERE id = @id
        ''',
        params: {'id': runId, 'rows': rowsWritten},
      );
      return BackupProcessingResult(
        configured: true,
        processed: rowsWritten,
        failed: 0,
      );
    } catch (error) {
      final safeError = _safeError(error);
      await db.query(
        '''
        UPDATE backup_runs SET
          status = 'failed', finished_at = NOW(), error_message = @error
        WHERE id = @id
        ''',
        params: {'id': runId, 'error': safeError},
      );
      return BackupProcessingResult(
        configured: true,
        processed: rowsWritten,
        failed: 1,
        error: safeError,
      );
    }
  }

  Future<Map<String, dynamic>> health() async {
    final pending = await db.query(
      '''
      SELECT
        COUNT(*) FILTER (WHERE status = 'pending'),
        COUNT(*) FILTER (WHERE status = 'failed'),
        MAX(synced_at),
        MAX(last_error) FILTER (WHERE status = 'failed')
      FROM backup_outbox
      ''',
    );
    final latestFull = await db.query(
      '''
      SELECT status, finished_at, error_message
      FROM backup_runs
      WHERE kind = 'full'
      ORDER BY started_at DESC
      LIMIT 1
      ''',
    );
    return {
      'configured': isConfigured,
      'live_spreadsheet_configured': env.googleLiveSpreadsheetId.isNotEmpty,
      'full_spreadsheet_configured': env.googleFullSpreadsheetId.isNotEmpty,
      'pending': pending.first[0],
      'failed': pending.first[1],
      'last_success_at': pending.first[2]?.toString(),
      'last_error': pending.first[3],
      'last_full_backup': latestFull.isEmpty
          ? null
          : {
              'status': latestFull.first[0],
              'finished_at': latestFull.first[1]?.toString(),
              'error': latestFull.first[2],
            },
    };
  }

  Future<SheetsApi> _api() async {
    final raw = env.googleServiceAccountJson;
    if (raw == null || raw.isEmpty) {
      throw StateError('GOOGLE_SERVICE_ACCOUNT_JSON is missing');
    }
    final credentials = ServiceAccountCredentials.fromJson(jsonDecode(raw));
    final client = await clientViaServiceAccount(credentials, [
      SheetsApi.spreadsheetsScope,
    ]);
    return SheetsApi(client);
  }

  Future<void> _upsertByStableId({
    required SheetsApi api,
    required String spreadsheetId,
    required String tab,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    final normalized = <String, dynamic>{
      'id': entityId,
      ...payload,
      'backup_updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final headers = normalized.keys.toList();
    await _ensureHeader(api, spreadsheetId, tab, headers);
    final existing = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$tab'!A:A",
    );
    final values = existing.values ?? const [];
    final index = values.indexWhere(
      (row) => row.isNotEmpty && row.first.toString() == entityId,
    );
    final output = [for (final header in headers) normalized[header]];
    if (index >= 1) {
      await api.spreadsheets.values.update(
        ValueRange(values: [output]),
        spreadsheetId,
        "'$tab'!A${index + 1}",
        valueInputOption: 'RAW',
      );
    } else {
      await api.spreadsheets.values.append(
        ValueRange(values: [output]),
        spreadsheetId,
        "'$tab'!A1",
        valueInputOption: 'RAW',
        insertDataOption: 'INSERT_ROWS',
      );
    }
  }

  Future<void> _ensureHeader(
    SheetsApi api,
    String spreadsheetId,
    String tab,
    List<String> headers,
  ) async {
    final current = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$tab'!1:1",
    );
    final existing = current.values?.firstOrNull;
    if (existing == null || existing.isEmpty) {
      await api.spreadsheets.values.update(
        ValueRange(values: [headers]),
        spreadsheetId,
        "'$tab'!A1",
        valueInputOption: 'RAW',
      );
    }
  }

  Future<List<List<Object?>>> _tableSnapshot(String table) async {
    final result = await db.query('SELECT row_to_json(t)::text FROM $table t');
    final records = result
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row[0] as String) as Map,
          ),
        )
        .toList();
    if (records.isEmpty) return const <List<Object?>>[];
    final headers = records.expand((record) => record.keys).toSet().toList();
    return [
      headers,
      for (final record in records)
        [
          for (final header in headers)
            record[header] is Map || record[header] is List
                ? jsonEncode(record[header])
                : record[header]?.toString(),
        ],
    ];
  }

  Future<void> _ensureTabs(SheetsApi api, String spreadsheetId) async {
    final spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final existing = (spreadsheet.sheets ?? [])
        .map((sheet) => sheet.properties?.title)
        .whereType<String>()
        .toSet();
    final needed = {...tabs.values, ...fullBackupTables.keys, 'Sync Logs'};
    final requests = [
      for (final tab in needed)
        if (!existing.contains(tab))
          Request(
            addSheet: AddSheetRequest(properties: SheetProperties(title: tab)),
          ),
    ];
    if (requests.isNotEmpty) {
      await api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(requests: requests),
        spreadsheetId,
      );
    }
  }

  String _safeError(Object error) {
    stderr.writeln('Google Sheets backup failed: $error');
    final text = error.toString();
    return text.length > 500 ? text.substring(0, 500) : text;
  }
}
