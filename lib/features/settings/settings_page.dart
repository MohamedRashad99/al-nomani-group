import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../../features/auth/auth_cubit.dart';
import '../../shared/widgets/app_scaffold.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<_SyncSettings> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SyncSettings> _load() async {
    final engine = sl<SyncEngine>();
    return _SyncSettings(
      intervalDays: await engine.intervalDays(),
      mode: await engine.mode(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = sl<AppConfig>();
    final canUpdate =
        context.watch<AuthCubit>().state.session?.can(
          AppPermission.settingsUpdate,
        ) ==
        true;
    return AppScaffold(
      title: S.settings,
      child: FutureBuilder<_SyncSettings>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final settings = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'إعدادات المزامنة',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<SyncMode>(
                        initialValue: settings.mode,
                        decoration: const InputDecoration(
                          labelText: 'وضع المزامنة',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: SyncMode.scheduled,
                            child: Text('مجدولة'),
                          ),
                          DropdownMenuItem(
                            value: SyncMode.nearRealtime,
                            child: Text('بعد كل عملية عند توفر الإنترنت'),
                          ),
                        ],
                        onChanged: !canUpdate
                            ? null
                            : (value) {
                                if (value != null) {
                                  _save(
                                    mode: value,
                                    days: settings.intervalDays,
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: settings.intervalDays,
                        decoration: const InputDecoration(
                          labelText: 'الفاصل بين المزامنات',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('كل يوم'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text('كل ٣ أيام'),
                          ),
                          DropdownMenuItem(
                            value: 5,
                            child: Text('كل ٥ أيام'),
                          ),
                          DropdownMenuItem(
                            value: 7,
                            child: Text('كل ٧ أيام'),
                          ),
                        ],
                        onChanged: !canUpdate
                            ? null
                            : (value) {
                                if (value != null) {
                                  _save(mode: settings.mode, days: value);
                                }
                              },
                      ),
                      if (!canUpdate) ...[
                        const SizedBox(height: 10),
                        const Text(S.noPermission),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('إصدار التطبيق'),
                      trailing: Text(config.appVersion),
                    ),
                    ListTile(
                      title: const Text('إصدار قاعدة البيانات'),
                      trailing: Text('${config.databaseVersion}'),
                    ),
                    ListTile(
                      title: const Text('بروتوكول المزامنة'),
                      trailing: Text('${config.syncProtocolVersion}'),
                    ),
                    ListTile(
                      title: const Text('بيئة التشغيل'),
                      trailing: Text(
                        config.isDevelopment ? 'تطوير واختبار' : 'إنتاج',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: const Text(S.logout),
                  leading: const Icon(Icons.logout),
                  onTap: () => context.read<AuthCubit>().logout(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save({required SyncMode mode, required int days}) async {
    final db = sl<AppDatabase>();
    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: SyncConfigKeys.syncMode,
          value: mode.name,
          updatedAt: now,
        ),
      );
      await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: SyncConfigKeys.syncIntervalDays,
          value: '$days',
          updatedAt: now,
        ),
      );
      for (final entry in {
        SyncConfigKeys.syncMode: mode.name,
        SyncConfigKeys.syncIntervalDays: '$days',
      }.entries) {
        await sl<SyncQueueRepository>().enqueue(
          entityType: SyncEntityType.setting,
          entityId: entry.key,
          operation: SyncOperationType.update,
          payload: {
            'id': entry.key,
            'key': entry.key,
            'value': entry.value,
            'updated_at': now.toIso8601String(),
          },
          operationId: newId(),
        );
      }
    });
    await sl<MetadataStore>().set(
      SyncConfigKeys.nextScheduledSyncAt,
      now.add(Duration(days: days)).toIso8601String(),
    );
    if (mode == SyncMode.nearRealtime) {
      await sl<SyncEngine>().syncNow(force: true);
    }
    if (mounted) {
      setState(() => _future = _load());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات.')));
    }
  }
}

class _SyncSettings {
  const _SyncSettings({required this.intervalDays, required this.mode});

  final int intervalDays;
  final SyncMode mode;
}
