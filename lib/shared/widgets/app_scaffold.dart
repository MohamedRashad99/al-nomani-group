import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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

    if (form == AppFormFactor.phone) {
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
        drawer: _AppDrawer(items: items),
        body: SafeArea(child: child),
        floatingActionButton: fab,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selected(context, primary),
          onDestinationSelected: (index) => context.go(primary[index].path),
          destinations: [
            for (final item in primary)
              NavigationDestination(
                selectedIcon: Icon(item.selectedIcon),
                icon: Icon(item.icon),
                label: item.label,
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
    final preferred = ['/dashboard', '/sales', '/customers', '/inventory'];
    final primary = [
      for (final path in preferred) ...all.where((item) => item.path == path),
    ];
    return [
      ...primary.take(4),
      const _NavItem(
        '/more',
        S.more,
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
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
  const _NavItem(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
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
  const _AppDrawer({required this.items});

  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    final current = GoRouterState.of(context).uri.path;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: BrandMark(size: 52),
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
          ],
        ),
      ),
    );
  }
}
