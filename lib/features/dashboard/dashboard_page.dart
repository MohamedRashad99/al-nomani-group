import 'dart:math' as math;

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/arabic_format.dart';
import '../../core/utils/breakpoints.dart';
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
  late final Stream<DashboardSnapshot> _stream = sl<DashboardService>().watch();
  late Future<SyncHealth> _health = sl<SyncEngine>().health();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.dashboard,
      actions: [
        IconButton(
          tooltip: 'تحديث الحالة',
          onPressed: () => setState(() => _health = sl<SyncEngine>().health()),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: StreamBuilder<DashboardSnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const BrandedLoading(message: 'نجهّز ملخص أعمالك');
          }
          return FutureBuilder<SyncHealth>(
            future: _health,
            builder: (context, healthSnap) {
              final health = healthSnap.data;
              if (health == null) {
                return const BrandedLoading(message: 'نجهّز ملخص أعمالك');
              }
              return _DashboardBody(
                data: _DashboardData(snapshot.data!, health),
              );
            },
          );
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

class _DashboardBody extends StatefulWidget {
  const _DashboardBody({required this.data});

  final _DashboardData data;

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Widget _reveal({required int order, required Widget child}) {
    final start = (order * 0.07).clamp(0.0, 0.62);
    final end = (start + 0.38).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _motion,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.data.snapshot;
    final session = context.watch<AuthCubit>().state.session;
    final permissions = session?.permissions ?? const <String>{};
    final width = MediaQuery.sizeOf(context).width;
    final phone = Breakpoints.isPhone(context);
    final horizontalPadding = phone
        ? 12.0
        : width >= 1200
        ? 32.0
        : 16.0;
    final innerWidth = width - (horizontalPadding * 2);
    final kpiColumns = phone
        ? (innerWidth < 340 ? 1 : 2)
        : (innerWidth / 285).floor().clamp(2, 4);

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
            child: _reveal(
              order: 0,
              child: _WelcomeHeader(
                name: session?.displayName ?? '',
                health: widget.data.health,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverToBoxAdapter(
            child: _KpiGrid(
              columns: kpiColumns,
              children: [
                _reveal(
                  order: 1,
                  child: _KpiCard(
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
                ),
                _reveal(
                  order: 2,
                  child: _KpiCard(
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
                ),
                _reveal(
                  order: 3,
                  child: _KpiCard(
                  label: S.todayCollections,
                  value: MoneyText(
                    dashboard.todayCollections,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF1565C0),
                  helper: 'تحصيلات مسجلة اليوم',
                  ),
                ),
                _reveal(
                  order: 4,
                  child: _KpiCard(
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
                ),
              ],
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
            child: _reveal(
              order: 5,
              child: _QuickActions(permissions: permissions),
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
            child: _reveal(
              order: 6,
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
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _reveal(
              order: 7,
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
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            28,
          ),
          sliver: SliverToBoxAdapter(
            child: _reveal(
              order: 8,
              child: _RecentActivity(snapshot: dashboard),
            ),
          ),
        ),
      ],
    );
  }
}

class _WelcomeHeader extends StatefulWidget {
  const _WelcomeHeader({required this.name, required this.health});

  final String name;
  final SyncHealth health;

  @override
  State<_WelcomeHeader> createState() => _WelcomeHeaderState();
}

class _WelcomeHeaderState extends State<_WelcomeHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'صباح الخير'
        : hour < 18
        ? 'مساء الخير'
        : 'أهلاً بك';
    final health = widget.health;
    final name = widget.name;
    final healthy =
        health.failed == 0 &&
        health.backupFailed == 0 &&
        health.backupConfigured != false;
    final phone = Breakpoints.isPhone(context);
    final statusChip = Tooltip(
      message: health.backupLastError ?? health.statusAr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              healthy ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              size: 16,
              color: healthy ? const Color(0xFFB9F6CA) : Colors.orange[100],
            ),
            const SizedBox(width: 6),
            Text(
              healthy ? 'البيانات محمية' : health.statusAr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting، $name',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: phone ? 18 : null,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'إليك ملخص أداء مجموعة النعماني اليوم',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
            fontSize: phone ? 12 : null,
          ),
        ),
      ],
    );
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        final shift = _shimmer.value;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(phone ? 14 : 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                AppColors.darkGreen,
                Color(0xFF3F8F45),
                Color(0xFF2E6B33),
              ],
              begin: Alignment(-1 + shift * 2, -1),
              end: Alignment(1 - shift * 2, 1),
            ),
            borderRadius: BorderRadius.circular(phone ? 18 : 24),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkGreen.withValues(alpha: .18 + shift * .08),
                blurRadius: 20 + shift * 10,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      },
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandMark(size: 42, showText: false),
                    const SizedBox(width: 10),
                    Expanded(child: titleBlock),
                  ],
                ),
                const SizedBox(height: 10),
                statusChip,
              ],
            )
          : Row(
              children: [
                const BrandMark(size: 58, showText: false),
                const SizedBox(width: 16),
                Expanded(child: titleBlock),
                const SizedBox(width: 10),
                statusChip,
              ],
            ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
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
    final phone = Breakpoints.isPhone(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(phone ? 10 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(phone ? 6 : 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: phone ? 18 : 20, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: phone ? 12 : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(fit: BoxFit.scaleDown, child: value),
            ),
            const SizedBox(height: 6),
            Text(
              helper,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.muted,
                fontSize: phone ? 10 : null,
              ),
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
        const _Action(
          'بيع جديد',
          '/sales/new',
          Icons.add_shopping_cart_rounded,
        ),
      if (permissions.contains(AppPermission.collectionsCreate))
        const _Action('تسجيل تحصيل', '/collections', Icons.payments_rounded),
      if (permissions.contains(AppPermission.inventoryAdjust))
        const _Action('تسوية المخزون', '/inventory', Icons.inventory_rounded),
      if (permissions.contains(AppPermission.customersCreate))
        const _Action(
          'عميل جديد',
          '/customers',
          Icons.person_add_alt_1_rounded,
        ),
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
                icon: Icon(action.icon, size: 19,color: AppColors.card),
                label: Text(action.label, style: const TextStyle(color: AppColors.card)),
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
              children: [
                for (final point in snapshot.salesTrend)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ArabicFormat.day(point.date),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ),
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
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: AppColors.orange),
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
                      backgroundColor:
                          Quantity.parse(product.currentStock).isZero
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
                              style: const TextStyle(
                                color: AppColors.darkGreen,
                              ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${sale.saleNumber} • ${ArabicFormat.dateTime(sale.soldAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      ArabicFormat.dateTime(collection.collectedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
    final phone = Breakpoints.isPhone(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null)
          Text(
            subtitle!,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
          ),
      ],
    );
    return Card(
      child: Padding(
        padding: EdgeInsets.all(phone ? 12 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phone && action != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: action,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: heading),
                  ?action,
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
