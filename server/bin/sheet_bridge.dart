import 'dart:convert';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

/// Tiny CORS bridge so the Flutter web app can update Google Sheets.
Future<void> main() async {
  final file = File('../secrets/google-service-account.json');
  if (!file.existsSync()) {
    stderr.writeln('Missing secrets/google-service-account.json');
    exitCode = 1;
    return;
  }
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final credentials = ServiceAccountCredentials.fromJson(raw);
  final client = await clientViaServiceAccount(credentials, [
    sheets.SheetsApi.spreadsheetsScope,
  ]);
  final api = sheets.SheetsApi(client);

  final app = Router()
    ..options('/sheets/write', (request) => Response.ok(''))
    ..post('/sheets/write', (Request request) async {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final spreadsheetId = body['spreadsheetId'] as String? ?? '';
      final sections = Map<String, dynamic>.from(body['sections'] as Map);
      if (spreadsheetId.isEmpty) {
        return Response.badRequest(body: 'missing spreadsheetId');
      }
      await _write(api, spreadsheetId, sections);
      return Response.ok(jsonEncode({'ok': true}));
    });

  final handler = const Pipeline()
      .addMiddleware(_cors())
      .addHandler(app.call);
  final server = await io.serve(handler, InternetAddress.loopbackIPv4, 8765);
  stdout.writeln('Sheet bridge listening on http://127.0.0.1:${server.port}');
}

Middleware _cors() {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
  return (inner) {
    return (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: headers);
      }
      final response = await inner(request);
      return response.change(headers: headers);
    };
  };
}

Future<void> _write(
  sheets.SheetsApi api,
  String spreadsheetId,
  Map<String, dynamic> sections,
) async {
  final spreadsheet = await api.spreadsheets.get(spreadsheetId);
  final existing = {
    for (final sheet in spreadsheet.sheets ?? const <sheets.Sheet>[])
      if (sheet.properties?.title != null) sheet.properties!.title!,
  };
  final add = [
    for (final tab in sections.keys)
      if (!existing.contains(tab))
        sheets.Request(
          addSheet: sheets.AddSheetRequest(
            properties: sheets.SheetProperties(title: tab),
          ),
        ),
  ];
  if (add.isNotEmpty) {
    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: add),
      spreadsheetId,
    );
  }
  for (final entry in sections.entries) {
    final values = [
      for (final row in (entry.value as List))
        [for (final value in (row as List)) value],
    ];
    await api.spreadsheets.values.clear(
      sheets.ClearValuesRequest(),
      spreadsheetId,
      "'${entry.key}'!A:ZZ",
    );
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: values),
      spreadsheetId,
      "'${entry.key}'!A1",
      valueInputOption: 'RAW',
    );
  }
  stdout.writeln('Updated ${sections.length} Arabic tabs.');
}
