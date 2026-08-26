class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final bool isDeleted;
}

abstract final class CatalogCategories {
  static const all = <ProductCategory>[
    ProductCategory(id: 'cat-fert', name: 'أسمدة زراعية'),
    ProductCategory(id: 'cat-nutri', name: 'مغذيات نباتية'),
    ProductCategory(id: 'cat-insect', name: 'مبيدات حشرية'),
    ProductCategory(id: 'cat-fung', name: 'مبيدات فطرية'),
    ProductCategory(id: 'cat-herb', name: 'مبيدات أعشاب'),
  ];

  static ProductCategory? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final category in all) {
      if (category.id == id) return category;
    }
    return null;
  }
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    this.categoryId,
    this.brand,
    this.description,
    this.packSize,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.currentStock,
    required this.minimumStock,
    required this.unit,
    this.customUnitLabel,
    this.isActive = true,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final String sku;
  final String? categoryId;
  final String? brand;
  final String? description;
  final String? packSize;
  final String purchasePrice;
  final String sellingPrice;
  final String currentStock;
  final String minimumStock;
  final String unit;
  final String? customUnitLabel;
  final bool isActive;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Product copyWith({
    String? currentStock,
    String? unit,
    String? packSize,
    String? customUnitLabel,
    int? version,
    DateTime? updatedAt,
    String? deviceId,
    bool? isDeleted,
  }) {
    return Product(
      id: id,
      name: name,
      sku: sku,
      categoryId: categoryId,
      brand: brand,
      description: description,
      packSize: packSize ?? this.packSize,
      purchasePrice: purchasePrice,
      sellingPrice: sellingPrice,
      currentStock: currentStock ?? this.currentStock,
      minimumStock: minimumStock,
      unit: unit ?? this.unit,
      customUnitLabel: customUnitLabel ?? this.customUnitLabel,
      isActive: isActive,
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'sku': sku,
    'category_id': categoryId,
    'brand': brand,
    'description': description,
    'pack_size': packSize,
    'purchase_price': purchasePrice,
    'selling_price': sellingPrice,
    'current_stock': currentStock,
    'minimum_stock': minimumStock,
    'unit': unit,
    'custom_unit_label': customUnitLabel,
    'is_active': isActive,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.area,
    this.notes,
    this.isActive = true,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? area;
  final String? notes;
  final bool isActive;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'area': area,
    'notes': notes,
    'is_active': isActive,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };
}

