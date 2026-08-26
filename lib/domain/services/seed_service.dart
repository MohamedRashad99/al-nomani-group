import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';

import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';

class SeedService {
  SeedService(this._store, this._devices);
  final ErpStore _store;
  final DeviceIdStore _devices;

  static const demoAdminUsername = 'admin';
  static const demoAdminPassword = '54321';
  static const demoAdminDisplayName = 'م / أحمد نعمان الجعبيري';

  Future<void> ensureDemoAdminIdentity() async {
    final existing = await _store.getUserByUsername(demoAdminUsername);
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
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
    if (existing.displayName == demoAdminDisplayName && passwordMatches) {
      return;
    }

    await _store.putUser(
      AppUser(
        id: existing.id,
        username: existing.username,
        displayName: demoAdminDisplayName,
        passwordHash: BCrypt.hashpw(demoAdminPassword, BCrypt.gensalt()),
        roleId: existing.roleId.isEmpty ? AppRole.admin : existing.roleId,
        isActive: true,
        version: existing.version + 1,
        deviceId: deviceId,
        createdAt: existing.createdAt,
        updatedAt: now,
      ),
    );
  }
}
