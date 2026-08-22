import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../services/auth_service.dart';
import '../services/google_sheets_backup.dart';

class BackupRoutes {
  BackupRoutes(this.sheets);
  final GoogleSheetsBackup sheets;

  Router get router => Router()
    ..get('/health', (Request request) async {
      if (!_can(request, AppPermission.backupView)) {
        return Response.forbidden('{"error":"غير مصرح"}');
      }
      return Response.ok(
        jsonEncode(await sheets.health()),
        headers: {'content-type': 'application/json'},
      );
    })
    ..post('/retry', (Request request) async {
      if (!_can(request, AppPermission.backupRetry)) {
        return Response.forbidden('{"error":"غير مصرح"}');
      }
      final result = await sheets.processPending();
      return Response(
        result.configured && result.failed == 0 ? 200 : 503,
        body: jsonEncode(result.toJson()),
        headers: {'content-type': 'application/json'},
      );
    })
    ..post('/full', (Request request) async {
      if (!_can(request, AppPermission.backupFullSync)) {
        return Response.forbidden('{"error":"غير مصرح"}');
      }
      final result = await sheets.writeFullBackup();
      return Response(
        result.configured && result.failed == 0 ? 200 : 503,
        body: jsonEncode(result.toJson()),
        headers: {'content-type': 'application/json'},
      );
    });

  bool _can(Request request, String permission) {
    final user = request.context['user'] as AuthUser?;
    return user?.can(permission) == true;
  }
}
