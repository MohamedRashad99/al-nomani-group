import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../domain/services/user_admin_service.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: S.users,
      fab: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      child: FutureBuilder<List<User>>(
        future: sl<UserAdminService>().list(),
        builder: (context, snap) {
          final items = snap.data ?? const <User>[];
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final u in items)
                ListTile(
                  title: Text(u.displayName),
                  subtitle: Text(
                    '${u.username} • ${u.roleId} • ${u.isActive ? S.active : S.inactive}',
                  ),
                  onTap: () => _edit(u),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(User? user) async {
    final username = TextEditingController(text: user?.username ?? '');
    final display = TextEditingController(text: user?.displayName ?? '');
    final password = TextEditingController();
    var role = user?.roleId ?? AppRole.cashier;
    var active = user?.isActive ?? true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: username,
                decoration: const InputDecoration(labelText: S.username),
              ),
              TextField(
                controller: display,
                decoration: const InputDecoration(labelText: 'الاسم الظاهر'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: S.password),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                items: const [
                  DropdownMenuItem(
                    value: AppRole.admin,
                    child: Text('مدير النظام'),
                  ),
                  DropdownMenuItem(value: AppRole.manager, child: Text('مدير')),
                  DropdownMenuItem(
                    value: AppRole.cashier,
                    child: Text('أمين صندوق'),
                  ),
                  DropdownMenuItem(
                    value: AppRole.viewer,
                    child: Text('عرض فقط'),
                  ),
                ],
                onChanged: (v) => setS(() => role = v ?? role),
              ),
              SwitchListTile(
                title: const Text(S.active),
                value: active,
                onChanged: (v) => setS(() => active = v),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(S.save),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await sl<UserAdminService>().upsert(
      session: context.read<AuthCubit>().state.session!,
      id: user?.id,
      username: username.text,
      displayName: display.text,
      password: password.text.isEmpty ? null : password.text,
      roleId: role,
      isActive: active,
    );
    if (mounted) setState(() {});
  }
}
