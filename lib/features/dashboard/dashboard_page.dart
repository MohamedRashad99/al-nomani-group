import 'dart:math' as math;

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/dashboard_service.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/brand.dart';
import '../../shared/widgets/money_text.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final results = await Future.wait([
      sl<DashboardService>().load(),
      sl<SyncEngine>().health(),
    ]);
    return _DashboardData(
      results[0] as DashboardSnapshot,
      results[1] as SyncHealth,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.dashboard,
      actions: [
        IconButton(
          tooltip: 'تحديث البيانات',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const BrandedLoading(message: 'نجهّز ملخص أعمالك');
          }
          if (!snapshot.hasData) {
            return BrandedEmptyState(
              title: 'تعذر تحميل لوحة التحكم',
              message: 'بياناتك المحلية لم تتأثر. أعد المحاولة.',
              action: FilledButton(
                onPressed: _refresh,
                child: const Text(S.retry),
              ),
            );
          }
          return _DashboardBody(data: snapshot.data!);
        },
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData(this.snapshot, this.health);

  final DashboardSnapshot snapshot;
  final SyncHealth health;
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final _DashboardData data;

  @override
  Widget build(BuildContext context) {
    final dashboard = data.snapshot;
    final session = context.watch<AuthCubit>().state.session;
    final permissions = session?.permissions ?? const <String>{};
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width >= 1200 ? 32.0 : 16.0;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            12,
          ),
          sliver: SliverToBoxAdapter(
            child: _WelcomeHeader(
              name: session?.displayName ?? '',
              health: data.health,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 285,
              mainAxisExtent: 136,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildListDelegate([
              _KpiCard(
                label: S.todaySales,
                value: MoneyText(
                  dashboard.todaySales,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                icon: Icons.trending_up_rounded,
                color: AppColors.green,
                helper:
                    '${dashboard.todaySalesChangePercent >= 0 ? '+' : ''}${dashboard.todaySalesChangePercent.toStringAsFixed(0)}٪ عن أمس',
              ),
              _KpiCard(
                label: S.outstandingDebt,
                value: MoneyText(
                  dashboard.outstandingDebt,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                icon: Icons.account_balance_wallet_outlined,
                color: AppColors.orange,
                helper:
                    '${ArabicFormat.number(dashboard.customersWithDebt)} عميل',
              ),
              _KpiCard(
                label: S.todayCollections,
                value: MoneyText(
                  dashboard.todayCollections,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                icon: Icons.payments_outlined,
                color: const Color(0xFF1565C0),
                helper: 'تحصيلات مسجلة اليوم',
              ),
              _KpiCard(
                label: S.lowStock,
                value: Text(
                  ArabicFormat.number(
                    dashboard.lowStock + dashboard.outOfStock,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                icon: Icons.warning_amber_rounded,
                color: AppColors.danger,
                helper:
                    '${ArabicFormat.number(dashboard.outOfStock)} منتج نافد',
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _QuickActions(permissions: permissions),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trend = _TrendPanel(snapshot: dashboard);
                final debt = _DebtPanel(snapshot: dashboard);
                if (constraints.maxWidth < 850) {
                  return Column(
                    children: [trend, const SizedBox(height: 12), debt],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: trend),
                    const SizedBox(width: 12),
                    Expanded(child: debt),
                  ],
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final low = _LowStockPanel(snapshot: dashboard);
                final top = _RankingPanel(
                  title: S.topProducts,
                  items: dashboard.topProducts,
                  icon: Icons.emoji_events_outlined,
                );
                final customers = _RankingPanel(
                  title: S.topCustomers,
                  items: dashboard.topCustomers,
                  icon: Icons.groups_outlined,
                );
                if (constraints.maxWidth < 1050) {
                  return Column(
                    children: [
                      low,
                      const SizedBox(height: 12),
                      top,
                      const SizedBox(height: 12),
                      customers,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: low),
                    const SizedBox(width: 12),
                    Expanded(child: top),
                    const SizedBox(width: 12),
                    Expanded(child: customers),
                  ],
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            28,
          ),
          sliver: SliverToBoxAdapter(
            child: _RecentActivity(snapshot: dashboard),
          ),
        ),
      ],
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.name, required this.health});

  final String name;
  final SyncHealth health;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'صباح الخير'
        : hour < 18
        ? 'مساء الخير'
        : 'أهلاً بك';
    final healthy =
        health.failed == 0 &&
        health.backupFailed == 0 &&
        health.backupConfigured != false;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.darkGreen, Color(0xFF347B39)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkGreen.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const BrandMark(size: 58, showText: false),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting، $name',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'إليك ملخص أداء مجموعة النعماني اليوم',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: health.backupLastError ?? health.statusAr,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    healthy
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    size: 18,
                    color: healthy ? const Color(0xFFB9F6CA) : Colors.orange[100],
                  ),
                  const SizedBox(width: 7),
                  Text(
                    healthy ? 'البيانات محمية' : health.statusAr,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.helper,
  });

  final String label;
  final Widget value;
  final IconData icon;
  final Color color;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: value),
            const SizedBox(height: 2),
            Text(
              helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.permissions});

  final Set<String> permissions;

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (permissions.contains(AppPermission.salesCreate))
        const _Action('بيع جديد', '/sales/new', Icons.add_shopping_cart_rounded),
      if (permissions.contains(AppPermission.collectionsCreate))
        const _Action(
          'تسجيل تحصيل',
          '/collections',
          Icons.payments_rounded,
        ),
      if (permissions.contains(AppPermission.inventoryAdjust))
        const _Action(
          'تسوية المخزون',
          '/inventory',
          Icons.inventory_rounded,
        ),
      if (permissions.contains(AppPermission.customersCreate))
        const _Action('عميل جديد', '/customers', Icons.person_add_alt_1_rounded),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('إجراءات سريعة', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions)
              FilledButton.tonalIcon(
                onPressed: () => context.go(action.path),
                icon: Icon(action.icon, size: 19),
                label: Text(action.label),
              ),
          ],
        ),
      ],
    );
  }
}

