import 'package:al_nomani_shared/al_nomani_shared.dart';
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
import '../../shared/widgets/google_sheet_link_button.dart';
import '../../shared/widgets/searchable_select.dart';

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

  bool _syncingNow = false;

  Future<_SyncSettings> _load() async {
    final engine = sl<SyncEngine>();
    return _SyncSettings(
      intervalDays: _normalizeInterval(await engine.intervalDays()),
      mode: await engine.mode(),
    );
  }

  int _normalizeInterval(int days) {
    if (days == 1 || days == 2 || days == 5) return days;
    return days <= 2 ? 2 : 5;
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
                      SearchableSelectField<SyncMode>(
                        label: 'وضع المزامنة',
                        required: true,
                        allowCustom: false,
                        enabled: canUpdate,
                        value: settings.mode,
                        options: const [
                          SearchableOption(
                            value: SyncMode.scheduled,
                            label: 'مجدولة',
                          ),
                          SearchableOption(
                            value: SyncMode.nearRealtime,
                            label: 'بعد كل عملية عند توفر الإنترنت',
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _save(mode: value, days: settings.intervalDays);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      SearchableSelectField<int>(
                        label: 'الفاصل بين المزامنات',
                        required: true,
                        allowCustom: false,
                        enabled: canUpdate,
                        value: settings.intervalDays,
                        options: const [
                          SearchableOption(value: 1, label: 'كل يوم'),
                          SearchableOption(value: 2, label: 'كل يومين'),
                          SearchableOption(value: 5, label: 'كل ٥ أيام'),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _save(mode: settings.mode, days: value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(S.firebaseImmediateHint),
                      const SizedBox(height: 12),
                      GoogleSheetLinkButton(url: config.googleSheetUrl),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _syncingNow ? null : _syncNow,
                        child: _syncingNow
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(S.syncNow),
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
                      trailing: Text(config.visibleBuildLabel),
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
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: SyncConfigKeys.syncMode,
              value: mode.name,
              updatedAt: now,
            ),
          );
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
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

  Future<void> _syncNow() async {
    setState(() => _syncingNow = true);
    try {
      await sl<SyncEngine>().syncNow(force: true);
      if (!mounted) return;
      final health = await sl<SyncEngine>().health();
      if (!mounted) return;
      final failed = health.failed > 0 || health.backupFailed > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed
                ? health.backupLastError ??
                      health.lastError ??
                      'اكتملت المحاولة مع أخطاء.'
                : S.syncSuccess,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }
}

class _SyncSettings {
  const _SyncSettings({required this.intervalDays, required this.mode});

  final int intervalDays;
  final SyncMode mode;
}
