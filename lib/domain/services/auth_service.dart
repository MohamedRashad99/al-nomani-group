import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../data/remote/auth_token_store.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../session.dart';

class AuthService {
  AuthService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AppConfig config,
    required Dio dio,
    required AuthTokenStore tokens,
    FlutterSecureStorage? storage,
  }) : _store = store,
       _devices = devices,
       _config = config,
       _dio = dio,
       _tokens = tokens,
       _storage = storage ?? const FlutterSecureStorage();

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AppConfig _config;
  final Dio _dio;
  final AuthTokenStore _tokens;
  final FlutterSecureStorage _storage;

  static const _sessionKey = 'offline_session_v1';
  static const offlineSessionDays = 14;

  Future<AppSession> login(String username, String password) async {
    final normalizedUsername = username.trim();
    final local = await _store.getUserByUsername(normalizedUsername);

    if (local != null) {
      if (!local.isActive || local.isDeleted) {
        throw const AppException('هذا الحساب معطّل.', code: 'user_disabled');
      }
      if (local.passwordHash.isEmpty ||
          !BCrypt.checkpw(password, local.passwordHash)) {
        throw const AppException(
          'اسم المستخدم أو كلمة المرور غير صحيحة.',
          code: 'login_failed',
        );
      }
    }

    var authenticatedOnline = false;
    final skipRemoteLogin =
        kIsWeb &&
        (_config.apiBaseUrl.contains('localhost') ||
            _config.apiBaseUrl.contains('127.0.0.1'));
    try {
      if (skipRemoteLogin) {
        throw const FormatException('skip remote login on web localhost');
      }
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
      await _cacheRemoteUser(data, password, existing: local);
      authenticatedOnline = true;
    } catch (_) {
      if (local == null) {
        throw const AppException(
          'اسم المستخدم أو كلمة المرور غير صحيحة.',
          code: 'login_failed',
        );
      }
    }

    final user = await _store.getUserByUsername(normalizedUsername);
    if (user == null || !user.isActive || user.isDeleted) {
      throw const AppException('هذا الحساب معطّل.', code: 'user_disabled');
    }

    final session = AppSession(
      userId: user.id,
      username: user.username,
      displayName: user.displayName,
      roleName: user.roleId,
      permissions: {...?RolePermissions.matrix[user.roleId]},
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
    final user = await _store.getUser(session.userId) ??
        await _store.getUserByUsername(session.username);
    if (user != null && (!user.isActive || user.isDeleted)) {
      await _storage.delete(key: _sessionKey);
      return null;
    }
    final refreshed = AppSession(
      userId: session.userId,
      username: user?.username ?? session.username,
      displayName: user?.displayName ?? session.displayName,
      roleName: user?.roleId ?? session.roleName,
      permissions: user == null
          ? session.permissions
          : {...?RolePermissions.matrix[user.roleId]},
      expiresAt: session.expiresAt,
      isOfflineVerified: session.isOfflineVerified,
    );
    await _persistSession(refreshed);
    return refreshed;
  }

  Future<void> logout() async {
    await Future.wait([_storage.delete(key: _sessionKey), _tokens.clear()]);
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
    await _devices.setPref('last_user_id', session.userId);
  }

  Future<void> _cacheRemoteUser(
    Map<String, dynamic> data,
    String password, {
    AppUser? existing,
  }) async {
    final now = EgyptTime.nowUtc();
    final deviceId = await _devices.deviceId();
    final user = data['user'] as Map<String, dynamic>? ?? data;
    final serverId = user['id'] as String? ?? newId();
    final id = existing?.id ?? serverId;
    await _store.putUser(
      AppUser(
        id: id,
        username: user['username'] as String,
        displayName:
            user['display_name'] as String? ?? user['username'] as String,
        passwordHash: BCrypt.hashpw(password, BCrypt.gensalt()),
        roleId: user['role'] as String? ?? AppRole.cashier,
        isActive: user['is_active'] as bool? ?? true,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deviceId: deviceId,
      ),
    );
  }
}
