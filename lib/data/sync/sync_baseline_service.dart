import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../local/app_database.dart';
import '../local/metadata_store.dart';
import 'sync_queue_repository.dart';

/// Enqueues existing local master data once before transactional operations.
///
/// This is essential for installations created offline: sales can reference
/// seeded customers/products that the central database has never seen.
class SyncBaselineService {
  SyncBaselineService(this._db, this._metadata, this._queue);

  static const _completedKey = 'sync_baseline_v1_enqueued';

  final AppDatabase _db;
  final MetadataStore _metadata;
  final SyncQueueRepository _queue;

  Future<void> ensureEnqueued() async {
    if (await _metadata.get(_completedKey) == 'true') return;
    final deviceId = await _metadata.deviceId();

    for (final row in await _db.select(_db.productCategories).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.category,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v1-category-${row.id}',
        payload: {
          'id': row.id,
          'name': row.name,
          'description': row.description,
          'is_active': row.isActive,
          'version': row.version,
          'device_id': row.deviceId ?? deviceId,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
        },
      );
    }

    for (final row in await _db.select(_db.customers).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.customer,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v1-customer-${row.id}',
        payload: {
          'id': row.id,
          'name': row.name,
          'phone': row.phone,
          'address': row.address,
          'area': row.area,
          'notes': row.notes,
          'is_active': row.isActive,
          'version': row.version,
          'device_id': row.deviceId ?? deviceId,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
        },
      );
    }

    for (final row in await _db.select(_db.customerAccounts).get()) {
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.customerAccount,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v1-account-${row.id}',
        payload: {
          'id': row.id,
          'customer_id': row.customerId,
          'cached_balance': row.cachedBalance,
          'version': row.version,
          'device_id': row.deviceId ?? deviceId,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
        },
      );
    }

    for (final row in await _db.select(_db.products).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.product,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v1-product-${row.id}',
        payload: {
          'id': row.id,
          'name': row.name,
          'sku': row.sku,
          'category_id': row.categoryId,
          'brand': row.brand,
          'description': row.description,
          'purchase_price': row.purchasePrice,
          'selling_price': row.sellingPrice,
          'current_stock': row.currentStock,
          'minimum_stock': row.minimumStock,
          'unit': row.unit,
          'custom_unit_label': row.customUnitLabel,
          'is_active': row.isActive,
          'version': row.version,
          'device_id': row.deviceId ?? deviceId,
          'created_at': row.createdAt.toIso8601String(),
          'updated_at': row.updatedAt.toIso8601String(),
        },
      );
    }

    await _metadata.set(_completedKey, 'true');
  }
}