class CustomerAccount {
  const CustomerAccount({
    required this.id,
    required this.customerId,
    required this.cachedBalance,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String customerId;
  final String cachedBalance;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerAccount copyWith({
    String? cachedBalance,
    int? version,
    DateTime? updatedAt,
    String? deviceId,
  }) {
    return CustomerAccount(
      id: id,
      customerId: customerId,
      cachedBalance: cachedBalance ?? this.cachedBalance,
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'cached_balance': cachedBalance,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class CustomerAccountTransaction {
  const CustomerAccountTransaction({
    required this.id,
    required this.accountId,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.runningBalance,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.createdBy,
    required this.deviceId,
    required this.createdAt,
  });

  final String id;
  final String accountId;
  final String customerId;
  final String type;
  final String amount;
  final String runningBalance;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String createdBy;
  final String deviceId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'account_id': accountId,
    'customer_id': customerId,
    'type': type,
    'amount': amount,
    'running_balance': runningBalance,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'notes': notes,
    'created_by': createdBy,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
  };
}

class Sale {
  const Sale({
    required this.id,
    required this.customerId,
    required this.saleNumber,
    this.status = 'completed',
    required this.subtotal,
    required this.paidAmount,
    required this.remainingAmount,
    this.notes,
    required this.soldAt,
    required this.createdBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String customerId;
  final String saleNumber;
  final String status;
  final String subtotal;
  final String paidAmount;
  final String remainingAmount;
  final String? notes;
  final DateTime soldAt;
  final String createdBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'sale_number': saleNumber,
    'status': status,
    'subtotal': subtotal,
    'paid_amount': paidAmount,
    'remaining_amount': remainingAmount,
    'notes': notes,
    'sold_at': soldAt.toIso8601String(),
    'created_by': createdBy,
    'cancelled_at': cancelledAt?.toIso8601String(),
    'cancelled_by': cancelledBy,
    'cancel_reason': cancelReason,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
  });

  final String id;
  final String saleId;
  final String productId;
  final String quantity;
  final String unit;
  final String unitPrice;
  final String lineTotal;
  final int version;
  final String? deviceId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'sale_id': saleId,
    'product_id': productId,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'line_total': lineTotal,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
  };
}

class Collection {
  const Collection({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.paymentMethod,
    required this.collectedAt,
    this.notes,
    required this.createdBy,
    this.status = 'completed',
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String customerId;
  final String amount;
  final String paymentMethod;
  final DateTime collectedAt;
  final String? notes;
  final String createdBy;
  final String status;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'amount': amount,
    'payment_method': paymentMethod,
    'collected_at': collectedAt.toIso8601String(),
    'notes': notes,
    'created_by': createdBy,
    'status': status,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };
}

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.unit,
    required this.previousStock,
    required this.newStock,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.createdBy,
    required this.deviceId,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String type;
  final String quantity;
  final String unit;
  final String previousStock;
  final String newStock;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String createdBy;
  final String deviceId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'product_id': productId,
    'type': type,
    'quantity': quantity,
    'unit': unit,
    'previous_stock': previousStock,
    'new_stock': newStock,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'notes': notes,
    'created_by': createdBy,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.passwordHash,
    required this.roleId,
    this.isActive = true,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String username;
  final String displayName;
  final String passwordHash;
  final String roleId;
  final bool isActive;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, dynamic> toMap() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'password_hash': passwordHash,
    'role_id': roleId,
    'is_active': isActive,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };
}

class AuditLog {
  const AuditLog({
    required this.id,
    this.userId,
    this.deviceId,
    required this.action,
    required this.entityType,
    this.entityId,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String? deviceId;
  final String action;
  final String entityType;
  final String? entityId;
  final String? oldValue;
  final String? newValue;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'device_id': deviceId,
    'action': action,
    'entity_type': entityType,
    'entity_id': entityId,
    'old_value': oldValue,
    'new_value': newValue,
    'created_at': createdAt.toIso8601String(),
  };
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.area,
    this.notes,
    this.isActive = true,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? area;
  final String? notes;
  final bool isActive;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'area': area,
    'notes': notes,
    'is_active': isActive,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };
}

class SupplierAccount {
  const SupplierAccount({
    required this.id,
    required this.supplierId,
    required this.cachedBalance,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String supplierId;
  final String cachedBalance;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  SupplierAccount copyWith({
    String? cachedBalance,
    int? version,
    DateTime? updatedAt,
    String? deviceId,
  }) {
    return SupplierAccount(
      id: id,
      supplierId: supplierId,
      cachedBalance: cachedBalance ?? this.cachedBalance,
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'supplier_id': supplierId,
    'cached_balance': cachedBalance,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class SupplierAccountTransaction {
  const SupplierAccountTransaction({
    required this.id,
    required this.accountId,
    required this.supplierId,
    required this.type,
    required this.amount,
    required this.runningBalance,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.createdBy,
    required this.deviceId,
    required this.createdAt,
  });

  final String id;
  final String accountId;
  final String supplierId;
  final String type;
  final String amount;
  final String runningBalance;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String createdBy;
  final String deviceId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'account_id': accountId,
    'supplier_id': supplierId,
    'type': type,
    'amount': amount,
    'running_balance': runningBalance,
    'reference_type': referenceType,
    'reference_id': referenceId,
    'notes': notes,
    'created_by': createdBy,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
  };
}

class Purchase {
  const Purchase({
    required this.id,
    required this.supplierId,
    required this.purchaseNumber,
    this.status = 'completed',
    required this.subtotal,
    required this.paidAmount,
    required this.remainingAmount,
    this.notes,
    required this.purchasedAt,
    required this.createdBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;
  final String supplierId;
  final String purchaseNumber;
  final String status;
  final String subtotal;
  final String paidAmount;
  final String remainingAmount;
  final String? notes;
  final DateTime purchasedAt;
  final String createdBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;
  final int version;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, dynamic> toMap() => {
    'id': id,
    'supplier_id': supplierId,
    'purchase_number': purchaseNumber,
    'status': status,
    'subtotal': subtotal,
    'paid_amount': paidAmount,
    'remaining_amount': remainingAmount,
    'notes': notes,
    'purchased_at': purchasedAt.toIso8601String(),
    'created_by': createdBy,
    'cancelled_at': cancelledAt?.toIso8601String(),
    'cancelled_by': cancelledBy,
    'cancel_reason': cancelReason,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_deleted': isDeleted,
  };
}

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
    this.version = 1,
    this.deviceId,
    required this.createdAt,
  });

  final String id;
  final String purchaseId;
  final String productId;
  final String quantity;
  final String unit;
  final String unitPrice;
  final String lineTotal;
  final int version;
  final String? deviceId;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'purchase_id': purchaseId,
    'product_id': productId,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'line_total': lineTotal,
    'version': version,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
  };
}

class AppSetting {
  const AppSetting({required this.key, required this.value, required this.updatedAt});

  final String key;
  final String value;
  final DateTime updatedAt;
}
