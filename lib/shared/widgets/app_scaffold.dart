import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/breakpoints.dart';
import '../../features/auth/auth_cubit.dart';
import 'brand.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.fab,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final Widget? fab;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final form = Breakpoints.of(context);
    final session = context.watch<AuthCubit>().state.session;
    final items = _items(session?.permissions ?? {});

    if (Breakpoints.isPhone(context)) {
      final primary = _primaryItems(items);
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              const BrandMark(size: 34, showText: false),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          actions: actions,
        ),
        drawer: _AppDrawer(items: items, sessionName: session?.displayName),
        body: SafeArea(child: child),
        floatingActionButton: fab,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selected(context, primary),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) => context.go(primary[index].path),
          destinations: [
            for (final item in primary)
              NavigationDestination(
                selectedIcon: Icon(item.selectedIcon),
                icon: Icon(item.icon),
                label: item.shortLabel,
              ),
          ],
        ),
      );
    }

    final expanded = form != AppFormFactor.tablet;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: expanded ? 264 : 88,
            color: AppColors.darkGreen,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      expanded ? 20 : 14,
                      20,
                      expanded ? 20 : 14,
                      22,
                    ),
                    child: BrandMark(size: 48, showText: expanded, light: true),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        for (final item in items)
                          _RailItem(
                            item: item,
                            expanded: expanded,
                            selected: _matches(context, item.path),
                          ),
                      ],
                    ),
                  ),
                  if (session != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: expanded
                          ? ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              leading: const CircleAvatar(
                                backgroundColor: Colors.white24,
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                              title: Text(
                                session.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: const Text(
                                'الحساب الحالي',
                                style: TextStyle(color: Colors.white60),
                              ),
                              trailing: IconButton(
                                tooltip: S.logout,
                                onPressed: () =>
                                    context.read<AuthCubit>().logout(),
                                icon: const Icon(
                                  Icons.logout,
                                  color: Colors.white70,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: S.logout,
                              onPressed: () =>
                                  context.read<AuthCubit>().logout(),
                              icon: const Icon(
                                Icons.logout,
                                color: Colors.white70,
                              ),
                            ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: Text(
                      sl<AppConfig>().visibleBuildLabel,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: expanded ? .72 : .55),
                        fontSize: expanded ? 11 : 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: fab,
    );
  }

  List<_NavItem> _primaryItems(List<_NavItem> all) {
    const preferred = ['/dashboard', '/sales', '/customers', '/products'];
    final primary = <_NavItem>[];
    for (final path in preferred) {
      for (final item in all) {
        if (item.path == path) primary.add(item);
      }
    }
    for (final item in all) {
      if (primary.length >= 4) break;
      if (primary.any((entry) => entry.path == item.path)) continue;
      primary.add(item);
    }
    return [
      ...primary.take(4),
      const _NavItem(
        '/more',
        S.more,
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
        shortLabel: S.more,
      ),
    ];
  }

  int _selected(BuildContext context, List<_NavItem> items) {
    final index = items.indexWhere((item) => _matches(context, item.path));
    return index < 0 ? items.length - 1 : index;
  }

  bool _matches(BuildContext context, String path) {
    final location = GoRouterState.of(context).uri.path;
    if (path == '/dashboard') return location == path;
    return location == path || location.startsWith('$path/');
  }

  List<_NavItem> _items(Set<String> permissions) => [
    const _NavItem(
      '/dashboard',
      S.dashboard,
      Icons.dashboard_outlined,
      Icons.dashboard_rounded,
      shortLabel: 'الرئيسية',
    ),
    if (permissions.contains(AppPermission.salesView))
      const _NavItem(
        '/sales',
        S.sales,
        Icons.point_of_sale_outlined,
        Icons.point_of_sale_rounded,
      ),
    if (permissions.contains(AppPermission.customersView))
      const _NavItem(
        '/customers',
        S.customers,
        Icons.people_outline,
        Icons.people_rounded,
      ),
    if (permissions.contains(AppPermission.outstandingView))
      const _NavItem(
        '/outstanding',
        S.outstanding,
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet_rounded,
        shortLabel: 'الآجلة',
      ),
    if (permissions.contains(AppPermission.productsView))
      const _NavItem(
        '/products',
        S.products,
        Icons.inventory_2_outlined,
        Icons.inventory_2_rounded,
      ),
    if (permissions.contains(AppPermission.inventoryView))
      const _NavItem(
        '/inventory',
        S.inventory,
        Icons.warehouse_outlined,
        Icons.warehouse_rounded,
      ),
    if (permissions.contains(AppPermission.collectionsView))
      const _NavItem(
        '/collections',
        S.collections,
        Icons.payments_outlined,
        Icons.payments_rounded,
      ),
    if (permissions.contains(AppPermission.reportsView))
      const _NavItem(
        '/reports',
        S.reports,
        Icons.analytics_outlined,
        Icons.analytics_rounded,
      ),
    if (permissions.contains(AppPermission.usersView))
      const _NavItem(
        '/users',
        S.users,
        Icons.manage_accounts_outlined,
        Icons.manage_accounts_rounded,
      ),
    if (permissions.contains(AppPermission.backupView))
      const _NavItem(
        '/backup',
        S.backup,
        Icons.cloud_sync_outlined,
        Icons.cloud_sync_rounded,
        shortLabel: 'المزامنة',
      ),
    if (permissions.contains(AppPermission.settingsView))
      const _NavItem(
        '/settings',
        S.settings,
        Icons.settings_outlined,
        Icons.settings_rounded,
      ),
  ];
}

class _NavItem {
  const _NavItem(
    this.path,
    this.label,
    this.icon,
    this.selectedIcon, {
    String? shortLabel,
  }) : shortLabelOverride = shortLabel;

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? shortLabelOverride;
  String get shortLabel => shortLabelOverride ?? label;
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.expanded,
    required this.selected,
  });

  final _NavItem item;
  final bool expanded;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: .15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.go(item.path),
          child: SizedBox(
            height: 50,
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (expanded) const SizedBox(width: 14),
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  color: selected ? Colors.white : Colors.white70,
                ),
                if (expanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.items, this.sessionName});

  final List<_NavItem> items;
  final String? sessionName;

  @override
  Widget build(BuildContext context) {
    final current = GoRouterState.of(context).uri.path;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: BrandMark(size: 52),
            ),
            if (sessionName != null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE7F3E6),
                  child: Icon(Icons.person, color: AppColors.darkGreen),
                ),
                title: Text(
                  sessionName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('القائمة الجانبية'),
              ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final item in items)
                    ListTile(
                      selected:
                          current == item.path ||
                          current.startsWith('${item.path}/'),
                      selectedColor: AppColors.darkGreen,
                      selectedTileColor: const Color(0xFFE7F3E6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(item.path);
                      },
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text(S.logout),
              onTap: () => context.read<AuthCubit>().logout(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                sl<AppConfig>().visibleBuildLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
