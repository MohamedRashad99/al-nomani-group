import 'dart:async';

import '../config/env.dart';
import '../services/google_sheets_backup.dart';

class BackupScheduler {
  BackupScheduler(this.env, this.sheets);
  final Env env;
  final GoogleSheetsBackup sheets;
  Timer? _fullBackupTimer;
  Timer? _outboxTimer;

  void start() {
    final interval = Duration(days: env.syncIntervalDays);
    _fullBackupTimer?.cancel();
    _outboxTimer?.cancel();
    _outboxTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      await sheets.processPending();
    });
    _fullBackupTimer = Timer.periodic(interval, (_) async {
      await sheets.writeFullBackup();
    });
  }
}
