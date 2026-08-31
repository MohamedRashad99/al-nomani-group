import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../session.dart';
import 'audit_service.dart';
import 'inventory_measure.dart';

class InventoryService {
  InventoryService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
  }) : _store = store,
       _devices = devices,
       _audit = audit;

  final ErpStore _store;
  final DeviceIdStore _devices;
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
        type != 'sale_cancel' &&
        type != 'purchase' &&
        type != 'purchase_cancel' &&
        type != 'purchase_return') {
      throw const PermissionException();
    }
    if (quantity.isZero) {
      throw const ValidationException('الكمية غير صالحة.');
    }
    await apply(
      session: session,
      productId: productId,
      quantity: quantity,
      type: type,
      notes: notes,
      referenceType: referenceType,
      referenceId: referenceId,
      allowNegative: allowNegative,
    );
  }

  Future<void> apply({
    required AppSession session,
    required String productId,
    required Quantity quantity,
    required String type,
    String? notes,
    String? referenceType,
    String? referenceId,
    bool allowNegative = false,
  }) async {
    final product = await _store.getProduct(productId);
    if (product == null || product.isDeleted) {
      throw const ValidationException('المنتج غير موجود.');
    }
    final previous = Quantity.parse(product.currentStock);
    final signed = _signedQuantity(type, quantity);
    final next = previous + signed;
    if (next.isNegative && !allowNegative) {
      throw const ValidationException('المخزون غير كافٍ.');
    }
    final measure = InventoryMeasure.fromProduct(product);
    final actualDelta = measure.actualOf(signed.isNegative ? -signed : signed);
    final now = DateTime.now().toUtc();
    final movementId = newId();
    final deviceId = await _devices.deviceId();
    await _store.putProduct(
      product.copyWith(
        currentStock: next.toStorage(),
        version: product.version + 1,
        updatedAt: now,
        deviceId: deviceId,
      ),
    );
    final actualNote = 'فعلي ${InventoryMeasure.formatQuantity(actualDelta, measure.unitOfMeasure)}';
    final combinedNotes = notes == null || notes.trim().isEmpty
        ? actualNote
        : '${notes.trim()} • $actualNote';
    final movement = InventoryMovement(
      id: movementId,
      productId: productId,
      type: type,
      quantity: quantity.toStorage(),
      unit: measure.packageType,
      previousStock: previous.toStorage(),
      newStock: next.toStorage(),
      referenceType: referenceType,
      referenceId: referenceId,
      notes: combinedNotes,
      actualQuantity: actualDelta.toStorage(),
      unitOfMeasure: measure.unitOfMeasure.code,
      createdBy: session.userId,
      deviceId: deviceId,
      createdAt: now,
    );
    await _store.putMovement(movement);
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'inventory.$type',
      entityType: 'inventory_movement',
      entityId: movementId,
      newValue: movement.toMap(),
    );
  }

  Stream<List<InventoryMovement>> watchMovements({String? productId}) {
    return _store.watchMovements(productId: productId);
  }

  Quantity _signedQuantity(String type, Quantity quantity) {
    final abs = quantity.isNegative ? -quantity : quantity;
    switch (type) {
      case 'stock_in':
      case 'manual_increase':
      case 'return':
      case 'sale_cancel':
      case 'purchase':
        return abs;
      case 'sale':
      case 'stock_out':
      case 'manual_decrease':
      case 'purchase_cancel':
      case 'purchase_return':
        return -abs;
      case 'adjustment':
        return quantity;
      default:
        throw ValidationException('نوع حركة المخزون غير معروف: $type');
    }
  }
}
