import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../session.dart';
import 'audit_service.dart';

class CatalogService {
  CatalogService({
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

  Future<List<Product>> searchProducts(String query) {
    return _productsQuery(query).get();
  }

  Stream<List<Product>> watchProducts(String query) {
    return _productsQuery(query).watch();
  }

  SimpleSelectStatement<$ProductsTable, Product> _productsQuery(String query) {
    final q = query.trim();
    final select = _db.select(_db.products)
      ..where((t) => t.isDeleted.equals(false));
    if (q.isNotEmpty) {
      select.where(
        (t) => t.name.like('%$q%') | t.sku.like('%$q%') | t.brand.like('%$q%'),
      );
    }
    select.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return select;
  }

  Future<List<Customer>> searchCustomers(String query) {
    return _customersQuery(query).get();
  }

  Stream<List<Customer>> watchCustomers(String query) {
    return _customersQuery(query).watch();
  }

  SimpleSelectStatement<$CustomersTable, Customer> _customersQuery(
    String query,
  ) {
    final q = query.trim();
    final select = _db.select(_db.customers)
      ..where((t) => t.isDeleted.equals(false));
    if (q.isNotEmpty) {
      select.where(
        (t) => t.name.like('%$q%') | t.phone.like('%$q%') | t.area.like('%$q%'),
      );
    }
    select.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return select;
  }

  Future<List<ProductCategory>> listCategories() {
    return _categoriesQuery().get();
  }

  Stream<List<ProductCategory>> watchCategories() {
    return _categoriesQuery().watch();
  }

  SimpleSelectStatement<$ProductCategoriesTable, ProductCategory>
  _categoriesQuery() {
    final select = _db.select(_db.productCategories)
      ..where((t) => t.isDeleted.equals(false));
    select.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return select;
  }

  Future<String> upsertProduct({
    required AppSession session,
    String? id,
    required String name,
    required String sku,
    String? categoryId,
    String? brand,
    String? description,
    required Money purchasePrice,
    required Money sellingPrice,
    required Quantity currentStock,
    required Quantity minimumStock,
    required String unit,
    String? customUnitLabel,
    bool isActive = true,
  }) async {
    final isCreate = id == null;
    if (isCreate && !session.can(AppPermission.productsCreate)) {
      throw const PermissionException();
    }
    if (!isCreate && !session.can(AppPermission.productsUpdate)) {
      throw const PermissionException();
    }
    if (name.trim().isEmpty || sku.trim().isEmpty) {
      throw const ValidationException('اسم المنتج والرمز مطلوبان.');
    }

    return _db.transaction(() async {
      final now = DateTime.now().toUtc();
      final deviceId = await _metadata.deviceId();
      final productId = id ?? newId();
      final existing = id == null
          ? null
          : await (_db.select(
              _db.products,
            )..where((t) => t.id.equals(id))).getSingleOrNull();

      final companion = ProductsCompanion(
        id: Value(productId),
        name: Value(name.trim()),
        sku: Value(sku.trim()),
        categoryId: Value(categoryId),
        brand: Value(brand),
        description: Value(description),
        purchasePrice: Value(purchasePrice.toStorage()),
        sellingPrice: Value(sellingPrice.toStorage()),
        currentStock: Value(existing?.currentStock ?? currentStock.toStorage()),
        minimumStock: Value(minimumStock.toStorage()),
        unit: Value(unit),
        customUnitLabel: Value(customUnitLabel),
        isActive: Value(isActive),
        version: Value((existing?.version ?? 0) + 1),
        deviceId: Value(deviceId),
        createdAt: Value(existing?.createdAt ?? now),
        updatedAt: Value(now),
        isDeleted: const Value(false),
      );

      await _db.into(_db.products).insertOnConflictUpdate(companion);

      final payload = {
        'id': productId,
        'name': name.trim(),
        'sku': sku.trim(),
        'category_id': categoryId,
        'brand': brand,
        'description': description,
        'purchase_price': purchasePrice.toStorage(),
        'selling_price': sellingPrice.toStorage(),
        'current_stock': existing?.currentStock ?? currentStock.toStorage(),
        'minimum_stock': minimumStock.toStorage(),
        'unit': unit,
        'custom_unit_label': customUnitLabel,
        'is_active': isActive,
        'version': (existing?.version ?? 0) + 1,
        'device_id': deviceId,
      };

      await _audit.write(
        userId: session.userId,
        deviceId: deviceId,
        action: isCreate ? 'product.create' : 'product.update',
        entityType: 'product',
        entityId: productId,
        oldValue: existing == null
            ? null
            : {
                'name': existing.name,
                'selling_price': existing.sellingPrice,
                'sku': existing.sku,
              },
        newValue: payload,
      );
      await _queue.enqueue(
        entityType: SyncEntityType.product,
        entityId: productId,
        operation: isCreate
            ? SyncOperationType.create
            : SyncOperationType.update,
        payload: payload,
        operationId: newId(),
      );
      return productId;
    });
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
    final existing = await _customersQuery(trimmed).get();
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
    final isCreate = id == null;
    if (isCreate && !session.can(AppPermission.customersCreate)) {
      throw const PermissionException();
    }
    if (!isCreate && !session.can(AppPermission.customersUpdate)) {
      throw const PermissionException();
    }
    if (name.trim().isEmpty) {
      throw const ValidationException('اسم العميل مطلوب.');
    }

    return _db.transaction(() async {
      final now = DateTime.now().toUtc();
      final deviceId = await _metadata.deviceId();
      final customerId = id ?? newId();
      final existing = id == null
          ? null
          : await (_db.select(
              _db.customers,
            )..where((t) => t.id.equals(id))).getSingleOrNull();

      await _db
          .into(_db.customers)
          .insertOnConflictUpdate(
            CustomersCompanion(
              id: Value(customerId),
              name: Value(name.trim()),
              phone: Value(phone),
              address: Value(address),
              area: Value(area),
              notes: Value(notes),
              isActive: Value(isActive),
              version: Value((existing?.version ?? 0) + 1),
              deviceId: Value(deviceId),
              createdAt: Value(existing?.createdAt ?? now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
            ),
          );

      if (existing == null) {
        await _db
            .into(_db.customerAccounts)
            .insert(
              CustomerAccountsCompanion.insert(
                id: newId(),
                customerId: customerId,
                cachedBalance: Money.zero().toStorage(),
                deviceId: Value(deviceId),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      final payload = {
        'id': customerId,
        'name': name.trim(),
        'phone': phone,
        'address': address,
        'area': area,
        'notes': notes,
        'is_active': isActive,
        'version': (existing?.version ?? 0) + 1,
        'device_id': deviceId,
      };
      await _audit.write(
        userId: session.userId,
        deviceId: deviceId,
        action: isCreate ? 'customer.create' : 'customer.update',
        entityType: 'customer',
        entityId: customerId,
        oldValue: existing == null
            ? null
            : {'name': existing.name, 'phone': existing.phone},
        newValue: payload,
      );
      await _queue.enqueue(
        entityType: SyncEntityType.customer,
        entityId: customerId,
        operation: isCreate
            ? SyncOperationType.create
            : SyncOperationType.update,
        payload: payload,
        operationId: newId(),
      );
      return customerId;
    });
  }

  Future<String> upsertCategory({
    required AppSession session,
    String? id,
    required String name,
    String? description,
  }) async {
    if (!session.can(AppPermission.productsCreate) &&
        !session.can(AppPermission.productsUpdate)) {
      throw const PermissionException();
    }
    return _db.transaction(() async {
      final now = DateTime.now().toUtc();
      final deviceId = await _metadata.deviceId();
      final categoryId = id ?? newId();
      await _db
          .into(_db.productCategories)
          .insertOnConflictUpdate(
            ProductCategoriesCompanion(
              id: Value(categoryId),
              name: Value(name.trim()),
              description: Value(description),
              version: const Value(1),
              deviceId: Value(deviceId),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              isActive: const Value(true),
            ),
          );
      await _queue.enqueue(
        entityType: SyncEntityType.category,
        entityId: categoryId,
        operation: id == null
            ? SyncOperationType.create
            : SyncOperationType.update,
        payload: {
          'id': categoryId,
          'name': name.trim(),
          'description': description,
        },
        operationId: newId(),
      );
      return categoryId;
    });
  }
}
