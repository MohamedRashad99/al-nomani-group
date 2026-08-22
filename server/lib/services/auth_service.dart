import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../config/env.dart';
import '../database/postgres_db.dart';

class AuthUser {
  final String id;
  final String username;
  final String displayName;
  final String role;
  final List<String> permissions;

  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.permissions,
  });

  bool can(String permission) => permissions.contains(permission);

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'role': role,
    'permissions': permissions,
  };
}

class AuthService {
  AuthService(this.db, this.env);
  final PostgresDb db;
  final Env env;

  Future<Map<String, dynamic>> login(String username, String password) async {
    final rows = await db.query(
      'SELECT id, username, display_name, password_hash, role_id, is_active, is_deleted FROM users WHERE username = @u',
      params: {'u': username},
    );
    if (rows.isEmpty) {
      throw StateError('invalid');
    }
    final row = rows.first;
    final hash = row[3] as String;
    final active = row[5] as bool;
    final deleted = row[6] as bool;
    if (!active || deleted || !BCrypt.checkpw(password, hash)) {
      throw StateError('invalid');
    }
    final user = AuthUser(
      id: row[0] as String,
      username: row[1] as String,
      displayName: row[2] as String,
      role: row[4] as String,
      permissions: RolePermissions.matrix[row[4] as String] ?? const [],
    );
    final access = JWT({
      'sub': user.id,
      'role': user.role,
    }).sign(SecretKey(env.jwtSecret), expiresIn: const Duration(minutes: 15));
    final refresh = JWT({
      'sub': user.id,
      'type': 'refresh',
    }).sign(SecretKey(env.jwtSecret), expiresIn: const Duration(days: 7));
    return {
      'access_token': access,
      'refresh_token': refresh,
      'user': user.toJson(),
    };
  }

  AuthUser verify(String token) {
    final jwt = JWT.verify(token, SecretKey(env.jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    final role = payload['role'] as String? ?? AppRole.viewer;
    return AuthUser(
      id: payload['sub'] as String,
      username: '',
      displayName: '',
      role: role,
      permissions: RolePermissions.matrix[role] ?? const [],
    );
  }
}
