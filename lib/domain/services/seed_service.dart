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
    final users = await _store.listUsers();
    if (users.isNotEmpty) return;
    final now = DateTime.now().toUtc();
    await _store.putUser(
      AppUser(
        id: newId(),
        username: demoAdminUsername,
        displayName: demoAdminDisplayName,
        passwordHash: BCrypt.hashpw(demoAdminPassword, BCrypt.gensalt()),
        roleId: AppRole.admin,
        deviceId: await _devices.deviceId(),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}
