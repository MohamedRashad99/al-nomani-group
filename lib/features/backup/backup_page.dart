import 'dart:convert';
import 'dart:typed_data';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/file_download.dart';
import '../../data/local/app_database.dart';
import '../../domain/services/conflict_resolution_service.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../auth/auth_cubit.dart';
import 'backup_cubit.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<BackupCubit>()..refresh(),
      child: const _BackupView(),
    );
  }
}

class _BackupView extends StatelessWidget {
  const _BackupView();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    return AppScaffold(
      title: S.backup,
      child: BlocBuilder<BackupCubit, BackupState>(
        builder: (context, state) {
          final h = state.health;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (h != null) ...[
                _tile(
                  'حالة البيانات',
                  h.statusAr,
                  color: h.failed > 0 ? AppColors.danger : AppColors.green,
                ),
                _tile(
                  S.lastSync,
                  h.lastSuccessfulSync?.toLocal().toString() ?? '—',
                ),
                _tile(
                  S.nextSync,
                  h.nextScheduledSync?.toLocal().toString() ?? '—',
                ),
                _tile(
                  S.lastFullBackup,
                  h.lastFullBackup?.toLocal().toString() ?? '—',
                ),
                _tile(S.pendingOps, '${h.pending}'),
                _tile(S.failedOps, '${h.failed}'),
                _tile(S.successOps, '${h.synced}'),
                _tile(
                  S.lastError,
                  (h.lastError == null || h.lastError!.isEmpty)
                      ? '—'
                      : h.lastError!,
                ),
                _tile(S.internetStatus, h.online ? S.online : S.offline),
                _tile(
                  'الخادم المركزي',
                  !h.serverReachable
                      ? 'غير متاح'
                      : h.serverAuthenticated
                      ? 'متصل والجلسة صالحة'
                      : 'متصل لكن جلسة الدخول منتهية',
                  color: h.serverReachable && h.serverAuthenticated
                      ? AppColors.green
                      : AppColors.danger,
                ),
                _tile(
                  'قبول PostgreSQL',
                  h.failed > 0
                      ? 'توجد عمليات مرفوضة أو لم تصل'
                      : h.pending > 0
                      ? 'توجد عمليات محلية لم تُقبل بعد'
                      : 'كل العمليات المستلمة مقبولة',
                ),
                _tile(
                  S.backupStatus,
                  h.backupConfigured == false
                      ? 'غير مهيأ'
                      : h.backupFailed > 0
                      ? 'فشل النسخ إلى Google Sheets'
                      : h.backupPending > 0
                      ? '${h.backupPending} نسخة في انتظار Google Sheets'
                      : 'Google Sheets جاهز',
                  color: h.backupFailed > 0
                      ? AppColors.danger
                      : h.backupConfigured == false
                      ? AppColors.warning
                      : AppColors.green,
                ),
                if (h.backupLastError?.isNotEmpty == true)
                  _tile('خطأ Google Sheets', h.backupLastError!),
                _tile(S.localDbStatus, 'محلية وجاهزة'),
              ],
              if (state.message != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(state.message!),
                ),
              FutureBuilder(
                future: sl<ConflictResolutionService>().openConflicts(),
                builder: (context, snapshot) {
                  final conflicts = snapshot.data ?? const <Conflict>[];
                  if (conflicts.isEmpty) return const SizedBox.shrink();
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'تعارضات تحتاج مراجعة',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          for (final conflict in conflicts)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${conflict.entityType} • ${conflict.entityId}',
                              ),
                              subtitle: const Text(
                                'اختر النسخة المعتمدة. ستبقى النسختان محفوظتين في سجل التعارض.',
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  final service =
                                      sl<ConflictResolutionService>();
                                  final currentSession = context
                                      .read<AuthCubit>()
                                      .state
                                      .session!;
                                  if (value == 'server') {
                                    await service.acceptServer(
                                      currentSession,
                                      conflict.id,
                                    );
                                  } else {
                                    await service.keepLocal(
                                      currentSession,
                                      conflict.id,
                                    );
                                  }
                                  if (context.mounted) {
                                    await context.read<BackupCubit>().refresh();
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'server',
                                    child: Text('اعتماد نسخة الخادم'),
                                  ),
                                  PopupMenuItem(
                                    value: 'local',
                                    child: Text('الاحتفاظ بالنسخة المحلية'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              FilledButton(
                onPressed:
                    state.busy || session?.can(AppPermission.backupSync) != true
                    ? null
                    : () => context.read<BackupCubit>().syncNow(),
                child: const Text(S.syncNow),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed:
                    state.busy ||
                        session?.can(AppPermission.backupRetry) != true
                    ? null
                    : () => context.read<BackupCubit>().retryFailed(),
                child: const Text(S.retryFailed),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed:
                    state.busy ||
                        session?.can(AppPermission.backupFullSync) != true
                    ? null
                    : () => context.read<BackupCubit>().fullBackup(),
                child: const Text(S.fullBackupNow),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        final cubit = context.read<BackupCubit>();
                        await cubit.exportLocal();
                        final json = cubit.state.exportJson;
                        if (json != null && context.mounted) {
                          await downloadBytes(
                            Uint8List.fromList(utf8.encode(json)),
                            filename:
                                'al-nomani-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
                            mimeType: 'application/json;charset=utf-8',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم تنزيل النسخة الاحتياطية المحلية.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: const Text(S.exportLocalBackup),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(String label, String value, {Color? color}) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value, style: TextStyle(color: color)),
    );
  }
}
