import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../local/app_database.dart';
import '../local/metadata_store.dart';
import 'sync_queue_repository.dart';

/// Enqueues existing local data once so Firestore sections stay complete.
class SyncBaselineService {
  SyncBaselineService(this._db, this._metadata, this._queue);

  static const _completedKey = 'sync_baseline_v2_full_enqueued';

  final AppDatabase _db;
  final MetadataStore _metadata;
  final SyncQueueRepository _queue;

  Future<void> ensureEnqueued() async {
    if (await _metadata.get(_completedKey) == 'true') return;
    final deviceId = await _metadata.deviceId();

    for (final row in await _db.select(_db.roles).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.role,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-role-${row.id}',
        payload: {
          'id': row.id,
          'name': row.name,
          'display_name_ar': row.displayNameAr,
          'version': row.version,
        },
      );
    }

    for (final row in await _db.select(_db.users).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.user,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-user-${row.id}',
        payload: {
          'id': row.id,
          'username': row.username,
          'display_name': row.displayName,
          'role_id': row.roleId,
          'is_active': row.isActive,
          'version': row.version,
        },
      );
    }

    for (final row in await _db.select(_db.productCategories).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.category,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-category-${row.id}',
        payload: {
          'id': row.id,
          'name': row.name,
          'description': row.description,
          'is_active': row.isActive,
          'version': row.version,
          'device_id': row.deviceId ?? deviceId,
        },
      );
    }

    for (final row in await _db.select(_db.customers).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.customer,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-customer-${row.id}',
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
        },
      );
    }

    for (final row in await _db.select(_db.customerAccounts).get()) {
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.customerAccount,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-account-${row.id}',
        payload: {
          'id': row.id,
          'customer_id': row.customerId,
          'cached_balance': row.cachedBalance,
          'version': row.version,
          'device_id': row.deviceId ?? deviceId,
        },
      );
    }

    for (final row in await _db.select(_db.products).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.product,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-product-${row.id}',
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
        },
      );
    }

    for (final row in await _db.select(_db.sales).get()) {
      if (row.isDeleted) continue;
      final items = await (_db.select(
        _db.saleItems,
      )..where((t) => t.saleId.equals(row.id))).get();
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.sale,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-sale-${row.id}',
        payload: {
          'id': row.id,
          'customer_id': row.customerId,
          'sale_number': row.saleNumber,
          'status': row.status,
          'subtotal': row.subtotal,
          'paid_amount': row.paidAmount,
          'remaining_amount': row.remainingAmount,
          'notes': row.notes,
          'sold_at': row.soldAt.toIso8601String(),
          'created_by': row.createdBy,
          'version': row.version,
          'items': [
            for (final item in items)
              {
                'id': item.id,
                'sale_id': item.saleId,
                'product_id': item.productId,
                'quantity': item.quantity,
                'unit': item.unit,
                'unit_price': item.unitPrice,
                'line_total': item.lineTotal,
              },
          ],
        },
      );
      for (final item in items) {
        await _queue.enqueueIfAbsent(
          entityType: SyncEntityType.saleItem,
          entityId: item.id,
          operation: SyncOperationType.create,
          operationId: 'baseline-v2-sale-item-${item.id}',
          payload: {
            'id': item.id,
            'sale_id': item.saleId,
            'product_id': item.productId,
            'quantity': item.quantity,
            'unit': item.unit,
            'unit_price': item.unitPrice,
            'line_total': item.lineTotal,
            'version': item.version,
          },
        );
      }
    }

    for (final row in await _db.select(_db.inventoryMovements).get()) {
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.inventoryMovement,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-inventory-${row.id}',
        payload: {
          'id': row.id,
          'product_id': row.productId,
          'type': row.type,
          'quantity': row.quantity,
          'unit': row.unit,
          'previous_stock': row.previousStock,
          'new_stock': row.newStock,
          'reference_type': row.referenceType,
          'reference_id': row.referenceId,
          'notes': row.notes,
          'created_by': row.createdBy,
          'device_id': row.deviceId,
          'created_at': row.createdAt.toIso8601String(),
          'version': 1,
        },
      );
    }

    for (final row in await _db.select(_db.collections).get()) {
      if (row.isDeleted) continue;
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.collection,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-collection-${row.id}',
        payload: {
          'id': row.id,
          'customer_id': row.customerId,
          'amount': row.amount,
          'payment_method': row.paymentMethod,
          'collected_at': row.collectedAt.toIso8601String(),
          'notes': row.notes,
          'created_by': row.createdBy,
          'status': row.status,
          'version': row.version,
        },
      );
    }

    for (final row in await _db.select(_db.customerAccountTransactions).get()) {
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.customerAccountTransaction,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-account-tx-${row.id}',
        payload: {
          'id': row.id,
          'account_id': row.accountId,
          'customer_id': row.customerId,
          'type': row.type,
          'amount': row.amount,
          'running_balance': row.runningBalance,
          'reference_type': row.referenceType,
          'reference_id': row.referenceId,
          'notes': row.notes,
          'created_by': row.createdBy,
          'device_id': row.deviceId,
          'created_at': row.createdAt.toIso8601String(),
          'version': 1,
        },
      );
    }

    for (final row in await _db.select(_db.auditLogs).get()) {
      await _queue.enqueueIfAbsent(
        entityType: SyncEntityType.auditLog,
        entityId: row.id,
        operation: SyncOperationType.create,
        operationId: 'baseline-v2-audit-${row.id}',
        payload: {
          'id': row.id,
          'user_id': row.userId,
          'device_id': row.deviceId,
          'action': row.action,
          'entity_type': row.entityType,
          'entity_id': row.entityId,
          'old_value': _tryDecode(row.oldValue),
          'new_value': _tryDecode(row.newValue),
          'created_at': row.createdAt.toIso8601String(),
          'version': 1,
        },
      );
    }

    await _metadata.set(_completedKey, 'true');
  }

  Object? _tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
}
