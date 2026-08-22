import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final permissions =
        context.watch<AuthCubit>().state.session?.permissions ?? const {};
    final modules = [
      if (permissions.contains(AppPermission.productsCreate) ||
          permissions.contains(AppPermission.customersCreate) ||
          permissions.contains(AppPermission.inventoryCreate))
        const _Module(
          'استيراد البيانات',
          '/import',
          Icons.upload_file_outlined,
        ),
      if (permissions.contains(AppPermission.inventoryView))
        const _Module(S.inventory, '/inventory', Icons.warehouse_outlined),
      if (permissions.contains(AppPermission.collectionsView))
        const _Module(S.collections, '/collections', Icons.payments_outlined),
      if (permissions.contains(AppPermission.outstandingView))
        const _Module(
          S.outstanding,
          '/outstanding',
          Icons.account_balance_wallet_outlined,
        ),
      if (permissions.contains(AppPermission.reportsView))
        const _Module(S.reports, '/reports', Icons.analytics_outlined),
      if (permissions.contains(AppPermission.usersView))
        const _Module(S.users, '/users', Icons.manage_accounts_outlined),
      if (permissions.contains(AppPermission.backupView))
        const _Module(S.backup, '/backup', Icons.cloud_sync_outlined),
      if (permissions.contains(AppPermission.settingsView))
        const _Module(S.settings, '/settings', Icons.settings_outlined),
    ];

    return AppScaffold(
      title: S.more,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 132,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: modules.length,
        itemBuilder: (context, index) {
          final module = modules[index];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.go(module.path),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(module.icon, size: 30),
                    Text(
                      module.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Module {
  const _Module(this.label, this.path, this.icon);

  final String label;
  final String path;
  final IconData icon;
}
