import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/config/app_config.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/file_download.dart';
import '../../data/sync/arabic_workbook_builder.dart';
import '../session.dart';

enum ReportFileType { csv, excel, pdf }

class ReportBranding {
  const ReportBranding({
    required this.companyName,
    required this.systemName,
    required this.administratorName,
    required this.generatedAt,
  });

  factory ReportBranding.fromSession(AppSession session) {
    return ReportBranding(
      companyName: S.appName,
      systemName: S.appSubtitle,
      administratorName: session.displayName,
      generatedAt: EgyptTime.nowUtc(),
    );
  }

  final String companyName;
  final String systemName;
  final String administratorName;
  final DateTime generatedAt;

  String get stamp => EgyptTime.formatDateTime(generatedAt);

  List<List<Object?>> coverRows() {
    return [
      ['الشركة', companyName],
      ['النظام', systemName],
      ['المسؤول', administratorName],
      ['تاريخ الإنشاء', stamp],
      ['إصدار البناء', AppConfig.egyptBuildLabel(generatedAt)],
    ];
  }
}

class ReportExportService {
  ReportExportService(this._workbook);

  final ArabicWorkbookBuilder _workbook;

  Future<Map<String, List<List<Object?>>>> sections() => _workbook.build();

  Future<Uint8List> buildCsvBytes({required ReportBranding branding}) async {
    final sections = await _workbook.build();
    final sales = sections[SheetArabic.sales]!;
    final rows = <List<Object?>>[
      ...branding.coverRows(),
      <Object?>[],
      ...sales,
    ];
    final csv = const ListToCsvConverter().convert(
      rows.map((row) => row.map((value) => value?.toString() ?? '').toList()).toList(),
    );
    return Uint8List.fromList(utf8.encode('\uFEFF$csv'));
  }

  Future<Uint8List> buildExcelBytes({required ReportBranding branding}) async {
    final workbook = Excel.createExcel();
    final cover = workbook['غلاف التقرير'];
    for (final row in branding.coverRows()) {
      cover.appendRow([
        for (final value in row) TextCellValue(value.toString()),
      ]);
    }
    final sections = await _workbook.build();
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
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> buildPdfBytes({required ReportBranding branding}) async {
    final sections = await _workbook.build();
    final fontData = await rootBundle.load(
      'assets/fonts/NotoKufiArabic-Regular.ttf',
    );
    final font = pw.Font.ttf(fontData);
    pw.MemoryImage? logo;
    try {
      final logoData = await rootBundle.load('assets/images/al_nomani_logo.png');
      logo = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }

    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 36, 28, 36),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        textDirection: pw.TextDirection.rtl,
        header: (context) => _pdfHeader(branding, font, logo),
        footer: (context) => _pdfFooter(context, branding, font),
        build: (_) => [
          for (final entry in sections.entries) ...[
            pw.Text(
              entry.key,
              style: pw.TextStyle(
                font: font,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
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
              headerStyle: pw.TextStyle(
                font: font,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(font: font, fontSize: 8),
              cellAlignment: pw.Alignment.centerRight,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8F5E9),
              ),
            ),
            pw.SizedBox(height: 16),
          ],
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _pdfHeader(
    ReportBranding branding,
    pw.Font font,
    pw.MemoryImage? logo,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColor.fromInt(0xFF2E7D32), width: 1.2),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null)
            pw.Container(
              width: 42,
              height: 42,
              margin: const pw.EdgeInsets.only(left: 10),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  branding.companyName,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  branding.systemName,
                  style: pw.TextStyle(font: font, fontSize: 9),
                ),
                pw.Text(
                  'المسؤول: ${branding.administratorName}',
                  style: pw.TextStyle(font: font, fontSize: 8),
                ),
              ],
            ),
          ),
          pw.Text(
            branding.stamp,
            style: pw.TextStyle(font: font, fontSize: 8),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfFooter(
    pw.Context context,
    ReportBranding branding,
    pw.Font font,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromInt(0xFFBDBDBD), width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            branding.companyName,
            style: pw.TextStyle(font: font, fontSize: 8),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: font, fontSize: 8),
          ),
          pw.Text(
            branding.systemName,
            style: pw.TextStyle(font: font, fontSize: 8),
          ),
        ],
      ),
    );
  }

  Future<void> download(
    ReportFileType type, {
    required ReportBranding branding,
  }) async {
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    switch (type) {
      case ReportFileType.csv:
        await downloadBytes(
          await buildCsvBytes(branding: branding),
          filename: 'المبيعات-$stamp.csv',
          mimeType: 'text/csv;charset=utf-8',
        );
        return;
      case ReportFileType.excel:
        await downloadBytes(
          await buildExcelBytes(branding: branding),
          filename: 'مجموعة-النعماني-$stamp.xlsx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        return;
      case ReportFileType.pdf:
        await downloadBytes(
          await buildPdfBytes(branding: branding),
          filename: 'التقارير-$stamp.pdf',
          mimeType: 'application/pdf',
        );
        return;
    }
  }

  Future<void> exportSales(
    ReportFileType type, {
    ReportBranding? branding,
  }) {
    return download(
      type,
      branding: branding ??
          ReportBranding(
            companyName: S.appName,
            systemName: S.appSubtitle,
            administratorName: S.owner,
            generatedAt: DateTime.now(),
          ),
    );
  }
}
