import 'package:flutter/material.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'core/l10n/app_strings.dart';

Future<void> main() async {
  try {
    await bootstrap();
    runApp(const AlNomaniApp());
  } catch (e) {
    runApp(
      MaterialApp(
        locale: const Locale('ar'),
        builder: (context, _) => Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${S.migrationFailed}\n\n$e'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
