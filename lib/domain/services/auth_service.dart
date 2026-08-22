import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/remote/auth_token_store.dart';
import '../session.dart';

class AuthService {
  AuthService({
    required AppDatabase db,
    required MetadataStore metadata,
    required AppConfig config,
    required Dio dio,
    required AuthTokenStore tokens,
    FlutterSecureStorage? storage,
  }) : _db = db,
       _metadata = metadata,
       _config = config,
       _dio = dio,
       _tokens = tokens,
       _storage = storage ?? const FlutterSecureStorage();

  final AppDatabase _db;
  final MetadataStore _metadata;
  final AppConfig _config;
  final Dio _dio;
  final AuthTokenStore _tokens;
  final FlutterSecureStorage _storage;

  static const _sessionKey = 'offline_session_v1';
  static const offlineSessionDays = 14;

  Future<AppSession> login(String username, String password) async {
    final normalizedUsername = username.trim();
    final local = await (_db.select(
      _db.users,
    )..where((t) => t.username.equals(normalizedUsername))).getSingleOrNull();

    if (local != null) {
      if (!local.isActive || local.isDeleted) {
        throw const AppException('هذا الحساب معطّل.', code: 'user_disabled');
      }
      if (!BCrypt.checkpw(password, local.passwordHash)) {
        throw const AppException(
          'اسم المستخدم أو كلمة المرور غير صحيحة.',
          code: 'login_failed',
        );
      }
    }

    var authenticatedOnline = false;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '${_config.apiBaseUrl}/api/v1/auth/login',
        data: {'username': normalizedUsername, 'password': password},
        options: Options(sendTimeout: const Duration(seconds: 5)),
      );
      final data = response.data ?? const <String, dynamic>{};
      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      if (access == null || refresh == null) {
        throw const FormatException('missing tokens');
      }
      await _tokens.save(accessToken: access, refreshToken: refresh);
      await _cacheRemoteUser(data, password, existingLocal: local);
      authenticatedOnline = true;
    } catch (_) {
      if (local == null) {
        throw const AppException(
          'اسم المستخدم أو كلمة المرور غير صحيحة.',
          code: 'login_failed',
        );
      }
    }

    final user = await (_db.select(
      _db.users,
    )..where((t) => t.username.equals(normalizedUsername))).getSingle();
    if (!user.isActive || user.isDeleted) {
      throw const AppException('هذا الحساب معطّل.', code: 'user_disabled');
    }

    final permissions = await _permissionsFor(user.roleId);
    final session = AppSession(
      userId: user.id,
      username: user.username,
      displayName: user.displayName,
      roleName: user.roleId,
      permissions: permissions,
      expiresAt: DateTime.now().add(const Duration(days: offlineSessionDays)),
      isOfflineVerified: !authenticatedOnline,
    );
    await _persistSession(session);
    return session;
  }

  Future<AppSession?> restore() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final session = AppSession(
      userId: map['user_id'] as String,
      username: map['username'] as String,
      displayName: map['display_name'] as String,
      roleName: map['role_name'] as String,
      permissions: ((map['permissions'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      expiresAt: DateTime.parse(map['expires_at'] as String),
      isOfflineVerified: true,
    );
    if (session.isExpired) {
      await _storage.delete(key: _sessionKey);
      return null;
    }
    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(session.userId))).getSingleOrNull();
    if (user == null || !user.isActive || user.isDeleted) return null;
    return session;
  }

  Future<void> logout() async {
    await Future.wait([_storage.delete(key: _sessionKey), _tokens.clear()]);
  }

  Future<Set<String>> _permissionsFor(String roleId) async {
    final rows = await (_db.select(
      _db.rolePermissionLinks,
    )..where((t) => t.roleId.equals(roleId))).get();
    if (rows.isNotEmpty) {
      return rows.map((r) => r.permissionId).toSet();
    }
    return {...?RolePermissions.matrix[roleId]};
  }

  Future<void> _persistSession(AppSession session) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({
        'user_id': session.userId,
        'username': session.username,
        'display_name': session.displayName,
        'role_name': session.roleName,
        'permissions': session.permissions.toList(),
        'expires_at': session.expiresAt.toIso8601String(),
      }),
    );
    await _metadata.set('last_user_id', session.userId);
  }

  Future<void> _cacheRemoteUser(
    Map<String, dynamic> data,
    String password, {
    User? existingLocal,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = await _metadata.deviceId();
    final user = data['user'] as Map<String, dynamic>? ?? data;
    final serverId = user['id'] as String? ?? newId();
    final id = existingLocal?.id ?? serverId;
    await _metadata.set('server_user_id', serverId);
    await _db
        .into(_db.users)
        .insertOnConflictUpdate(
          UsersCompanion(
            id: Value(id),
            username: Value(user['username'] as String),
            displayName: Value(
              user['display_name'] as String? ?? user['username'] as String,
            ),
            passwordHash: Value(BCrypt.hashpw(password, BCrypt.gensalt())),
            roleId: Value(user['role'] as String? ?? AppRole.cashier),
            isActive: Value(user['is_active'] as bool? ?? true),
            createdAt: Value(existingLocal?.createdAt ?? now),
            updatedAt: Value(now),
            deviceId: Value(deviceId),
          ),
        );
  }
}
