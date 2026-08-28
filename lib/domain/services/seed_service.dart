import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';

import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import 'user_identity.dart';

class SeedService {
  SeedService(this._store, this._devices);
  final ErpStore _store;
  final DeviceIdStore _devices;

  static const demoAdminUsername = 'admin';
  static const demoAdminPassword = '54321';
  static const demoAdminDisplayName = 'م / أحمد نعمان الجعبيري';

  Future<void> ensureDemoAdminIdentity() async {
    final users = await _store.listUsers();
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final hiddenIds = await _softDeleteDuplicateAdmins(users, deviceId, now);
    final existing = UserIdentity.pickByUsername(
      await _store.listUsers(),
      demoAdminUsername,
    );
    if (existing == null) {
      await _store.putUser(
        AppUser(
          id: newId(),
          username: demoAdminUsername,
          displayName: demoAdminDisplayName,
          passwordHash: BCrypt.hashpw(demoAdminPassword, BCrypt.gensalt()),
          roleId: AppRole.admin,
          deviceId: deviceId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return;
    }

    var passwordMatches = false;
    try {
      passwordMatches =
          existing.passwordHash.isNotEmpty &&
          BCrypt.checkpw(demoAdminPassword, existing.passwordHash);
    } catch (_) {}

    final needsProfileFix =
        existing.displayName != demoAdminDisplayName ||
        existing.roleId.isEmpty ||
        !existing.isActive;
    if (passwordMatches && !needsProfileFix && hiddenIds.isEmpty) {
      return;
    }

    await _store.putUser(
      existing.copyWith(
        displayName: demoAdminDisplayName,
        passwordHash: passwordMatches
            ? existing.passwordHash
            : BCrypt.hashpw(demoAdminPassword, BCrypt.gensalt()),
        roleId: existing.roleId.isEmpty ? AppRole.admin : existing.roleId,
        isActive: true,
        version: existing.version + 1,
        deviceId: deviceId,
        updatedAt: now,
      ),
    );
  }

  Future<List<String>> _softDeleteDuplicateAdmins(
    List<AppUser> users,
    String deviceId,
    DateTime now,
  ) async {
    final admins = UserIdentity.matchesByUsername(users, demoAdminUsername);
    if (admins.length <= 1) return const [];
    admins.sort(UserIdentity.compareCanonical);
    final kept = admins.first;
    final hiddenIds = <String>[];
    for (final extra in admins.skip(1)) {
      hiddenIds.add(extra.id);
      await _store.putUser(
        extra.copyWith(
          isDeleted: true,
          isActive: false,
          version: extra.version + 1,
          deviceId: deviceId,
          updatedAt: now,
        ),
      );
    }
    await _store.putAudit(
      AuditLog(
        id: newId(),
        userId: kept.id,
        deviceId: deviceId,
        action: 'user.dedupe_admin',
        entityType: 'user',
        entityId: kept.id,
        oldValue: hiddenIds.join(','),
        newValue: kept.id,
        createdAt: now,
      ),
    );
    return hiddenIds;
  }
}
