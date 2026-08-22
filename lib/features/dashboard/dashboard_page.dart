import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/breakpoints.dart';
import '../../domain/services/dashboard_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/money_text.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.dashboard,
      child: FutureBuilder<DashboardSnapshot>(
        future: sl<DashboardService>().load(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final phone = Breakpoints.isPhone(context);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(S.demoBanner, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: phone ? 2 : 4,
                childAspectRatio: phone ? 1.2 : 1.6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  StatCard(label: S.todaySales, child: MoneyText(d.todaySales)),
                  StatCard(
                    label: S.outstandingDebt,
                    child: MoneyText(d.outstandingDebt),
                  ),
                  StatCard(
                    label: S.todayCollections,
                    child: MoneyText(d.todayCollections),
                  ),
                  StatCard(label: S.lowStock, child: Text('${d.lowStock}')),
                  StatCard(
                    label: S.weeklySales,
                    child: MoneyText(d.weeklySales),
                  ),
                  StatCard(
                    label: S.monthlySales,
                    child: MoneyText(d.monthlySales),
                  ),
                  StatCard(
                    label: S.monthlyCollections,
                    child: MoneyText(d.monthlyCollections),
                  ),
                  StatCard(label: S.outOfStock, child: Text('${d.outOfStock}')),
                  StatCard(
                    label: S.totalProducts,
                    child: Text('${d.totalProducts}'),
                  ),
                  StatCard(
                    label: S.customersWithDebt,
                    child: Text('${d.customersWithDebt}'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                S.recentSales,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...d.recentSales.map(
                (s) => ListTile(
                  title: Text(s.saleNumber),
                  subtitle: Text(s.soldAt.toLocal().toString()),
                  trailing: MoneyText(Money.parse(s.subtotal)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                S.recentCollections,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...d.recentCollections.map(
                (c) => ListTile(
                  title: MoneyText(Money.parse(c.amount)),
                  subtitle: Text(c.collectedAt.toLocal().toString()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
