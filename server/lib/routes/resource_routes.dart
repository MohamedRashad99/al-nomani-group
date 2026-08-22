import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/postgres_db.dart';
import '../services/auth_service.dart';

class ResourceRoutes {
  ResourceRoutes(this.db);
  final PostgresDb db;

  Router get router => Router()
    ..get('/products', (Request request) async {
      final rows = await db.query(
        'SELECT id, name, sku, selling_price, current_stock FROM products WHERE is_deleted = FALSE ORDER BY name',
      );
      return Response.ok(
        jsonEncode({
          'items': rows
              .map(
                (r) => {
                  'id': r[0],
                  'name': r[1],
                  'sku': r[2],
                  'selling_price': r[3].toString(),
                  'current_stock': r[4].toString(),
                },
              )
              .toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    })
    ..post('/users', (Request request) async {
      final actor = request.context['user'] as AuthUser;
      if (!actor.can(AppPermission.usersCreate) &&
          !actor.can(AppPermission.usersUpdate)) {
        return Response.forbidden('{"error":"غير مصرح"}');
      }
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = body['id'] as String? ?? '';
      final username = (body['username'] as String? ?? '').trim();
      final password = body['password'] as String?;
      final role = body['role_id'] as String? ?? AppRole.cashier;
      if (id.isEmpty ||
          username.isEmpty ||
          !RolePermissions.matrix.containsKey(role) ||
          (password != null && password.length < 8)) {
        return Response(
          422,
          body: '{"error":"بيانات المستخدم غير صالحة"}',
          headers: {'content-type': 'application/json'},
        );
      }
      final existing = await db.query(
        'SELECT id, password_hash FROM users WHERE id = @id OR username = @username',
        params: {'id': id, 'username': username},
      );
      if (existing.isEmpty && (password == null || password.isEmpty)) {
        return Response(
          422,
          body: '{"error":"كلمة المرور مطلوبة للمستخدم الجديد"}',
          headers: {'content-type': 'application/json'},
        );
      }
      final hash = password == null || password.isEmpty
          ? existing.first[1] as String
          : BCrypt.hashpw(password, BCrypt.gensalt());
      await db.query(
        '''
        INSERT INTO users
          (id, username, display_name, password_hash, role_id, is_active,
           version, device_id, created_at, updated_at)
        VALUES
          (@id, @username, @display, @hash, @role, @active, @version,
           @device, NOW(), NOW())
        ON CONFLICT (id) DO UPDATE SET
          username = EXCLUDED.username,
          display_name = EXCLUDED.display_name,
          password_hash = EXCLUDED.password_hash,
          role_id = EXCLUDED.role_id,
          is_active = EXCLUDED.is_active,
          version = EXCLUDED.version,
          updated_at = NOW()
        ''',
        params: {
          'id': id,
          'username': username,
          'display': body['display_name'] ?? username,
          'hash': hash,
          'role': role,
          'active': body['is_active'] ?? true,
          'version': body['version'] ?? 1,
          'device': body['device_id'],
        },
      );
      return Response.ok(
        jsonEncode({'id': id, 'status': 'saved'}),
        headers: {'content-type': 'application/json'},
      );
    });
}
