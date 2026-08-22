import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../domain/services/dashboard_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.reports,
      child: FutureBuilder<DashboardSnapshot>(
        future: sl<DashboardService>().load(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                title: const Text(S.monthlySales),
                trailing: MoneyText(d.monthlySales),
              ),
              ListTile(
                title: const Text(S.outstandingDebt),
                trailing: MoneyText(d.outstandingDebt),
              ),
              ListTile(
                title: const Text(S.monthlyCollections),
                trailing: MoneyText(d.monthlyCollections),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final db = sl<AppDatabase>();
                  final sales = await db.select(db.sales).get();
                  final csv = StringBuffer(
                    'id,sale_number,subtotal,paid,remaining,sold_at\n',
                  );
                  for (final s in sales) {
                    csv.writeln(
                      '${s.id},${s.saleNumber},${s.subtotal},${s.paidAmount},${s.remainingAmount},${s.soldAt}',
                    );
                  }
                  await Clipboard.setData(ClipboardData(text: csv.toString()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم نسخ تقرير المبيعات CSV.'),
                      ),
                    );
                  }
                },
                child: const Text(S.export),
              ),
            ],
          );
        },
      ),
    );
  }
}
