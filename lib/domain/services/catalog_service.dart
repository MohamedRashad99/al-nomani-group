import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../session.dart';
import 'audit_service.dart';

class CatalogService {
  CatalogService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
  }) : _store = store,
       _devices = devices,
       _audit = audit;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AuditService _audit;

  Future<List<Product>> searchProducts(String query) async {
    return _filterProducts(await _store.listProducts(), query);
  }

  Stream<List<Product>> watchProducts(String query) {
    return _store.watchProducts().map((items) => _filterProducts(items, query));
  }

  List<Product> _filterProducts(List<Product> items, String query) {
    final q = query.trim();
    if (q.isEmpty) return items;
    return [
      for (final item in items)
        if (item.name.contains(q) ||
            item.sku.contains(q) ||
            (item.brand ?? '').contains(q))
          item,
    ];
  }

  Future<List<Customer>> searchCustomers(String query) async {
    return _filterCustomers(await _store.listCustomers(), query);
  }

  Stream<List<Customer>> watchCustomers(String query) {
    return _store.watchCustomers().map(
      (items) => _filterCustomers(items, query),
    );
  }

  List<Customer> _filterCustomers(List<Customer> items, String query) {
    final q = query.trim();
    if (q.isEmpty) return items;
    return [
      for (final item in items)
        if (item.name.contains(q) ||
            (item.phone ?? '').contains(q) ||
            (item.area ?? '').contains(q))
          item,
    ];
  }

  Future<List<ProductCategory>> listCategories() async => CatalogCategories.all;

  Stream<List<ProductCategory>> watchCategories() =>
      Stream.value(CatalogCategories.all);

  Future<String> upsertProduct({
    required AppSession session,
    String? id,
    required String name,
    required String sku,
    String? categoryId,
    String? brand,
    String? description,
    String? packSize,
    required Money purchasePrice,
    required Money sellingPrice,
    required Quantity currentStock,
    required Quantity minimumStock,
    required String unit,
    String? customUnitLabel,
    bool isActive = true,
  }) async {
    final existing = id == null ? null : await _store.getProduct(id);
    final isCreate = existing == null;
    if (isCreate && !session.can(AppPermission.productsCreate)) {
      throw const PermissionException();
    }
    if (!isCreate && !session.can(AppPermission.productsUpdate)) {
      throw const PermissionException();
    }
    if (name.trim().isEmpty || sku.trim().isEmpty) {
      throw const ValidationException('اسم المنتج والرمز مطلوبان.');
    }
    if (unit.trim().isEmpty) {
      throw const ValidationException('الوحدة مطلوبة.');
    }
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final productId = id ?? newId();
    final product = Product(
      id: productId,
      name: name.trim(),
      sku: sku.trim(),
      categoryId: categoryId,
      brand: brand,
      description: description,
      packSize: packSize?.trim().isEmpty == true ? null : packSize?.trim(),
      purchasePrice: purchasePrice.toStorage(),
      sellingPrice: sellingPrice.toStorage(),
      currentStock: existing?.currentStock ?? currentStock.toStorage(),
      minimumStock: minimumStock.toStorage(),
      unit: unit.trim(),
      customUnitLabel: customUnitLabel,
      isActive: isActive,
      version: (existing?.version ?? 0) + 1,
      deviceId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.putProduct(product);
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: isCreate ? 'product.create' : 'product.update',
      entityType: 'product',
      entityId: productId,
      newValue: product.toMap(),
    );
    return productId;
  }

  Future<void> deleteProduct({
    required AppSession session,
    required String id,
  }) async {
    if (!session.can(AppPermission.productsDelete)) {
      throw const PermissionException();
    }
    final saleItems = await _store.listSaleItems(productId: id);
    final purchaseItems = await _store.listPurchaseItems(productId: id);
    if (saleItems.isNotEmpty || purchaseItems.isNotEmpty) {
      throw const ValidationException(
        'لا يمكن حذف المنتج لأنه مستخدم في فواتير بيع أو شراء.',
      );
    }
    await _store.deleteProduct(id);
    await _audit.write(
      userId: session.userId,
      deviceId: await _devices.deviceId(),
      action: 'product.delete',
      entityType: 'product',
      entityId: id,
    );
  }

  Future<String> findOrCreateCustomer({
    required AppSession session,
    String? id,
    String? name,
  }) async {
    if (id != null && id.isNotEmpty) return id;
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      throw const ValidationException('اسم العميل مطلوب.');
    }
    final existing = await searchCustomers(trimmed);
    for (final customer in existing) {
      if (customer.name == trimmed) return customer.id;
    }
    if (!session.can(AppPermission.customersCreate) &&
        !session.can(AppPermission.outstandingCreate) &&
        !session.can(AppPermission.salesCreate) &&
        !session.can(AppPermission.collectionsCreate)) {
      throw const PermissionException();
    }
    return upsertCustomer(
      session: session.copyWith(
        permissions: {...session.permissions, AppPermission.customersCreate},
      ),
      name: trimmed,
    );
  }

  Future<String> upsertCustomer({
    required AppSession session,
    String? id,
    required String name,
    String? phone,
    String? address,
    String? area,
    String? notes,
    bool isActive = true,
  }) async {
    final existing = id == null ? null : await _store.getCustomer(id);
    final isCreate = existing == null;
    if (isCreate && !session.can(AppPermission.customersCreate)) {
      throw const PermissionException();
    }
    if (!isCreate && !session.can(AppPermission.customersUpdate)) {
      throw const PermissionException();
    }
    if (name.trim().isEmpty) {
      throw const ValidationException('اسم العميل مطلوب.');
    }
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final customerId = id ?? newId();
    final customer = Customer(
      id: customerId,
      name: name.trim(),
      phone: phone,
      address: address,
      area: area,
      notes: notes,
      isActive: isActive,
      version: (existing?.version ?? 0) + 1,
      deviceId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.putCustomer(customer);
    if (existing == null) {
      await _store.putAccount(
        CustomerAccount(
          id: newId(),
          customerId: customerId,
          cachedBalance: Money.zero().toStorage(),
          deviceId: deviceId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: isCreate ? 'customer.create' : 'customer.update',
      entityType: 'customer',
      entityId: customerId,
      newValue: customer.toMap(),
    );
    return customerId;
  }
}
