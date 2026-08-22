import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config/env.dart';
import 'database/postgres_db.dart';
import 'middleware/auth_middleware.dart';
import 'routes/auth_routes.dart';
import 'routes/backup_routes.dart';
import 'routes/resource_routes.dart';
import 'routes/sync_routes.dart';
import 'schedulers/backup_scheduler.dart';
import 'services/auth_service.dart';
import 'services/google_sheets_backup.dart';
import 'services/sync_service.dart';

Future<HttpServer> createServer({required int port, PostgresDb? db}) async {
  final env = Env.load();
  final database = db ?? PostgresDb(env);
  await database.open();
  await database.migrate();

  final auth = AuthService(database, env);
  final sheets = GoogleSheetsBackup(env);
  final sync = SyncService(database, sheets);
  BackupScheduler(env, sheets).start();

  final public = Router()
    ..get(
      '/health',
      (Request _) => Response.ok(
        '{"status":"ok"}',
        headers: {'content-type': 'application/json'},
      ),
    )
    ..mount('/api/v1/auth', AuthRoutes(auth).router.call);

  final protected = Router()
    ..mount('/api/v1/sync', SyncRoutes(sync).router.call)
    ..mount('/api/v1/backup', BackupRoutes(sheets).router.call)
    ..mount('/api/v1', ResourceRoutes(database).router.call);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(
        Cascade()
            .add(public.call)
            .add(
              Pipeline()
                  .addMiddleware(authMiddleware(auth))
                  .addHandler(protected.call),
            )
            .handler,
      );

  return io.serve(handler, InternetAddress.anyIPv4, port);
}
