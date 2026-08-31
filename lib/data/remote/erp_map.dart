import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/erp_models.dart';

String mapText(Map<String, dynamic> data, List<String> keys, [String fallback = '']) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    final text = '$value';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return fallback;
}

String? mapTextOrNull(Map<String, dynamic> data, List<String> keys) {
  final text = mapText(data, keys);
  return text.isEmpty ? null : text;
}

bool mapBool(Map<String, dynamic> data, List<String> keys, {bool fallback = true}) {
  for (final key in keys) {
    final value = data[key];
    if (value is bool) return value;
  }
  return fallback;
}

int mapVersion(Map<String, dynamic> data) {
  final value = data['version'];
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 1;
}

DateTime mapDate(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
  }
  return DateTime.now().toUtc();
}

DateTime? mapDateOrNull(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
  }
  return null;
}

Product productFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return Product(
    id: id,
    name: mapText(data, const ['name'], 'منتج'),
    sku: mapText(data, const ['sku'], id),
    categoryId: mapTextOrNull(data, const ['category_id', 'categoryId']),
    brand: mapTextOrNull(data, const ['brand']),
    description: mapTextOrNull(data, const ['description']),
    packSize: mapTextOrNull(data, const ['pack_size', 'packSize']),
    packageSize: mapTextOrNull(data, const ['package_size', 'packageSize']),
    unitOfMeasure: mapTextOrNull(data, const ['unit_of_measure', 'unitOfMeasure']),
    packageType: mapTextOrNull(data, const ['package_type', 'packageType']),
    reorderPoint: mapTextOrNull(data, const ['reorder_point', 'reorderPoint']),
    safetyStock: mapTextOrNull(data, const ['safety_stock', 'safetyStock']),
    purchasePrice: mapText(data, const ['purchase_price', 'purchasePrice'], '0'),
    sellingPrice: mapText(data, const ['selling_price', 'sellingPrice'], '0'),
    currentStock: mapText(data, const ['current_stock', 'currentStock'], '0'),
    minimumStock: mapText(data, const ['minimum_stock', 'minimumStock'], '0'),
    unit: mapText(data, const ['unit'], ''),
    customUnitLabel: mapTextOrNull(data, const ['custom_unit_label', 'customUnitLabel']),
    isActive: mapBool(data, const ['is_active', 'isActive']),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
    isDeleted: mapBool(data, const ['is_deleted', 'isDeleted'], fallback: false) ||
        data['operation'] == 'delete',
    images: _imagesFrom(data['images']),
  );
}

List<ProductImage> _imagesFrom(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        ProductImage.fromMap(Map<String, dynamic>.from(item)),
  ];
}

Customer customerFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return Customer(
    id: id,
    name: mapText(data, const ['name'], 'عميل'),
    phone: mapTextOrNull(data, const ['phone']),
    address: mapTextOrNull(data, const ['address']),
    area: mapTextOrNull(data, const ['area']),
    notes: mapTextOrNull(data, const ['notes']),
    linkedSupplierId: mapTextOrNull(data, const ['linked_supplier_id', 'linkedSupplierId']),
    isActive: mapBool(data, const ['is_active', 'isActive']),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
    isDeleted: mapBool(data, const ['is_deleted', 'isDeleted'], fallback: false) ||
        data['operation'] == 'delete',
  );
}

CustomerAccount accountFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return CustomerAccount(
    id: id,
    customerId: mapText(data, const ['customer_id', 'customerId']),
    cachedBalance: mapText(data, const ['cached_balance', 'cachedBalance'], '0'),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
  );
}

