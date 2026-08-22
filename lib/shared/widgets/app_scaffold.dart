import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/breakpoints.dart';
import '../../features/auth/auth_cubit.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.fab,
  });

  final String title;
  final Widget child;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final form = Breakpoints.of(context);
    final session = context.watch<AuthCubit>().state.session;
    final items = _items(session?.permissions ?? {});

    if (form == AppFormFactor.phone) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        drawer: _Drawer(items: items),
        body: SafeArea(child: child),
        floatingActionButton: fab,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selected(context, items.take(4).toList()),
          onDestinationSelected: (i) => context.go(items[i].path),
          destinations: [
            for (final item in items.take(4))
              NavigationDestination(icon: Icon(item.icon), label: item.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: form != AppFormFactor.tablet,
            selectedIndex: _selected(context, items),
            onDestinationSelected: (i) => context.go(items[i].path),
            leading: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                S.appName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.darkGreen),
              ),
            ),
            destinations: [
              for (final item in items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                AppBar(title: Text(title), automaticallyImplyLeading: false),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: fab,
    );
  }

  int _selected(BuildContext context, List<_NavItem> items) {
    final loc = GoRouterState.of(context).uri.path;
    final index = items.indexWhere((e) => loc.startsWith(e.path));
    return index < 0 ? 0 : index;
  }

  List<_NavItem> _items(Set<String> perms) {
    return [
      if (true)
        const _NavItem('/dashboard', S.dashboard, Icons.dashboard_outlined),
      if (perms.contains(AppPermission.productsView))
        const _NavItem('/products', S.products, Icons.inventory_2_outlined),
      if (perms.contains(AppPermission.inventoryView))
        const _NavItem('/inventory', S.inventory, Icons.warehouse_outlined),
      if (perms.contains(AppPermission.salesView))
        const _NavItem('/sales', S.sales, Icons.point_of_sale_outlined),
      if (perms.contains(AppPermission.customersView))
        const _NavItem('/customers', S.customers, Icons.people_outline),
      if (perms.contains(AppPermission.collectionsView))
        const _NavItem('/collections', S.collections, Icons.payments_outlined),
      if (perms.contains(AppPermission.reportsView))
        const _NavItem('/reports', S.reports, Icons.assessment_outlined),
      if (perms.contains(AppPermission.usersView))
        const _NavItem('/users', S.users, Icons.manage_accounts_outlined),
      if (perms.contains(AppPermission.backupView))
        const _NavItem('/backup', S.backup, Icons.cloud_sync_outlined),
      const _NavItem('/settings', S.settings, Icons.settings_outlined),
    ];
  }
}

class _NavItem {
  final String path;
  final String label;
  final IconData icon;
  const _NavItem(this.path, this.label, this.icon);
}

class _Drawer extends StatelessWidget {
  const _Drawer({required this.items});
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text(S.appName),
              subtitle: Text(S.appSubtitle),
            ),
            for (final item in items)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                minLeadingWidth: 24,
                onTap: () {
                  Navigator.pop(context);
                  context.go(item.path);
                },
              ),
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
