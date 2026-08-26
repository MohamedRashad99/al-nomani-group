import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/breakpoints.dart';
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
      if (permissions.contains(AppPermission.suppliersView))
        const _Module(S.suppliers, '/suppliers', Icons.local_shipping_outlined),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final phone = Breakpoints.isPhone(context);
          final columns = constraints.maxWidth < 360
              ? 1
              : constraints.maxWidth < 640
              ? 2
              : constraints.maxWidth < 980
              ? 3
              : 4;
          const gap = 12.0;
          final width =
              (constraints.maxWidth - 24 - (gap * (columns - 1))) / columns;
          return SingleChildScrollView(
            padding: EdgeInsets.all(phone ? 12 : 16),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final module in modules)
                  SizedBox(
                    width: width,
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => context.go(module.path),
                        child: Padding(
                          padding: EdgeInsets.all(phone ? 14 : 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(module.icon, size: phone ? 26 : 30),
                              SizedBox(height: phone ? 12 : 18),
                              Text(
                                module.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontSize: phone ? 15 : null),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
