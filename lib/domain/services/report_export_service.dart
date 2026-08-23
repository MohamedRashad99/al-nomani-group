import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/file_download.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/arabic_workbook_builder.dart';

enum ReportFileType { csv, excel, pdf }

class ReportExportService {
  ReportExportService(this._db);

  final AppDatabase _db;

  Future<void> exportSales(ReportFileType type) async {
    final sections = await ArabicWorkbookBuilder(_db).build();
    final sales = sections[SheetArabic.sales]!;
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    switch (type) {
      case ReportFileType.csv:
        final csv = const ListToCsvConverter().convert(sales);
        await downloadBytes(
          Uint8List.fromList(utf8.encode('\uFEFF$csv')),
          filename: 'المبيعات-$stamp.csv',
          mimeType: 'text/csv;charset=utf-8',
        );
        return;
      case ReportFileType.excel:
        await exportAllArabicExcel();
        return;
      case ReportFileType.pdf:
        final fontData = await rootBundle.load(
          'assets/fonts/NotoKufiArabic-Regular.ttf',
        );
        final font = pw.Font.ttf(fontData);
        final document = pw.Document();
        document.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            theme: pw.ThemeData.withFont(base: font, bold: font),
            textDirection: pw.TextDirection.rtl,
            build: (_) => [
              pw.Header(
                level: 0,
                child: pw.Text('تقرير مجموعة النعماني — كل الأقسام'),
              ),
              for (final entry in sections.entries) ...[
                pw.Text(entry.key, style: pw.TextStyle(font: font, fontSize: 14)),
                pw.SizedBox(height: 6),
                pw.TableHelper.fromTextArray(
                  headers: entry.value.first
                      .map((value) => value.toString())
                      .toList(),
                  data: entry.value
                      .skip(1)
                      .map(
                        (row) => row.map((value) => value.toString()).toList(),
                      )
                      .toList(),
                  headerStyle: pw.TextStyle(font: font),
                  cellStyle: pw.TextStyle(font: font, fontSize: 8),
                  cellAlignment: pw.Alignment.centerRight,
                ),
                pw.SizedBox(height: 16),
              ],
            ],
          ),
        );
        await downloadBytes(
          await document.save(),
          filename: 'التقارير-$stamp.pdf',
          mimeType: 'application/pdf',
        );
        return;
    }
  }

  Future<void> exportAllArabicExcel() async {
    final workbook = Excel.createExcel();
    final sections = await ArabicWorkbookBuilder(_db).build();
    for (final entry in sections.entries) {
      final sheet = workbook[entry.key];
      for (final row in entry.value) {
        sheet.appendRow([
          for (final value in row) TextCellValue(value.toString()),
        ]);
      }
    }
    workbook.delete('Sheet1');
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('تعذر إنشاء ملف Excel.');
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await downloadBytes(
      Uint8List.fromList(bytes),
      filename: 'مجموعة-النعماني-$stamp.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }
}