CustomerAccountTransaction accountTxFromMap(Map<String, dynamic> data, String id) {
  return CustomerAccountTransaction(
    id: id,
    accountId: mapText(data, const ['account_id', 'accountId']),
    customerId: mapText(data, const ['customer_id', 'customerId']),
    type: mapText(data, const ['type']),
    amount: mapText(data, const ['amount'], '0'),
    runningBalance: mapText(data, const ['running_balance', 'runningBalance'], '0'),
    referenceType: mapTextOrNull(data, const ['reference_type', 'referenceType']),
    referenceId: mapTextOrNull(data, const ['reference_id', 'referenceId']),
    notes: mapTextOrNull(data, const ['notes']),
    createdBy: mapText(data, const ['created_by', 'createdBy']),
    deviceId: mapText(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
  );
}

Sale saleFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return Sale(
    id: id,
    customerId: mapText(data, const ['customer_id', 'customerId']),
    saleNumber: mapText(data, const ['sale_number', 'saleNumber'], id),
    status: mapText(data, const ['status'], 'completed'),
    subtotal: mapText(data, const ['subtotal'], '0'),
    paidAmount: mapText(data, const ['paid_amount', 'paidAmount'], '0'),
    remainingAmount: mapText(data, const ['remaining_amount', 'remainingAmount'], '0'),
    notes: mapTextOrNull(data, const ['notes']),
    soldAt: mapDate(data, const ['sold_at', 'soldAt']),
    createdBy: mapText(data, const ['created_by', 'createdBy']),
    cancelledAt: mapDateOrNull(data, const ['cancelled_at', 'cancelledAt']),
    cancelledBy: mapTextOrNull(data, const ['cancelled_by', 'cancelledBy']),
    cancelReason: mapTextOrNull(data, const ['cancel_reason', 'cancelReason', 'reason']),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
    isDeleted: mapBool(data, const ['is_deleted', 'isDeleted'], fallback: false) ||
        data['operation'] == 'delete',
  );
}

SaleItem saleItemFromMap(Map<String, dynamic> data, String id) {
  return SaleItem(
    id: id,
    saleId: mapText(data, const ['sale_id', 'saleId']),
    productId: mapText(data, const ['product_id', 'productId']),
    quantity: mapText(data, const ['quantity'], '0'),
    unit: mapText(data, const ['unit']),
    unitPrice: mapText(data, const ['unit_price', 'unitPrice'], '0'),
    lineTotal: mapText(data, const ['line_total', 'lineTotal'], '0'),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
  );
}

Collection collectionFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return Collection(
    id: id,
    customerId: mapText(data, const ['customer_id', 'customerId']),
    amount: mapText(data, const ['amount'], '0'),
    paymentMethod: mapText(data, const ['payment_method', 'paymentMethod'], 'cash'),
    collectedAt: mapDate(data, const ['collected_at', 'collectedAt']),
    notes: mapTextOrNull(data, const ['notes']),
    createdBy: mapText(data, const ['created_by', 'createdBy']),
    status: mapText(data, const ['status'], 'completed'),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
    isDeleted: mapBool(data, const ['is_deleted', 'isDeleted'], fallback: false) ||
        data['operation'] == 'delete',
  );
}

InventoryMovement movementFromMap(Map<String, dynamic> data, String id) {
  return InventoryMovement(
    id: id,
    productId: mapText(data, const ['product_id', 'productId']),
    type: mapText(data, const ['type']),
    quantity: mapText(data, const ['quantity'], '0'),
    unit: mapText(data, const ['unit']),
    previousStock: mapText(data, const ['previous_stock', 'previousStock'], '0'),
    newStock: mapText(data, const ['new_stock', 'newStock'], '0'),
    referenceType: mapTextOrNull(data, const ['reference_type', 'referenceType']),
    referenceId: mapTextOrNull(data, const ['reference_id', 'referenceId']),
    notes: mapTextOrNull(data, const ['notes']),
    actualQuantity: mapTextOrNull(data, const ['actual_quantity', 'actualQuantity']),
    unitOfMeasure: mapTextOrNull(data, const ['unit_of_measure', 'unitOfMeasure']),
    createdBy: mapText(data, const ['created_by', 'createdBy']),
    deviceId: mapText(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
  );
}

AppUser userFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return AppUser(
    id: id,
    username: mapText(data, const ['username']),
    displayName: mapText(data, const ['display_name', 'displayName', 'username']),
    passwordHash: mapText(data, const ['password_hash', 'passwordHash']),
    roleId: mapText(data, const ['role_id', 'roleId', 'role'], 'cashier'),
    isActive: mapBool(data, const ['is_active', 'isActive']),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
    isDeleted: mapBool(data, const ['is_deleted', 'isDeleted'], fallback: false) ||
        data['operation'] == 'delete',
  );
}

