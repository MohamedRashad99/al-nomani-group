import 'dart:typed_data';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/l10n/app_strings.dart';
import '../../core/utils/arabic_format.dart';
import '../../core/utils/file_download.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/report_export_service.dart';
import '../../domain/session.dart';

class SupplierStatementExport {
  SupplierStatementExport._();

  static Future<void> sharePdf({
    required AppSession session,
    required Supplier supplier,
    required List<SupplierAccountTransaction> txs,
    required Money openingBalance,
  }) async {
    final bytes = await buildPdf(
      session: session,
      supplier: supplier,
      txs: txs,
      openingBalance: openingBalance,
    );
    await downloadBytes(
      bytes,
      filename: 'كشف-${supplier.name}-${EgyptTime.formatDate(EgyptTime.nowUtc())}.pdf',
      mimeType: 'application/pdf',
    );
  }

  static Future<Uint8List> buildPdf({
    required AppSession session,
    required Supplier supplier,
    required List<SupplierAccountTransaction> txs,
    required Money openingBalance,
  }) async {
    final branding = ReportBranding.fromSession(session);
    final fontData = await rootBundle.load(
      'assets/fonts/NotoKufiArabic-Regular.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final sorted = [...txs]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var balance = openingBalance;
    final rows = <List<String>>[];
    for (final tx in sorted) {
      final amount = Money.parse(tx.amount);
      final debit = amount.isPositive ? amount : Money.zero();
      final credit = amount.isNegative ? -amount : Money.zero();
      balance += amount;
      rows.add([
        ArabicFormat.transactionDateTime(tx.createdAt),
        _txLabel(tx.type),
        debit.isZero ? '' : debit.toDisplay(),
        credit.isZero ? '' : credit.toDisplay(),
        balance.toDisplay(),
      ]);
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Text(
            S.appName,
            style: pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('كشف حساب مورد: ${supplier.name}', style: pw.TextStyle(font: font, fontSize: 14)),
          pw.Text('تاريخ الإنشاء: ${branding.stamp}', style: pw.TextStyle(font: font, fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['التاريخ', 'نوع العملية', 'مدين', 'دائن', 'الرصيد'],
            data: rows,
            headerStyle: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
            cellStyle: pw.TextStyle(font: font, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerRight,
          ),
        ],
      ),
    );
    return doc.save();
  }

  static String _txLabel(String type) => switch (type) {
    'purchase' => 'شراء',
    'payment' => 'سداد',
    'purchase_cancel' => 'عكس شراء ملغى',
    'payment_cancel' => 'عكس سداد',
    'purchase_return' => 'مرتجع شراء',
    'receipt' => 'إيصال / خصم',
    _ => 'حركة حساب',
  };
}
