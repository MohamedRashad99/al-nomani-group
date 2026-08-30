import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/open_url.dart';
import '../../features/app/app_alert_cubit.dart';

class CustomerContactActions extends StatelessWidget {
  const CustomerContactActions({super.key, required this.phone});

  final String? phone;

  static String digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'[^\d+]'), '');

  @override
  Widget build(BuildContext context) {
    final raw = phone?.trim() ?? '';
    if (raw.isEmpty) return const SizedBox.shrink();
    final digits = digitsOnly(raw);
    if (digits.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'اتصال',
          onPressed: () => _open('tel:$digits', 'تعذر فتح تطبيق الاتصال.'),
          icon: const Icon(Icons.call_outlined, color: AppColors.darkGreen),
        ),
        IconButton(
          tooltip: 'واتساب',
          onPressed: () => _open(
            'https://wa.me/${digits.replaceAll('+', '')}',
            'تعذر فتح واتساب.',
          ),
          icon: const Icon(Icons.chat_outlined, color: AppColors.green),
        ),
      ],
    );
  }

  Future<void> _open(String url, String error) async {
    final opened = await openExternalUrl(url);
    if (!opened && sl.isRegistered<AppAlertCubit>()) {
      sl<AppAlertCubit>().error(error);
    }
  }
}
