import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../session.dart';
import 'account_service.dart';
import 'audit_service.dart';

class CollectionService {
  CollectionService({
    required AppDatabase db,
    required MetadataStore metadata,
    required SyncQueueRepository queue,
    required AuditService audit,
    required AccountService accounts,
  }) : _db = db,
       _metadata = metadata,
       _queue = queue,
       _audit = audit,
       _accounts = accounts;

  final AppDatabase _db;
  final MetadataStore _metadata;
  final SyncQueueRepository _queue;
  final AuditService _audit;
  final AccountService _accounts;

  Stream<List<Collection>> watch() {
    return (_db.select(_db.collections)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.collectedAt)]))
        .watch();
  }

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

    return _db.transaction(() async {
      final now = DateTime.now().toUtc();
      final deviceId = await _metadata.deviceId();
      final id = newId();
      final at = collectedAt?.toUtc() ?? now;

      await _db
          .into(_db.collections)
          .insert(
            CollectionsCompanion.insert(
              id: id,
              customerId: customerId,
              amount: amount.toStorage(),
              paymentMethod: paymentMethod,
              collectedAt: at,
              notes: Value(notes),
              createdBy: session.userId,
              deviceId: Value(deviceId),
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

      final payload = {
        'id': id,
        'customer_id': customerId,
        'amount': amount.toStorage(),
        'payment_method': paymentMethod,
        'collected_at': at.toIso8601String(),
        'notes': notes,
        'created_by': session.userId,
        'device_id': deviceId,
        'version': 1,
      };

      await _audit.write(
        userId: session.userId,
        deviceId: deviceId,
        action: 'collection.create',
        entityType: 'collection',
        entityId: id,
        newValue: payload,
      );
      await _queue.enqueue(
        entityType: SyncEntityType.collection,
        entityId: id,
        operation: SyncOperationType.create,
        payload: payload,
        operationId: id,
      );
      return id;
    });
  }
}
