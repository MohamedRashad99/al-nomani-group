import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../session.dart';
import 'audit_service.dart';
import 'user_identity.dart';

class UserAdminService {
  UserAdminService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
    required Dio dio,
    required AppConfig config,
  }) : _store = store,
       _devices = devices,
       _audit = audit,
       _dio = dio,
       _config = config;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AuditService _audit;
  final Dio _dio;
  final AppConfig _config;

  Future<List<AppUser>> list() => _store.listUsers();
  Stream<List<AppUser>> watch() => _store.watchUsers();

  Future<String> upsert({
    required AppSession session,
    String? id,
    required String username,
    required String displayName,
    String? password,
    required String roleId,
    List<String>? permissions,
    bool isActive = true,
  }) async {
    final creating = id == null;
    if (creating && !session.can(AppPermission.usersCreate)) {
      throw const PermissionException();
    }
    if (!creating && !session.can(AppPermission.usersUpdate)) {
      throw const PermissionException();
    }
    if (creating && (password == null || password.length < 5)) {
      throw const ValidationException('كلمة المرور يجب ألا تقل عن 5 أحرف.');
    }
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty) {
      throw const ValidationException('اسم المستخدم مطلوب.');
    }
    final now = EgyptTime.nowUtc();
    final deviceId = await _devices.deviceId();
    final userId = id ?? newId();
    final existing = id == null ? null : await _store.getUser(id);
    final taken = UserIdentity.pickByUsername(
      await _store.listUsers(),
      trimmedUsername,
    );
    if (taken != null && taken.id != userId) {
      throw const ValidationException('اسم المستخدم مستخدم مسبقاً.');
    }
    await _guardLastAdmin(
      existing: existing,
      nextRoleId: roleId,
      nextActive: isActive,
      nextDeleted: false,
    );
    final hash = password == null || password.isEmpty
        ? existing?.passwordHash
        : BCrypt.hashpw(password, BCrypt.gensalt());
    if (hash == null) {
      throw const ValidationException('كلمة المرور مطلوبة.');
    }
    final user = AppUser(
      id: userId,
      username: trimmedUsername,
      displayName: displayName.trim(),
      passwordHash: hash,
      roleId: roleId,
      permissions: permissions,
      isActive: isActive,
      version: (existing?.version ?? 0) + 1,
      deviceId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.putUser(user);
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: creating ? 'user.create' : 'user.update',
      entityType: 'user',
      entityId: userId,
    );
    try {
      await _dio.post<Map<String, dynamic>>(
        '${_config.apiBaseUrl}/api/v1/users',
        data: {
          'id': userId,
          'username': username.trim(),
          'display_name': displayName.trim(),
          if (password?.isNotEmpty == true) 'password': password,
          'role_id': roleId,
          'is_active': isActive,
        },
      );
    } catch (_) {}
    return userId;
  }

  Future<void> disable(AppSession session, String userId) async {
    await delete(session, userId);
  }

  Future<void> delete(AppSession session, String userId) async {
    if (!session.can(AppPermission.usersDisable)) {
      throw const PermissionException();
    }
    final user = await _store.getUser(userId);
    if (user == null || user.isDeleted) return;
    await _guardLastAdmin(
      existing: user,
      nextRoleId: user.roleId,
      nextActive: false,
      nextDeleted: true,
    );
    final now = EgyptTime.nowUtc();
    final deviceId = await _devices.deviceId();
    await _store.putUser(
      AppUser(
        id: user.id,
        username: user.username,
        displayName: user.displayName,
        passwordHash: user.passwordHash,
        roleId: user.roleId,
        permissions: user.permissions,
        isActive: false,
        version: user.version + 1,
        deviceId: deviceId,
        createdAt: user.createdAt,
        updatedAt: now,
        isDeleted: true,
      ),
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'user.delete',
      entityType: 'user',
      entityId: userId,
    );
  }

  Future<void> _guardLastAdmin({
    required AppUser? existing,
    required String nextRoleId,
    required bool nextActive,
    required bool nextDeleted,
  }) async {
    if (existing == null) return;
    final wasActiveAdmin =
        existing.roleId == AppRole.admin && existing.isActive && !existing.isDeleted;
    if (!wasActiveAdmin) return;
    final stillActiveAdmin =
        nextRoleId == AppRole.admin && nextActive && !nextDeleted;
    if (stillActiveAdmin) return;
    final others = await _store.listUsers();
    final remaining = [
      for (final user in others)
        if (user.id != existing.id &&
            user.roleId == AppRole.admin &&
            user.isActive &&
            !user.isDeleted)
          user,
    ];
    if (remaining.isEmpty) {
      throw const ValidationException('لا يمكن حذف أو تعطيل آخر مدير نشط.');
    }
  }
}