class _Action {
  const _Action(this.label, this.path, this.icon);

  final String label;
  final String path;
  final IconData icon;
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'اتجاه المبيعات',
      subtitle: 'آخر ٧ أيام',
      action: TextButton(
        onPressed: () => context.go('/reports'),
        child: const Text('عرض التقارير'),
      ),
      child: SizedBox(
        height: 210,
        child: Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _TrendPainter(snapshot.salesTrend),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final point in snapshot.salesTrend)
                  Text(
                    ArabicFormat.day(point.date),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.points);

  final List<SalesTrendPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final values = points
        .map((point) => point.amount.minorUnits.toDouble())
        .toList();
    final maxValue = math.max(1.0, values.reduce(math.max));
    final line = Path();
    final fill = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : index * size.width / (values.length - 1);
      final y = size.height - (values[index] / maxValue) * (size.height - 20);
      if (index == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x5534A853), Color(0x0034A853)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.green
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _DebtPanel extends StatelessWidget {
  const _DebtPanel({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final collected = snapshot.monthlyCollections.minorUnits.toDouble();
    final debt = snapshot.outstandingDebt.minorUnits.toDouble();
    final ratio = collected + debt == 0 ? 0.0 : collected / (collected + debt);
    return _Panel(
      title: 'الديون والتحصيل',
      subtitle: 'ملخص الشهر الحالي',
      child: SizedBox(
        height: 210,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MoneyText(
              snapshot.outstandingDebt,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.orange,
              ),
            ),
            const Text('إجمالي الرصيد المستحق'),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 12,
                backgroundColor: const Color(0xFFFFE0B2),
                color: AppColors.green,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.green,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'تحصيلات الشهر',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                MoneyText(snapshot.monthlyCollections),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.go('/customers'),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('متابعة حسابات العملاء'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockPanel extends StatelessWidget {
  const _LowStockPanel({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'تنبيهات المخزون',
      subtitle: '${snapshot.lowStock + snapshot.outOfStock} تحتاج متابعة',
      action: IconButton(
        tooltip: 'فتح المخزون',
        onPressed: () => context.go('/inventory'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      child: snapshot.lowStockProducts.isEmpty
          ? const _CompactEmpty('المخزون ضمن الحدود الآمنة')
          : Column(
              children: [
                for (final product in snapshot.lowStockProducts)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Quantity.parse(product.currentStock).isZero
                          ? const Color(0xFFFFEBEE)
                          : const Color(0xFFFFF3E0),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: Quantity.parse(product.currentStock).isZero
                            ? AppColors.danger
                            : AppColors.orange,
                      ),
                    ),
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('الحد الأدنى ${product.minimumStock}'),
                    trailing: Text(
                      product.currentStock,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RankingPanel extends StatelessWidget {
  const _RankingPanel({
    required this.title,
    required this.items,
    required this.icon,
  });

  final String title;
  final List<DashboardRank> items;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: items.isEmpty
          ? const _CompactEmpty('ستظهر النتائج بعد تسجيل المبيعات')
          : Column(
              children: [
                for (var index = 0; index < items.length; index++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE8F5E9),
                      child: index == 0
                          ? Icon(icon, color: AppColors.green, size: 20)
                          : Text(
                              ArabicFormat.number(index + 1),
                              style: const TextStyle(color: AppColors.darkGreen),
                            ),
                    ),
                    title: Text(
                      items[index].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: items[index].secondary == null
                        ? null
                        : Text(
                            items[index].secondary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: MoneyText(items[index].amount),
                  ),
              ],
            ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sales = snapshot.recentSales;
    final collections = snapshot.recentCollections;
    return _Panel(
      title: 'آخر النشاطات',
      subtitle: 'المبيعات والتحصيلات المسجلة محلياً',
      action: TextButton(
        onPressed: () => context.go('/sales'),
        child: const Text('عرض الكل'),
      ),
      child: sales.isEmpty && collections.isEmpty
          ? const _CompactEmpty('لا توجد نشاطات مسجلة بعد')
          : Column(
              children: [
                for (final sale in sales.take(4))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE8F5E9),
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: AppColors.green,
                      ),
                    ),
                    title: Text(
                      snapshot.customerNames[sale.customerId] ??
                          sale.saleNumber,
                    ),
                    subtitle: Text(
                      '${sale.saleNumber} • ${ArabicFormat.dateTime(sale.soldAt)}',
                    ),
                    trailing: MoneyText(Money.parse(sale.subtotal)),
                    onTap: () => context.go('/sales/${sale.id}'),
                  ),
                for (final collection in collections.take(2))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE3F2FD),
                      child: Icon(
                        Icons.payments_outlined,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    title: Text(
                      snapshot.customerNames[collection.customerId] ??
                          'تحصيل عميل',
                    ),
                    subtitle: Text(
                      ArabicFormat.dateTime(collection.collectedAt),
                    ),
                    trailing: MoneyText(Money.parse(collection.amount)),
                  ),
              ],
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.green),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
