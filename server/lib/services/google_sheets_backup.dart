import 'dart:convert';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';

import '../config/env.dart';

/// Google Sheets is a backup layer only. Failures never delete or mutate local/server business data.
class GoogleSheetsBackup {
  GoogleSheetsBackup(this.env);
  final Env env;

  static const tabs = [
    'Products',
    'Categories',
    'Customers',
    'Sales',
    'Sale Items',
    'Customer Accounts',
    'Collections',
    'Inventory Movements',
    'Users',
    'Audit Logs',
    'Sync Logs',
  ];

  Future<void> appendLive(List<Map<String, dynamic>> operations) async {
    final api = await _api();
    if (api == null) return;
    await _ensureTabs(api, env.googleLiveSpreadsheetId);
    final values = operations
        .map(
          (op) => [
            op['operation_id'],
            op['entity_type'],
            op['entity_id'],
            op['operation'],
            jsonEncode(op['payload']),
            DateTime.now().toUtc().toIso8601String(),
          ],
        )
        .toList();
    await api.spreadsheets.values.append(
      ValueRange(values: values),
      env.googleLiveSpreadsheetId,
      'Sync Logs!A1',
      valueInputOption: 'RAW',
    );
  }

  Future<void> writeFullBackup(Map<String, List<List<Object?>>> sheets) async {
    final api = await _api();
    if (api == null) return;
    await _ensureTabs(api, env.googleFullSpreadsheetId);
    for (final entry in sheets.entries) {
      await api.spreadsheets.values.clear(
        ClearValuesRequest(),
        env.googleFullSpreadsheetId,
        '${entry.key}!A:Z',
      );
      await api.spreadsheets.values.update(
        ValueRange(values: entry.value),
        env.googleFullSpreadsheetId,
        '${entry.key}!A1',
        valueInputOption: 'RAW',
      );
    }
  }

  Future<SheetsApi?> _api() async {
    final raw = env.googleServiceAccountJson;
    if (raw == null || raw.isEmpty) {
      stderr.writeln(
        'GOOGLE_SERVICE_ACCOUNT_JSON missing — Sheets backup skipped (data remains in PostgreSQL).',
      );
      return null;
    }
    final credentials = ServiceAccountCredentials.fromJson(jsonDecode(raw));
    final client = await clientViaServiceAccount(credentials, [
      SheetsApi.spreadsheetsScope,
    ]);
    return SheetsApi(client);
  }

  Future<void> _ensureTabs(SheetsApi api, String spreadsheetId) async {
    final sheet = await api.spreadsheets.get(spreadsheetId);
    final existing = (sheet.sheets ?? [])
        .map((s) => s.properties?.title)
        .whereType<String>()
        .toSet();
    final requests = <Request>[];
    for (final tab in tabs) {
      if (!existing.contains(tab)) {
        requests.add(
          Request(
            addSheet: AddSheetRequest(properties: SheetProperties(title: tab)),
          ),
        );
      }
    }
    if (requests.isEmpty) return;
    await api.spreadsheets.batchUpdate(
      BatchUpdateSpreadsheetRequest(requests: requests),
      spreadsheetId,
    );
  }
}
