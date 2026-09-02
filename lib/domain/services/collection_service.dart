import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../session.dart';
import 'account_service.dart';
import 'audit_service.dart';

class CollectionService {
  CollectionService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
    required AccountService accounts,
  }) : _store = store,
       _devices = devices,
       _audit = audit,
       _accounts = accounts;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AuditService _audit;
  final AccountService _accounts;

  Stream<List<Collection>> watch() => _store.watchCollections();

  Future<String> record({
    required AppSession session,
    required String customerId,
    required Money amount,
    required String paymentMethod,
    String? notes,
    DateTime? collectedAt,
  }) async {
    if (!session.can(AppPermission.collectionsCreate)) {
      throw const PermissionException();
    }
    if (!amount.isPositive) {
      throw const ValidationException('مبلغ التحصيل غير صالح.');
    }
    final now = EgyptTime.nowUtc();
    final deviceId = await _devices.deviceId();
    final id = newId();
    final at = collectedAt?.toUtc() ?? now;
    await _store.putCollection(
      Collection(
        id: id,
        customerId: customerId,
        amount: amount.toStorage(),
        paymentMethod: paymentMethod,
        collectedAt: at,
        notes: notes,
        createdBy: session.userId,
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _accounts.post(
      customerId: customerId,
      type: 'payment',
      amount: amount,
      createdBy: session.userId,
      deviceId: deviceId,
      referenceType: 'collection',
      referenceId: id,
      notes: notes,
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'collection.create',
      entityType: 'collection',
      entityId: id,
    );
    return id;
  }
}
