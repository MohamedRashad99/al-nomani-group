import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';

import '../config/env.dart';
import 'postgres_db.dart';

class ServerSeeder {
  ServerSeeder(this.db, this.env);

  final PostgresDb db;
  final Env env;

  Future<void> seedBootstrapAdmin() async {
    if (!env.allowSeed) return;
    final username = env.bootstrapAdminUsername;
    final password = env.bootstrapAdminPassword;
    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.length < 12) {
      return;
    }

    await db.transaction((tx) async {
      for (final entry in const {
        AppRole.admin: 'مدير النظام',
        AppRole.manager: 'مدير',
        AppRole.cashier: 'أمين صندوق',
        AppRole.viewer: 'عرض فقط',
      }.entries) {
        await tx.execute(
          Sql.named('''
            INSERT INTO roles (id, name, display_name_ar)
            VALUES (@id, @name, @display)
            ON CONFLICT (id) DO NOTHING
          '''),
          parameters: {
            'id': entry.key,
            'name': entry.key,
            'display': entry.value,
          },
        );
      }
      for (final code in AppPermission.all) {
        await tx.execute(
          Sql.named('''
            INSERT INTO permissions (id, code)
            VALUES (@id, @code)
            ON CONFLICT (id) DO NOTHING
          '''),
          parameters: {'id': code, 'code': code},
        );
        await tx.execute(
          Sql.named('''
            INSERT INTO role_permissions (role_id, permission_id)
            VALUES (@role, @permission)
            ON CONFLICT DO NOTHING
          '''),
          parameters: {'role': AppRole.admin, 'permission': code},
        );
      }
      await tx.execute(
        Sql.named('''
          INSERT INTO users
            (id, username, display_name, password_hash, role_id)
          VALUES
            ('server-admin', @username, 'مدير النظام', @hash, @role)
          ON CONFLICT (username) DO NOTHING
        '''),
        parameters: {
          'username': username,
          'hash': BCrypt.hashpw(password, BCrypt.gensalt()),
          'role': AppRole.admin,
        },
      );
    });
  }
}
