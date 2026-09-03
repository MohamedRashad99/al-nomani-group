import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../features/app/app_alert_cubit.dart';
import '../../features/app/app_busy_cubit.dart';

/// Confirms destructive ops, blocks double-submit via [AppBusyCubit], and
/// surfaces success/error through [AppAlertCubit].
class DestructiveActionGuard {
  const DestructiveActionGuard._();

  static Future<void> run({
    required BuildContext context,
    required String title,
    required String message,
    required Future<void> Function() action,
    required String successMessage,
    String confirmLabel = 'تأكيد',
    bool requireReason = false,
    String reasonLabel = 'سبب',
    VoidCallback? onSuccess,
  }) async {
    final reasonController = requireReason ? TextEditingController() : null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            if (requireReason) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(labelText: reasonLabel),
                maxLines: 2,
                autofocus: true,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(S.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final reason = reasonController?.text.trim() ?? '';
    reasonController?.dispose();
    if (confirmed != true || !context.mounted) return;
    if (requireReason && reason.isEmpty) {
      sl<AppAlertCubit>().error('سبب العملية مطلوب.');
      return;
    }
    try {
      await sl<AppBusyCubit>().guard(action);
      sl<AppAlertCubit>().success(successMessage);
      onSuccess?.call();
    } catch (error) {
      sl<AppAlertCubit>().error(error.toString());
    }
  }

  static Future<void> runWithReason({
    required BuildContext context,
    required String title,
    required String message,
    required Future<void> Function(String reason) action,
    required String successMessage,
    String confirmLabel = 'تأكيد',
    String reasonLabel = 'سبب',
    VoidCallback? onSuccess,
  }) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(labelText: reasonLabel),
              maxLines: 2,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(S.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || reason.isEmpty || !context.mounted) {
      if (confirmed == true && reason.isEmpty) {
        sl<AppAlertCubit>().error('سبب العملية مطلوب.');
      }
      return;
    }
    try {
      await sl<AppBusyCubit>().guard(() => action(reason));
      sl<AppAlertCubit>().success(successMessage);
      onSuccess?.call();
    } catch (error) {
      sl<AppAlertCubit>().error(error.toString());
    }
  }
}

/// Disables child actions while [AppBusyCubit] is active.
class BusyGuarded extends StatelessWidget {
  const BusyGuarded({super.key, required this.builder});

  final Widget Function(BuildContext context, bool busy) builder;

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AppBusyCubit>().isBusy;
    return builder(context, busy);
  }
}
