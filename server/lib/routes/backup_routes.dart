import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/google_sheets_backup.dart';

class BackupRoutes {
  BackupRoutes(this.sheets);
  final GoogleSheetsBackup sheets;

  Router get router => Router()
    ..post('/full', (Request request) async {
      try {
        await sheets.writeFullBackup({
          'Sync Logs': [
            ['full_backup', DateTime.now().toUtc().toIso8601String()],
          ],
        });
        return Response.ok(
          jsonEncode({'status': 'ok'}),
          headers: {'content-type': 'application/json'},
        );
      } catch (_) {
        return Response(
          503,
          body: jsonEncode({
            'error':
                'تعذر إنشاء النسخة الكاملة. البيانات في PostgreSQL لم تتأثر.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });
}
