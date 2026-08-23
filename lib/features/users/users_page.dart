import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/services/user_admin_service.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';
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
      child: StreamBuilder<List<User>>(
        stream: sl<UserAdminService>().watch(),
        builder: (context, snap) {
          final items = snap.data ?? const <User>[];
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

  static Future<void> _edit(BuildContext context, User? user) async {
    final username = TextEditingController(text: user?.username ?? '');
    final display = TextEditingController(text: user?.displayName ?? '');
    final password = TextEditingController();
    var role = user?.roleId ?? AppRole.cashier;
    var active = user?.isActive ?? true;
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
            builder: (ctx, setS) => SingleChildScrollView(
              child: Column(
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
                      SearchableOption(value: AppRole.viewer, label: 'عرض فقط'),
                    ],
                    onChanged: (v) => setS(() => role = v ?? role),
                  ),
                  SwitchListTile(
                    title: const Text(S.active),
                    value: active,
                    onChanged: (v) => setS(() => active = v),
                  ),
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
                                session: context
                                    .read<AuthCubit>()
                                    .state
                                    .session!,
                                id: user?.id,
                                username: username.text,
                                displayName: display.text,
                                password: password.text.isEmpty
                                    ? null
                                    : password.text,
                                roleId: role,
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
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
