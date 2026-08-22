import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/auth_service.dart';
import '../services/sync_service.dart';

class SyncRoutes {
  SyncRoutes(this.sync);
  final SyncService sync;

  Router get router => Router()
    ..post('/push', (Request request) async {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final protocol = body['sync_protocol_version'] as int? ?? 0;
      if (protocol > AppVersions.syncProtocolVersion) {
        return Response(
          409,
          body: jsonEncode({
            'error': 'بروتوكول المزامنة غير متوافق. لن يتم تجاهل الطابور.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final user = request.context['user'] as AuthUser;
      final result = await sync.push(body, user);
      return Response.ok(
        jsonEncode(result),
        headers: {'content-type': 'application/json'},
      );
    })
    ..get('/status', (Request request) {
      return Response.ok(
        jsonEncode({
          'server_time': DateTime.now().toUtc().toIso8601String(),
          'sync_protocol_version': AppVersions.syncProtocolVersion,
        }),
        headers: {'content-type': 'application/json'},
      );
    });
}
