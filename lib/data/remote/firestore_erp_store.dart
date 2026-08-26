import 'dart:async';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase/firebase_bootstrap.dart';
import '../../domain/entities/erp_models.dart';
import 'erp_map.dart';
import 'erp_store.dart';

class FirestoreErpStore implements ErpStore {
  static const companyId = 'al_nomani';

  DocumentReference<Map<String, dynamic>> get _company =>
      FirebaseFirestore.instance.collection('companies').doc(companyId);

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _company.collection(name);

  final _localChanges = StreamController<void>.broadcast();

  Future<void> ensureReady() async {
    if (!await FirebaseBootstrap.ensure()) {
      throw StateError(FirebaseBootstrap.lastError ?? 'Firebase غير جاهز.');
    }
    await _company.set({
      'name': 'مجموعة النعماني',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<T>> _watchCol<T>(
    String name,
    T Function(Map<String, dynamic> data, String id) parse,
    bool Function(T value) keep,
  ) {
    return _col(name).snapshots().map((snap) {
      return [
        for (final doc in snap.docs)
          if (doc.data()['operation'] != 'delete') parse(doc.data(), doc.id),
      ].where(keep).toList();
    });
  }

  Future<List<T>> _listCol<T>(
    String name,
    T Function(Map<String, dynamic> data, String id) parse,
    bool Function(T value) keep,
  ) async {
    await ensureReady();
    final snap = await _col(name).get();
    return [
      for (final doc in snap.docs)
        if (doc.data()['operation'] != 'delete') parse(doc.data(), doc.id),
    ].where(keep).toList();
  }

  Future<void> _put(
    String section,
    String id,
    Map<String, dynamic> payload, {
    String operation = 'update',
  }) async {
    await ensureReady();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final data = <String, dynamic>{
      ...payload,
      'id': id,
      'entityId': id,
      'section': section,
      'operationId': payload['operationId'] ?? newId(),
      'operation': operation,
      'version': payload['version'] ?? 1,
      'deviceId': payload['deviceId'] ?? payload['device_id'] ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    };
    await _col(section).doc(id).set(data, SetOptions(merge: true));
    _localChanges.add(null);
  }

  Future<void> _delete(String section, String id) async {
    await ensureReady();
    await _col(section).doc(id).delete();
    _localChanges.add(null);
  }

  @override
  Stream<void> watchChanges() {
    return StreamGroup.merge([
      _localChanges.stream,
      _col('products').snapshots().map((_) {}),
      _col('customers').snapshots().map((_) {}),
      _col('sales').snapshots().map((_) {}),
      _col('collections').snapshots().map((_) {}),
      _col('accounts').snapshots().map((_) {}),
      _col('inventory').snapshots().map((_) {}),
      _col('suppliers').snapshots().map((_) {}),
      _col('purchases').snapshots().map((_) {}),
    ]);
  }

  @override
  Future<List<Product>> listProducts() =>
      _listCol('products', productFromMap, (e) => !e.isDeleted);
  @override
  Stream<List<Product>> watchProducts() =>
      _watchCol('products', productFromMap, (e) => !e.isDeleted);
  @override
  Future<Product?> getProduct(String id) async {
    await ensureReady();
    final doc = await _col('products').doc(id).get();
    if (!doc.exists) return null;
    return productFromMap(doc.data()!, doc.id);
  }

  @override
  Future<void> putProduct(Product product) =>
      _put('products', product.id, product.toMap(), operation: 'update');
  @override
  Future<void> deleteProduct(String id) => _delete('products', id);

  @override
  Future<List<Customer>> listCustomers() =>
      _listCol('customers', customerFromMap, (e) => !e.isDeleted);
  @override
  Stream<List<Customer>> watchCustomers() =>
      _watchCol('customers', customerFromMap, (e) => !e.isDeleted);
  @override
  Future<Customer?> getCustomer(String id) async {
    await ensureReady();
    final doc = await _col('customers').doc(id).get();
    if (!doc.exists) return null;
    return customerFromMap(doc.data()!, doc.id);
  }

  @override
  Future<void> putCustomer(Customer customer) =>
      _put('customers', customer.id, customer.toMap());

  @override
  Future<List<CustomerAccount>> listAccounts() =>
      _listCol('accounts', accountFromMap, (_) => true);
  @override
  Future<CustomerAccount?> getAccountByCustomer(String customerId) async {
    final accounts = await listAccounts();
    for (final account in accounts) {
      if (account.customerId == customerId) return account;
    }
    return null;
  }

  @override
  Future<void> putAccount(CustomerAccount account) =>
      _put('accounts', account.id, account.toMap());

  @override
  Future<List<CustomerAccountTransaction>> listAccountTx({
    String? customerId,
    String? referenceId,
  }) async {
    final rows = await _listCol(
      'account_transactions',
      accountTxFromMap,
      (_) => true,
    );
    return rows.where((tx) {
      if (customerId != null && tx.customerId != customerId) return false;
      if (referenceId != null && tx.referenceId != referenceId) return false;
      return true;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> putAccountTx(CustomerAccountTransaction tx) =>
      _put('account_transactions', tx.id, tx.toMap(), operation: 'create');

  @override
  Future<List<Sale>> listSales() async {
    final rows = await _listCol('sales', saleFromMap, (e) => !e.isDeleted);
    rows.sort((a, b) => b.soldAt.compareTo(a.soldAt));
    return rows;
  }

  @override
  Stream<List<Sale>> watchSales() {
    return _watchCol('sales', saleFromMap, (e) => !e.isDeleted).map((rows) {
      rows.sort((a, b) => b.soldAt.compareTo(a.soldAt));
      return rows;
    });
  }

  @override
  Future<Sale?> getSale(String id) async {
    await ensureReady();
    final doc = await _col('sales').doc(id).get();
    if (!doc.exists) return null;
    return saleFromMap(doc.data()!, doc.id);
  }

  @override
  Future<void> putSale(Sale sale) =>
      _put('sales', sale.id, sale.toMap(), operation: sale.status == 'cancelled' ? 'cancel' : 'update');

  @override
  Future<List<SaleItem>> listSaleItems({String? saleId, String? productId}) async {
    final rows = await _listCol('sale_items', saleItemFromMap, (_) => true);
    return [
      for (final item in rows)
        if ((saleId == null || item.saleId == saleId) &&
            (productId == null || item.productId == productId))
          item,
    ];
  }

  @override
  Future<void> putSaleItem(SaleItem item) =>
      _put('sale_items', item.id, item.toMap(), operation: 'create');

  @override
  Future<List<Collection>> listCollections() async {
    final rows = await _listCol(
      'collections',
      collectionFromMap,
      (e) => !e.isDeleted,
    );
    rows.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    return rows;
  }

  @override
  Stream<List<Collection>> watchCollections() {
    return _watchCol(
      'collections',
      collectionFromMap,
      (e) => !e.isDeleted,
    ).map((rows) {
      rows.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
      return rows;
    });
  }

  @override
  Future<void> putCollection(Collection collection) =>
      _put('collections', collection.id, collection.toMap(), operation: 'create');

  @override
  Future<List<InventoryMovement>> listMovements({String? productId}) async {
    final rows = await _listCol('inventory', movementFromMap, (_) => true);
    return [
      for (final row in rows)
        if (productId == null || row.productId == productId) row,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Stream<List<InventoryMovement>> watchMovements({String? productId}) {
    return _watchCol('inventory', movementFromMap, (_) => true).map((rows) {
      return [
        for (final row in rows)
          if (productId == null || row.productId == productId) row,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Future<void> putMovement(InventoryMovement movement) =>
      _put('inventory', movement.id, movement.toMap(), operation: 'create');

  @override
  Future<List<AppUser>> listUsers() =>
      _listCol('users', userFromMap, (e) => !e.isDeleted);
  @override
  Stream<List<AppUser>> watchUsers() =>
      _watchCol('users', userFromMap, (e) => !e.isDeleted);
  @override
  Future<AppUser?> getUser(String id) async {
    await ensureReady();
    final doc = await _col('users').doc(id).get();
    if (!doc.exists) return null;
    return userFromMap(doc.data()!, doc.id);
  }

  @override
  Future<AppUser?> getUserByUsername(String username) async {
    final needle = username.trim();
    final users = await listUsers();
    for (final user in users) {
      if (user.username == needle) return user;
    }
    return null;
  }

  @override
  Future<void> putUser(AppUser user) =>
      _put('users', user.id, user.toMap(), operation: 'update');

  @override
  Future<void> putAudit(AuditLog log) =>
      _put('audit_logs', log.id, log.toMap(), operation: 'create');
  @override
  Future<List<AuditLog>> listAudits() =>
      _listCol('audit_logs', auditFromMap, (_) => true);

  @override
  Future<List<Supplier>> listSuppliers() =>
      _listCol('suppliers', supplierFromMap, (e) => !e.isDeleted);
  @override
  Stream<List<Supplier>> watchSuppliers() =>
      _watchCol('suppliers', supplierFromMap, (e) => !e.isDeleted);
  @override
  Future<Supplier?> getSupplier(String id) async {
    await ensureReady();
    final doc = await _col('suppliers').doc(id).get();
    if (!doc.exists) return null;
    return supplierFromMap(doc.data()!, doc.id);
  }

  @override
  Future<void> putSupplier(Supplier supplier) =>
      _put('suppliers', supplier.id, supplier.toMap());
  @override
  Future<void> deleteSupplier(String id) => _delete('suppliers', id);

  @override
  Future<List<SupplierAccount>> listSupplierAccounts() =>
      _listCol('supplier_accounts', supplierAccountFromMap, (_) => true);
  @override
  Future<SupplierAccount?> getAccountBySupplier(String supplierId) async {
    final accounts = await listSupplierAccounts();
    for (final account in accounts) {
      if (account.supplierId == supplierId) return account;
    }
    return null;
  }

  @override
  Future<void> putSupplierAccount(SupplierAccount account) =>
      _put('supplier_accounts', account.id, account.toMap());

  @override
  Future<List<SupplierAccountTransaction>> listSupplierTx({
    String? supplierId,
    String? referenceId,
  }) async {
    final rows = await _listCol(
      'supplier_account_transactions',
      supplierTxFromMap,
      (_) => true,
    );
    return rows.where((tx) {
      if (supplierId != null && tx.supplierId != supplierId) return false;
      if (referenceId != null && tx.referenceId != referenceId) return false;
      return true;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> putSupplierTx(SupplierAccountTransaction tx) => _put(
    'supplier_account_transactions',
    tx.id,
    tx.toMap(),
    operation: 'create',
  );

  @override
  Future<List<Purchase>> listPurchases({String? supplierId}) async {
    final rows = await _listCol('purchases', purchaseFromMap, (e) => !e.isDeleted);
    return [
      for (final row in rows)
        if (supplierId == null || row.supplierId == supplierId) row,
    ]..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
  }

  @override
  Stream<List<Purchase>> watchPurchases() {
    return _watchCol('purchases', purchaseFromMap, (e) => !e.isDeleted).map((
      rows,
    ) {
      rows.sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
      return rows;
    });
  }

  @override
  Future<Purchase?> getPurchase(String id) async {
    await ensureReady();
    final doc = await _col('purchases').doc(id).get();
    if (!doc.exists) return null;
    return purchaseFromMap(doc.data()!, doc.id);
  }

  @override
  Future<void> putPurchase(Purchase purchase) => _put(
    'purchases',
    purchase.id,
    purchase.toMap(),
    operation: purchase.status == 'cancelled' ? 'cancel' : 'update',
  );

  @override
  Future<List<PurchaseItem>> listPurchaseItems({
    String? purchaseId,
    String? productId,
  }) async {
    final rows = await _listCol('purchase_items', purchaseItemFromMap, (_) => true);
    return [
      for (final item in rows)
        if ((purchaseId == null || item.purchaseId == purchaseId) &&
            (productId == null || item.productId == productId))
          item,
    ];
  }

  @override
  Future<void> putPurchaseItem(PurchaseItem item) =>
      _put('purchase_items', item.id, item.toMap(), operation: 'create');

  @override
  Future<String?> getSetting(String key) async {
    await ensureReady();
    final doc = await _col('settings').doc(key).get();
    if (!doc.exists) return null;
    return mapTextOrNull(doc.data()!, const ['value']);
  }

  @override
  Future<void> putSetting(String key, String value) => _put('settings', key, {
    'key': key,
    'value': value,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'version': 1,
  });

  @override
  Future<List<AppSetting>> listSettings() async {
    await ensureReady();
    final snap = await _col('settings').get();
    return [
      for (final doc in snap.docs)
        AppSetting(
          key: doc.id,
          value: mapText(doc.data(), const ['value']),
          updatedAt: mapDate(doc.data(), const ['updated_at', 'updatedAt']),
        ),
    ];
  }
}

class StreamGroup {
  static Stream<void> merge(List<Stream<void>> streams) {
    final controller = StreamController<void>.broadcast();
    final subs = <StreamSubscription<void>>[];
    for (final stream in streams) {
      subs.add(stream.listen((_) {
        if (!controller.isClosed) controller.add(null);
      }));
    }
    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }
}
