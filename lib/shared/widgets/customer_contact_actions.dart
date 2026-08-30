import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/egypt_phone.dart';
import '../../core/utils/open_url.dart';
import '../../features/app/app_alert_cubit.dart';

class CustomerContactActions extends StatelessWidget {
  const CustomerContactActions({super.key, required this.phone});

  final String? phone;

  static String digitsOnly(String raw) => EgyptPhone.digitsOnly(raw);

  @override
  Widget build(BuildContext context) {
    final tel = EgyptPhone.telUri(phone);
    if (tel == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'اتصال',
          onPressed: () => _open(
            tel,
            fallback: null,
            error: 'تعذر فتح تطبيق الاتصال. استخدم هاتفاً أو أضف رمز الدولة.',
          ),
          icon: const Icon(Icons.call_outlined, color: AppColors.darkGreen),
        ),
        IconButton(
          tooltip: 'واتساب',
          onPressed: () => _open(
            EgyptPhone.whatsAppMe(phone)!,
            fallback: EgyptPhone.whatsAppApi(phone),
            error: 'تعذر فتح واتساب.',
          ),
          icon: const Icon(Icons.chat_outlined, color: AppColors.green),
        ),
      ],
    );
  }

  Future<void> _open(
    String url, {
    required String? fallback,
    required String error,
  }) async {
    var opened = await openExternalUrl(url);
    if (!opened && fallback != null) {
      opened = await openExternalUrl(fallback);
    }
    if (!opened && sl.isRegistered<AppAlertCubit>()) {
      sl<AppAlertCubit>().error(error);
    }
  }
}
