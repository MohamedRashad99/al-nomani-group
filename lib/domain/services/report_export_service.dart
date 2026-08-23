import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/file_download.dart';
import '../../data/local/app_database.dart';

enum ReportFileType { csv, excel, pdf }

class ReportExportService {
  ReportExportService(this._db);

  final AppDatabase _db;

  Future<void> exportSales(ReportFileType type) async {
    final sales = await _db.select(_db.sales).get();
    final customers = await _db.select(_db.customers).get();
    final customerNames = {
      for (final customer in customers) customer.id: customer.name,
    };
    final rows = <List<dynamic>>[
      [
        'رقم الفاتورة',
        'العميل',
        'الحالة',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'التاريخ',
      ],
      for (final sale in sales)
        [
          sale.saleNumber,
          customerNames[sale.customerId] ?? '',
          sale.status,
          sale.subtotal,
          sale.paidAmount,
          sale.remainingAmount,
          sale.soldAt.toLocal().toIso8601String(),
        ],
    ];
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    switch (type) {
      case ReportFileType.csv:
        final csv = const ListToCsvConverter().convert(rows);
        await downloadBytes(
          Uint8List.fromList(utf8.encode('\uFEFF$csv')),
          filename: 'sales-$stamp.csv',
          mimeType: 'text/csv;charset=utf-8',
        );
        return;
      case ReportFileType.excel:
        final workbook = Excel.createExcel();
        final sheet = workbook['المبيعات'];
        for (final row in rows) {
          sheet.appendRow([
            for (final value in row) TextCellValue(value.toString()),
          ]);
        }
        workbook.delete('Sheet1');
        final bytes = workbook.encode();
        if (bytes == null) throw StateError('تعذر إنشاء ملف Excel.');
        await downloadBytes(
          Uint8List.fromList(bytes),
          filename: 'sales-$stamp.xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
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
                child: pw.Text('تقرير مبيعات مجموعة النعماني'),
              ),
              pw.TableHelper.fromTextArray(
                headers: rows.first.map((value) => value.toString()).toList(),
                data: rows
                    .skip(1)
                    .map((row) => row.map((value) => value.toString()).toList())
                    .toList(),
                headerStyle: pw.TextStyle(font: font),
                cellStyle: pw.TextStyle(font: font, fontSize: 8),
                cellAlignment: pw.Alignment.centerRight,
              ),
            ],
          ),
        );
        await downloadBytes(
          await document.save(),
          filename: 'sales-$stamp.pdf',
          mimeType: 'application/pdf',
        );
        return;
    }
  }
}
