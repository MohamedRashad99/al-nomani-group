import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../session.dart';
import 'audit_service.dart';

class InventoryService {
  InventoryService({
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

  Future<void> adjust({
    required AppSession session,
    required String productId,
    required Quantity quantity,
    required String type,
    String? notes,
    String? referenceType,
    String? referenceId,
    bool allowNegative = false,
  }) async {
    if (!session.can(AppPermission.inventoryAdjust) &&
        !session.can(AppPermission.inventoryCreate) &&
        type != 'sale' &&
        type != 'sale_cancel') {
      throw const PermissionException();
    }
    if (quantity.isZero) {
      throw const ValidationException('الكمية غير صالحة.');
    }

    await _db.transaction(() async {
      await applyInsideTransaction(
        session: session,
        productId: productId,
        quantity: quantity,
        type: type,
        notes: notes,
        referenceType: referenceType,
        referenceId: referenceId,
        allowNegative: allowNegative,
      );
    });
  }

  /// Must be called from an existing Drift transaction.
  Future<void> applyInsideTransaction({
    required AppSession session,
    required String productId,
    required Quantity quantity,
    required String type,
    String? notes,
    String? referenceType,
    String? referenceId,
    bool allowNegative = false,
    bool enqueue = true,
  }) async {
    final product = await (_db.select(
      _db.products,
    )..where((t) => t.id.equals(productId))).getSingleOrNull();
    if (product == null || product.isDeleted) {
      throw const ValidationException('المنتج غير موجود.');
    }

    final previous = Quantity.parse(product.currentStock);
    final signed = _signedQuantity(type, quantity);
    final next = previous + signed;
    if (next.isNegative && !allowNegative) {
      throw const ValidationException('المخزون غير كافٍ.');
    }

    final now = DateTime.now().toUtc();
    final movementId = newId();
    final deviceId = await _metadata.deviceId();

    await (_db.update(
      _db.products,
    )..where((t) => t.id.equals(productId))).write(
      ProductsCompanion(
        currentStock: Value(next.toStorage()),
        version: Value(product.version + 1),
        updatedAt: Value(now),
        deviceId: Value(deviceId),
      ),
    );

    final movement = {
      'id': movementId,
      'product_id': productId,
      'type': type,
      'quantity': quantity.toStorage(),
      'unit': product.unit,
      'previous_stock': previous.toStorage(),
      'new_stock': next.toStorage(),
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
      'created_by': session.userId,
      'device_id': deviceId,
      'created_at': now.toIso8601String(),
    };

    await _db
        .into(_db.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: movementId,
            productId: productId,
            type: type,
            quantity: quantity.toStorage(),
            unit: product.unit,
            previousStock: previous.toStorage(),
            newStock: next.toStorage(),
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            notes: Value(notes),
            createdBy: session.userId,
            deviceId: deviceId,
            createdAt: now,
          ),
        );

    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'inventory.$type',
      entityType: 'inventory_movement',
      entityId: movementId,
      newValue: movement,
    );

    if (enqueue) {
      await _queue.enqueue(
        entityType: SyncEntityType.inventoryMovement,
        entityId: movementId,
        operation: SyncOperationType.create,
        payload: movement,
        operationId: movementId,
      );
    }
  }

  Quantity _signedQuantity(String type, Quantity quantity) {
    final abs = quantity.isNegative ? -quantity : quantity;
    switch (type) {
      case 'stock_in':
      case 'manual_increase':
      case 'return':
      case 'sale_cancel':
        return abs;
      case 'sale':
      case 'stock_out':
      case 'manual_decrease':
        return -abs;
      case 'adjustment':
        return quantity;
      default:
        throw ValidationException('نوع حركة المخزون غير معروف: $type');
    }
  }
}
