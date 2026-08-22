import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/app_scaffold.dart';
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
                _tile(S.backupStatus, h.statusAr),
                _tile(S.localDbStatus, 'محلية وجاهزة'),
              ],
              if (state.message != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(state.message!),
                ),
              FilledButton(
                onPressed: state.busy
                    ? null
                    : () => context.read<BackupCubit>().syncNow(),
                child: const Text(S.syncNow),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: state.busy
                    ? null
                    : () => context.read<BackupCubit>().retryFailed(),
                child: const Text(S.retryFailed),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: state.busy
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
                          await Clipboard.setData(ClipboardData(text: json));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم نسخ النسخة الاحتياطية إلى الحافظة.',
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
