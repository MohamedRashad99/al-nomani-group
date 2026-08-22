import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final config = sl<AppConfig>();
    return AppScaffold(
      title: S.settings,
      child: ListView(
        children: [
          ListTile(
            title: const Text('إصدار التطبيق'),
            subtitle: Text(config.appVersion),
          ),
          ListTile(
            title: const Text('إصدار قاعدة البيانات'),
            subtitle: Text('${config.databaseVersion}'),
          ),
          ListTile(
            title: const Text('بروتوكول المزامنة'),
            subtitle: Text('${config.syncProtocolVersion}'),
          ),
          ListTile(
            title: const Text('بيئة التشغيل'),
            subtitle: Text(config.environment),
          ),
          FutureBuilder(
            future: sl<AppDatabase>().select(sl<AppDatabase>().settings).get(),
            builder: (context, snap) {
              final rows = snap.data ?? const <Setting>[];
              return Column(
                children: [
                  for (final s in rows)
                    ListTile(title: Text(s.key), subtitle: Text(s.value)),
                  ListTile(
                    title: const Text('أيام المزامنة'),
                    trailing: FilledButton.tonal(
                      onPressed: () async {
                        final days = sl<AppConfig>().syncIntervalDays;
                        await sl<AppDatabase>()
                            .into(sl<AppDatabase>().settings)
                            .insertOnConflictUpdate(
                              SettingsCompanion.insert(
                                key: SyncConfigKeys.syncIntervalDays,
                                value: '$days',
                                updatedAt: DateTime.now().toUtc(),
                              ),
                            );
                      },
                      child: Text('${config.syncIntervalDays}'),
                    ),
                  ),
                ],
              );
            },
          ),
          ListTile(
            title: const Text(S.logout),
            leading: const Icon(Icons.logout),
            onTap: () => context.read<AuthCubit>().logout(),
          ),
        ],
      ),
    );
  }
}