AuditLog auditFromMap(Map<String, dynamic> data, String id) {
  return AuditLog(
    id: id,
    userId: mapTextOrNull(data, const ['user_id', 'userId']),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    action: mapText(data, const ['action']),
    entityType: mapText(data, const ['entity_type', 'entityType']),
    entityId: mapTextOrNull(data, const ['entity_id', 'entityId']),
    oldValue: mapTextOrNull(data, const ['old_value', 'oldValue']),
    newValue: mapTextOrNull(data, const ['new_value', 'newValue']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
  );
}

Supplier supplierFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return Supplier(
    id: id,
    name: mapText(data, const ['name'], 'مورد'),
    phone: mapTextOrNull(data, const ['phone']),
    address: mapTextOrNull(data, const ['address']),
    area: mapTextOrNull(data, const ['area']),
    notes: mapTextOrNull(data, const ['notes']),
    linkedCustomerId: mapTextOrNull(data, const ['linked_customer_id', 'linkedCustomerId']),
    isActive: mapBool(data, const ['is_active', 'isActive']),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
    isDeleted: mapBool(data, const ['is_deleted', 'isDeleted'], fallback: false) ||
        data['operation'] == 'delete',
  );
}

SupplierAccount supplierAccountFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return SupplierAccount(
    id: id,
    supplierId: mapText(data, const ['supplier_id', 'supplierId']),
    cachedBalance: mapText(data, const ['cached_balance', 'cachedBalance'], '0'),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
  );
}

SupplierAccountTransaction supplierTxFromMap(Map<String, dynamic> data, String id) {
  return SupplierAccountTransaction(
    id: id,
    accountId: mapText(data, const ['account_id', 'accountId']),
    supplierId: mapText(data, const ['supplier_id', 'supplierId']),
    type: mapText(data, const ['type']),
    amount: mapText(data, const ['amount'], '0'),
    runningBalance: mapText(data, const ['running_balance', 'runningBalance'], '0'),
    referenceType: mapTextOrNull(data, const ['reference_type', 'referenceType']),
    referenceId: mapTextOrNull(data, const ['reference_id', 'referenceId']),
    notes: mapTextOrNull(data, const ['notes']),
    createdBy: mapText(data, const ['created_by', 'createdBy']),
    deviceId: mapText(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
  );
}

Purchase purchaseFromMap(Map<String, dynamic> data, String id) {
  final now = DateTime.now().toUtc();
  return Purchase(
    id: id,
    supplierId: mapText(data, const ['supplier_id', 'supplierId']),
    purchaseNumber: mapText(data, const ['purchase_number', 'purchaseNumber'], id),
    status: mapText(data, const ['status'], 'completed'),
    subtotal: mapText(data, const ['subtotal'], '0'),
    paidAmount: mapText(data, const ['paid_amount', 'paidAmount'], '0'),
    remainingAmount: mapText(data, const ['remaining_amount', 'remainingAmount'], '0'),
    notes: mapTextOrNull(data, const ['notes']),
    purchasedAt: mapDate(data, const ['purchased_at', 'purchasedAt']),
    createdBy: mapText(data, const ['created_by', 'createdBy']),
    cancelledAt: mapDateOrNull(data, const ['cancelled_at', 'cancelledAt']),
    cancelledBy: mapTextOrNull(data, const ['cancelled_by', 'cancelledBy']),
    cancelReason: mapTextOrNull(data, const ['cancel_reason', 'cancelReason', 'reason']),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
    updatedAt: mapDateOrNull(data, const ['updated_at', 'updatedAt']) ?? now,
    isDeleted: mapBool(data, const ['is_deleted', 'isDeleted'], fallback: false) ||
        data['operation'] == 'delete',
  );
}

PurchaseItem purchaseItemFromMap(Map<String, dynamic> data, String id) {
  return PurchaseItem(
    id: id,
    purchaseId: mapText(data, const ['purchase_id', 'purchaseId']),
    productId: mapText(data, const ['product_id', 'productId']),
    quantity: mapText(data, const ['quantity'], '0'),
    unit: mapText(data, const ['unit']),
    unitPrice: mapText(data, const ['unit_price', 'unitPrice'], '0'),
    lineTotal: mapText(data, const ['line_total', 'lineTotal'], '0'),
    returnedQuantity: mapText(
      data,
      const ['returned_quantity', 'returnedQuantity'],
      '0',
    ),
    version: mapVersion(data),
    deviceId: mapTextOrNull(data, const ['device_id', 'deviceId']),
    createdAt: mapDate(data, const ['created_at', 'createdAt']),
  );
}
