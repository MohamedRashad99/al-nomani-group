import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/user_admin_service.dart';
import '../../domain/services/user_identity.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/destructive_action_guard.dart';
import '../../shared/widgets/searchable_select.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session!;
    return AppScaffold(
      title: S.users,
      fab: session.can(AppPermission.usersCreate)
          ? FloatingActionButton(
              onPressed: () => _edit(context, null),
              child: const Icon(Icons.add),
            )
          : null,
      child: StreamBuilder<List<AppUser>>(
        stream: sl<UserAdminService>().watch(),
        builder: (context, snap) {
          final items = UserIdentity.collapseVisible(
            snap.data ?? const <AppUser>[],
          );
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final u in items)
                ListTile(
                  title: Text(u.displayName),
                  subtitle: Text(
                    '${u.username} • ${_roleLabel(u.roleId)} • ${u.isActive ? S.active : S.inactive}',
                  ),
                  onTap: session.can(AppPermission.usersUpdate)
                      ? () => _edit(context, u)
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }

  static String _roleLabel(String role) => switch (role) {
    AppRole.admin => 'مدير النظام',
    AppRole.manager => 'مدير',
    AppRole.cashier => 'أمين صندوق',
    AppRole.viewer => 'عرض فقط',
    _ => 'غير محدد',
  };

  static const _groups = <(String, List<(String, String)>)>[
    (
      'العملاء',
      [
        (AppPermission.customersView, 'عرض العملاء'),
        (AppPermission.customersCreate, 'إضافة عميل'),
        (AppPermission.customersUpdate, 'تعديل عميل'),
        (AppPermission.customersDelete, 'حذف عميل'),
      ],
    ),
    (
      'المنتجات',
      [
        (AppPermission.productsView, 'عرض المنتجات'),
        (AppPermission.productsCreate, 'إضافة منتج'),
        (AppPermission.productsUpdate, 'تعديل منتج'),
        (AppPermission.productsDelete, 'حذف منتج'),
      ],
    ),
    (
      'المخزون',
      [
        (AppPermission.inventoryView, 'عرض المخزون'),
        (AppPermission.inventoryCreate, 'إضافة مخزون'),
        (AppPermission.inventoryRemove, 'خصم مخزون'),
        (AppPermission.inventoryAdjust, 'تعديل المخزون'),
      ],
    ),
    (
      'المبيعات',
      [
        (AppPermission.salesView, 'عرض المبيعات'),
        (AppPermission.salesCreate, 'إنشاء بيع'),
        (AppPermission.salesUpdate, 'تعديل بيع'),
        (AppPermission.salesCancel, 'إلغاء بيع'),
      ],
    ),
    (
      'المشتريات',
      [
        (AppPermission.purchasesView, 'عرض المشتريات'),
        (AppPermission.purchasesCreate, 'إنشاء شراء'),
        (AppPermission.purchasesUpdate, 'تعديل شراء'),
        (AppPermission.purchasesCancel, 'إلغاء شراء'),
      ],
    ),
    (
      'التقارير',
      [
        (AppPermission.reportsView, 'عرض التقارير'),
        (AppPermission.reportsFinancial, 'عرض التقارير المالية'),
        (AppPermission.reportsExport, 'تصدير / طباعة التقارير'),
      ],
    ),
    (
      'الحسابات',
      [
        (AppPermission.accountsView, 'عرض الحسابات'),
        (AppPermission.accountsCreate, 'إنشاء حركة'),
        (AppPermission.accountsUpdate, 'تعديل حركة'),
        (AppPermission.accountsReverse, 'عكس حركة'),
      ],
    ),
    (
      'المصروفات',
      [
        (AppPermission.expensesView, 'عرض المصروفات'),
        (AppPermission.expensesCreate, 'إضافة مصروف'),
        (AppPermission.expensesUpdate, 'تعديل مصروف'),
        (AppPermission.expensesDelete, 'حذف مصروف'),
      ],
    ),
  ];

  static Future<void> _edit(BuildContext context, AppUser? user) async {
    final session = context.read<AuthCubit>().state.session!;
    final username = TextEditingController(text: user?.username ?? '');
    final display = TextEditingController(text: user?.displayName ?? '');
    final password = TextEditingController();
    var role = user?.roleId ?? AppRole.cashier;
    var active = user?.isActive ?? true;
    var selected = RolePermissions.resolve(user?.roleId ?? role, user?.permissions);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var saving = false;
        String? error;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) {
              void applyRole(String next) {
                role = next;
                selected = RolePermissions.resolve(next);
              }

              void toggle(String permission, bool enabled) {
                selected = {...selected};
                if (enabled) {
                  selected.add(permission);
                  final view = AppPermission.viewOf[permission];
                  if (view != null) selected.add(view);
                } else {
                  selected.remove(permission);
                  if (!AppPermission.viewOf.containsKey(permission)) {
                    selected.removeWhere(
                      (code) => AppPermission.viewOf[code] == permission,
                    );
                  }
                }
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: username,
                      decoration: const InputDecoration(labelText: S.username),
                    ),
                    TextField(
                      controller: display,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الظاهر',
                      ),
                    ),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: S.password),
                    ),
                    SearchableSelectField<String>(
                      label: 'الدور',
                      required: true,
                      allowCustom: false,
                      value: role,
                      options: const [
                        SearchableOption(
                          value: AppRole.admin,
                          label: 'مدير النظام',
                        ),
                        SearchableOption(value: AppRole.manager, label: 'مدير'),
                        SearchableOption(
                          value: AppRole.cashier,
                          label: 'أمين صندوق',
                        ),
                        SearchableOption(
                          value: AppRole.viewer,
                          label: 'عرض فقط',
                        ),
                      ],
                      onChanged: (v) => setS(() => applyRole(v ?? role)),
                    ),
                    SwitchListTile(
                      title: const Text(S.active),
                      value: active,
                      onChanged: (v) => setS(() => active = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الصلاحيات',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    for (final group in _groups) ...[
                      const SizedBox(height: 8),
                      Text(
                        group.$1,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      for (final item in group.$2)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.$2),
                          value: selected.contains(item.$1),
                          onChanged: (value) =>
                              setS(() => toggle(item.$1, value)),
                        ),
                    ],
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              setS(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                await sl<UserAdminService>().upsert(
                                  session: session,
                                  id: user?.id,
                                  username: username.text,
                                  displayName: display.text,
                                  password: password.text.isEmpty
                                      ? null
                                      : password.text,
                                  roleId: role,
                                  permissions: selected.toList(),
                                  isActive: active,
                                );
                                await sl<SyncEngine>().maybeSyncAfterLocalWrite();
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                if (ctx.mounted) {
                                  setS(() {
                                    saving = false;
                                    error = e.toString();
                                  });
                                }
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(S.save),
                    ),
                    if (user != null && session.can(AppPermission.usersDisable))
                      TextButton(
                        onPressed: saving
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await DestructiveActionGuard.run(
                                  context: context,
                                  title: 'حذف المستخدم',
                                  message:
                                      'سيتم تعطيل ${user.displayName} وإخفاؤه من القائمة. لا يُحذف سجل المراجعة.',
                                  confirmLabel: 'حذف',
                                  successMessage: 'تم حذف المستخدم.',
                                  action: () async {
                                    await sl<UserAdminService>().delete(
                                      session,
                                      user.id,
                                    );
                                    await sl<SyncEngine>()
                                        .maybeSyncAfterLocalWrite();
                                  },
                                );
                              },
                        child: const Text('حذف المستخدم'),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
