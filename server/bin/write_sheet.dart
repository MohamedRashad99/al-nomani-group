import 'dart:convert';
import 'dart:io';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'package:al_nomani_server/services/sheet_workbook.dart';

/// Writes Arabic structured tabs to the live spreadsheet without PostgreSQL.
Future<void> main() async {
  const spreadsheetId = '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I';
  final file = File('../secrets/google-service-account.json');
  if (!file.existsSync()) {
    stderr.writeln('Missing secrets/google-service-account.json');
    exitCode = 1;
    return;
  }

  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final email = raw['client_email'] as String? ?? '';
  stdout.writeln('Service account: $email');
  stdout.writeln('Spreadsheet: $spreadsheetId');

  try {
    final credentials = ServiceAccountCredentials.fromJson(raw);
    final client = await clientViaServiceAccount(credentials, [
      SheetsApi.spreadsheetsScope,
    ]).timeout(const Duration(seconds: 20));
    final api = SheetsApi(client);

    var spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final existing = {
      for (final sheet in spreadsheet.sheets ?? const <Sheet>[])
        if (sheet.properties?.title != null) sheet.properties!.title!,
    };
    final needed = {
      SheetArabic.overview,
      ...structuredSheets.map((sheet) => sheet.tab),
    };
    final add = [
      for (final tab in needed)
        if (!existing.contains(tab))
          Request(
            addSheet: AddSheetRequest(properties: SheetProperties(title: tab)),
          ),
    ];
    if (add.isNotEmpty) {
      await api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(requests: add),
        spreadsheetId,
      );
    }

    spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final sheets = spreadsheet.sheets ?? const <Sheet>[];
    final remove = [
      for (final sheet in sheets)
        if (SheetArabic.retiredEnglishTabs.contains(sheet.properties?.title) &&
            sheet.properties?.sheetId != null)
          Request(
            deleteSheet: DeleteSheetRequest(sheetId: sheet.properties!.sheetId),
          ),
    ];
    if (remove.isNotEmpty && remove.length < sheets.length) {
      await api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(requests: remove),
        spreadsheetId,
      );
    }

    await api.spreadsheets.values.update(
      ValueRange(
        values: [
          ['البيان', 'القيمة'],
          ['وقت الكتابة', SheetArabic.cell(DateTime.now().toUtc())],
          ['حساب الخدمة', email],
          [
            'الحالة',
            'الملف بالعربية. بيانات الأقسام تُملأ بعد المزامنة أو تصدير Excel.',
          ],
        ],
      ),
      spreadsheetId,
      "'${SheetArabic.overview}'!A1",
      valueInputOption: 'RAW',
    );

    for (final sheet in structuredSheets) {
      final values = buildSheetValues(columns: sheet.columns, rows: const []);
      await api.spreadsheets.values.clear(
        ClearValuesRequest(),
        spreadsheetId,
        "'${sheet.tab}'!A:ZZ",
      );
      await api.spreadsheets.values.update(
        ValueRange(values: values),
        spreadsheetId,
        "'${sheet.tab}'!A1",
        valueInputOption: 'RAW',
      );
    }

    stdout.writeln('OK: Arabic workbook written.');
    client.close();
  } catch (error) {
    stderr.writeln('FAILED: $error');
    stderr.writeln(
      'Share the spreadsheet as Editor with $email and enable Google Sheets API.',
    );
    exitCode = 2;
  }
}
