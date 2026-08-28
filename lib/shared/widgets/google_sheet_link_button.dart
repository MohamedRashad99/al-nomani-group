import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/utils/open_url.dart';
import '../../features/app/app_alert_cubit.dart';

class GoogleSheetLinkButton extends StatelessWidget {
  const GoogleSheetLinkButton({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () async {
        final opened = await openExternalUrl(url);
        if (!opened) sl<AppAlertCubit>().error('تعذر فتح Google Sheet.');
      },
      icon: const Icon(Icons.open_in_new),
      label: const Text(S.openGoogleSheet),
    );
  }
}
