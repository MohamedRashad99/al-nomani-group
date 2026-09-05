import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/updates/mobile_update.dart';
import '../../core/utils/open_url.dart';

class MobileUpdateHost extends StatefulWidget {
  const MobileUpdateHost({super.key, required this.child});

  final Widget child;

  @override
  State<MobileUpdateHost> createState() => _MobileUpdateHostState();
}

class _MobileUpdateHostState extends State<MobileUpdateHost> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final info = await checkMobileUpdate();
    if (info == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !info.forceUpdate,
        child: AlertDialog(
          title: Text(
            info.forceUpdate ? 'تحديث إلزامي' : S.updateAvailable,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('يتوفر الإصدار ${info.latestVersionName}.'),
              if (info.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(info.notes.trim()),
              ],
            ],
          ),
          actions: [
            if (!info.forceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(S.updateLater),
              ),
            FilledButton(
              onPressed: () => openExternalUrl(info.updateUrl),
              child: const Text(S.updateNow),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
