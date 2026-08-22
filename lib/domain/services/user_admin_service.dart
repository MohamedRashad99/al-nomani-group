import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../session.dart';
import 'audit_service.dart';

class UserAdminService {
  UserAdminService({
    required AppDatabase db,
    required MetadataStore metadata,
    required SyncQueueRepository queue,
    required AuditService audit,
  }) : _db = db,
       _metadata = metadata,
       _queue = queue,
       _audit = audit;

  final AppDatabase _db;
  final MetadataStore _metadata;
  final SyncQueueRepository _queue;
  final AuditService _audit;

  Future<List<User>> list() =>
      (_db.select(_db.users)..where((t) => t.isDeleted.equals(false))).get();

  Future<String> upsert({
    required AppSession session,
    String? id,
    required String username,
    required String displayName,
    String? password,
    required String roleId,
    bool isActive = true,
  }) async {
    final creating = id == null;
    if (creating && !session.can(AppPermission.usersCreate)) {
      throw const PermissionException();
    }
    if (!creating && !session.can(AppPermission.usersUpdate)) {
      throw const PermissionException();
    }
    if (creating && (password == null || password.length < 8)) {
      throw const ValidationException('كلمة المرور يجب ألا تقل عن 8 أحرف.');
    }

    return _db.transaction(() async {
      final now = DateTime.now().toUtc();
      final deviceId = await _metadata.deviceId();
      final userId = id ?? newId();
      final existing = id == null
          ? null
          : await (_db.select(
              _db.users,
            )..where((t) => t.id.equals(id))).getSingleOrNull();
      final hash = password == null || password.isEmpty
          ? existing?.passwordHash
          : BCrypt.hashpw(password, BCrypt.gensalt());
      if (hash == null) {
        throw const ValidationException('كلمة المرور مطلوبة.');
      }

      await _db
          .into(_db.users)
          .insertOnConflictUpdate(
            UsersCompanion(
              id: Value(userId),
              username: Value(username.trim()),
              displayName: Value(displayName.trim()),
              passwordHash: Value(hash),
              roleId: Value(roleId),
              isActive: Value(isActive),
              version: Value((existing?.version ?? 0) + 1),
              deviceId: Value(deviceId),
              createdAt: Value(existing?.createdAt ?? now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
            ),
          );

      final payload = {
        'id': userId,
        'username': username.trim(),
        'display_name': displayName.trim(),
        'role_id': roleId,
        'is_active': isActive,
        'version': (existing?.version ?? 0) + 1,
      };
      await _audit.write(
        userId: session.userId,
        deviceId: deviceId,
        action: creating ? 'user.create' : 'user.update',
        entityType: 'user',
        entityId: userId,
        oldValue: existing == null
            ? null
            : {'username': existing.username, 'role_id': existing.roleId},
        newValue: payload,
      );
      await _queue.enqueue(
        entityType: SyncEntityType.user,
        entityId: userId,
        operation: creating
            ? SyncOperationType.create
            : SyncOperationType.update,
        payload: payload,
        operationId: newId(),
      );
      return userId;
    });
  }

  Future<void> disable(AppSession session, String userId) async {
    if (!session.can(AppPermission.usersDisable)) {
      throw const PermissionException();
    }
    await upsert(
      session: session,
      id: userId,
      username: (await (_db.select(
        _db.users,
      )..where((t) => t.id.equals(userId))).getSingle()).username,
      displayName: (await (_db.select(
        _db.users,
      )..where((t) => t.id.equals(userId))).getSingle()).displayName,
      roleId: (await (_db.select(
        _db.users,
      )..where((t) => t.id.equals(userId))).getSingle()).roleId,
      isActive: false,
    );
  }
}
