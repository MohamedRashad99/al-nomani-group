import 'dart:typed_data';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/cairo_date_range.dart';
import '../../domain/services/dashboard_service.dart';
import '../../domain/services/report_export_service.dart';
import '../../shared/widgets/date_range_bar.dart';
import '../../features/app/app_alert_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';
import '../../shared/widgets/report_busy_barrier.dart';
import '../../shared/widgets/summary_metrics.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late CairoDateRange _range = CairoDateRange.preset(ReportPeriod.thisMonth);

  ReportBranding _branding() {
    final session = context.read<AuthCubit>().state.session;
    if (session == null) {
      return ReportBranding(
        companyName: S.appName,
        systemName: S.appSubtitle,
        administratorName: S.owner,
        generatedAt: DateTime.now(),
        range: _range,
      );
    }
    return ReportBranding.fromSession(session, range: _range);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    final canExport = session?.can(AppPermission.reportsExport) == true;
    final canFinancial = session?.isAdmin == true;
    return AppScaffold(
      title: S.reports,
      child: FutureBuilder<({Money sales, Money collections})>(
        future: sl<DashboardService>().totalsIn(_range),
        builder: (context, snapshot) {
          final totals = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DateRangeBar(
                value: _range,
                onChanged: (range) => setState(() => _range = range),
              ),
              const SizedBox(height: 16),
              if (canFinancial)
                SummaryMetricsRow(
                  cardWidth: 280,
                  metrics: [
                    SummaryMetric(
                      label: 'مبيعات الفترة',
                      value: totals == null
                          ? const SizedBox(
                              width: 72,
                              child: LinearProgressIndicator(minHeight: 2),
                            )
                          : MoneyText(totals.sales),
                    ),
                    SummaryMetric(
                      label: 'تحصيلات الفترة',
                      value: totals == null
                          ? const SizedBox(
                              width: 72,
                              child: LinearProgressIndicator(minHeight: 2),
                            )
                          : MoneyText(totals.collections),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تصدير كل الأقسام بالعربية',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'اختر المعاينة داخل النظام أو التنزيل. المعاينة لا تنزّل الملف تلقائياً.',
                      ),
                      const SizedBox(height: 16),
                      _ReportFormatCard(
                        label: S.csv,
                        icon: Icons.table_rows_outlined,
                        enabled: canExport,
                        type: ReportFileType.csv,
                        branding: _branding(),
                      ),
                      const SizedBox(height: 10),
                      _ReportFormatCard(
                        label: S.excel,
                        icon: Icons.grid_on_outlined,
                        enabled: canExport,
                        type: ReportFileType.excel,
                        branding: _branding(),
                      ),
                      const SizedBox(height: 10),
                      _ReportFormatCard(
                        label: 'PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        enabled: canExport,
                        type: ReportFileType.pdf,
                        branding: _branding(),
                      ),
                      if (!canExport) ...[
                        const SizedBox(height: 10),
                        const Text(S.noPermission),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportFormatCard extends StatefulWidget {
  const _ReportFormatCard({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.type,
    required this.branding,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final ReportFileType type;
  final ReportBranding branding;

  @override
  State<_ReportFormatCard> createState() => _ReportFormatCardState();
}

class _ReportFormatCardState extends State<_ReportFormatCard> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      sl<AppAlertCubit>().error(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    await _run(() async {
      final service = sl<ReportExportService>();
      if (widget.type == ReportFileType.pdf) {
        final bytes = await service.buildPdfBytes(branding: widget.branding);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _PdfPreviewPage(title: widget.label, bytes: bytes),
          ),
        );
        return;
      }
      final sections = await service.sections(range: widget.branding.range);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('${S.reportPreview} — ${widget.label}'),
            content: SizedBox(
              width: 720,
              height: 520,
              child: ListView(
                children: [
                  for (final row in widget.branding.coverRows())
                    Text('${row.first}: ${row.last}'),
                  const Divider(),
                  for (final entry in sections.entries) ...[
                    Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          for (final header in entry.value.first)
                            DataColumn(label: Text(header.toString())),
                        ],
                        rows: [
                          for (final row in entry.value.skip(1).take(40))
                            DataRow(
                              cells: [
                                for (final cell in row)
                                  DataCell(Text(cell.toString())),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(S.close),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _download() async {
    await _run(() async {
      await sl<ReportExportService>().download(
        widget.type,
        branding: widget.branding,
      );
      sl<AppAlertCubit>().success('تم تنزيل ملف ${widget.label}.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ReportBusyBarrier(
      busy: _busy,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(widget.icon),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.label)),
              TextButton.icon(
                onPressed: widget.enabled && !_busy ? _preview : null,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text(S.preview),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: widget.enabled && !_busy ? _download : null,
                icon: const Icon(Icons.download_outlined),
                label: const Text(S.downloadFile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfPreviewPage extends StatelessWidget {
  const _PdfPreviewPage({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${S.reportPreview} — $title')),
      body: PdfPreview(
        build: (_) async => bytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        useActions: false,
        pdfFileName: 'مجموعة-النعماني.pdf',
      ),
    );
  }
}
