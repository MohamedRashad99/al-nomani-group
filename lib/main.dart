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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/al_nomani_logo.png',
                          width: 96,
                          height: 96,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'تعذر بدء النظام بأمان',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${S.migrationFailed}\n\n$e',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
