import 'dart:async';

import '../config/env.dart';
import '../services/google_sheets_backup.dart';

class BackupScheduler {
  BackupScheduler(this.env, this.sheets);
  final Env env;
  final GoogleSheetsBackup sheets;
  Timer? _timer;

  void start() {
    final interval = Duration(days: env.syncIntervalDays);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) async {
      try {
        await sheets.writeFullBackup({
          'Sync Logs': [
            ['scheduled_full_backup', DateTime.now().toUtc().toIso8601String()],
          ],
        });
      } catch (_) {
        // Never propagate backup failure into transactional systems.
      }
    });
  }
}
