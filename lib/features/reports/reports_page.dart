import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../domain/services/dashboard_service.dart';
import '../../domain/services/report_export_service.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/money_text.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final canExport =
        context.watch<AuthCubit>().state.session?.can(
          AppPermission.reportsExport,
        ) ==
        true;
    return AppScaffold(
      title: S.reports,
      child: StreamBuilder<DashboardSnapshot>(
        stream: sl<DashboardService>().watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const BrandedLoading();
          final dashboard = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 280,
                    child: StatCard(
                      label: S.monthlySales,
                      child: MoneyText(dashboard.monthlySales),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: StatCard(
                      label: S.outstandingDebt,
                      child: MoneyText(dashboard.outstandingDebt),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: StatCard(
                      label: S.monthlyCollections,
                      child: MoneyText(dashboard.monthlyCollections),
                    ),
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
                        'تصدير تقرير المبيعات',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'نزّل ملفاً حقيقياً إلى جهازك للاحتفاظ به أو مشاركته.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ExportButton(
                            label: S.csv,
                            icon: Icons.table_rows_outlined,
                            enabled: canExport,
                            type: ReportFileType.csv,
                          ),
                          _ExportButton(
                            label: S.excel,
                            icon: Icons.grid_on_outlined,
                            enabled: canExport,
                            type: ReportFileType.excel,
                          ),
                          _ExportButton(
                            label: 'PDF',
                            icon: Icons.picture_as_pdf_outlined,
                            enabled: canExport,
                            type: ReportFileType.pdf,
                          ),
                        ],
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

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.type,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final ReportFileType type;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: !enabled
          ? null
          : () async {
              try {
                await sl<ReportExportService>().exportSales(type);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم تنزيل ملف $label.')),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              }
            },
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
