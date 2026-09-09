import 'dart:async';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/utils/stream_utils.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/user_identity.dart';
import 'erp_map.dart';
import 'erp_store.dart';

class FirestoreErpStore implements ErpStore {
  static const companyId = 'al_nomani';

  DocumentReference<Map<String, dynamic>> get _company =>
      FirebaseFirestore.instance.collection('companies').doc(companyId);

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _company.collection(name);

  final _localChanges = StreamController<void>.broadcast();
  Stream<void>? _watchChanges;
  Future<void>? _ready;
  final _lists = <String, List<Object>>{};
  final _inflight = <String, Future<List<Object>>>{};
  final _generations = <String, int>{};
  String? _lastDataRev;
  Timer? _refreshNotify;
  final _preferServer = <String>{};

  Future<void> ensureReady() {
    return _ready ??= _ensureReadyOnce();
  }

  Future<void> _ensureReadyOnce() async {
    if (!await FirebaseBootstrap.ensure()) {
      _ready = null;
      throw StateError(FirebaseBootstrap.lastError ?? 'Firebase غير جاهز.');
    }
    await _company.set({
      'name': 'مجموعة النعماني',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<T> _parseSnap<T>(
    QuerySnapshot<Map<String, dynamic>> snap,
    T Function(Map<String, dynamic> data, String id) parse,
    bool Function(T value) keep,
  ) {
    return [
      for (final doc in snap.docs)
        if (doc.data()['operation'] != 'delete') parse(doc.data(), doc.id),
    ].where(keep).toList();
  }

  void _remember<T>(String name, List<T> rows) {
    _lists[name] = rows.cast<Object>();
  }

  int _bumpGeneration(String name) {
    final next = (_generations[name] ?? 0) + 1;
    _generations[name] = next;
    return next;
  }

  void _invalidate(String name) {
    _lists.remove(name);
    _inflight.remove(name);
    _bumpGeneration(name);
    _preferServer.add(name);
  }

  void _upsertCached<T>(
    String name,
    T row,
    bool Function(T value) sameId,
    bool Function(T value) keep,
    int Function(T a, T b)? compare,
  ) {
    final rows = <T>[
      for (final item in (_lists[name]?.cast<T>() ?? <T>[]))
        if (!sameId(item)) item,
    ];
    if (keep(row)) rows.add(row);
    if (compare != null) rows.sort(compare);
    _remember(name, rows);
    _preferServer.remove(name);
  }

  void _scheduleRemoteRefreshNotify() {
    _refreshNotify?.cancel();
    _refreshNotify = Timer(const Duration(milliseconds: 350), () {
      if (!_localChanges.isClosed) _localChanges.add(null);
    });
  }

  Future<void> _touchCompanyRev(String section) async {
    try {
      await _company.set({
        'dataRev': FieldValue.increment(1),
        'lastSection': section,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<List<Object>> _readCol<T>(
    String name,
    T Function(Map<String, dynamic> data, String id) parse,
    bool Function(T value) keep,
    Source source,
  ) async {
    final gen = _generations[name] ?? 0;
    final snap = await _col(name).get(GetOptions(source: source));
    if ((_generations[name] ?? 0) != gen) {
      final cached = _lists[name];
      if (cached != null) return cached;
    }
    final rows = _parseSnap(snap, parse, keep);
    if ((_generations[name] ?? 0) == gen) {
      _remember(name, rows);
    }
    return rows.cast<Object>();
  }

  Stream<List<T>> _watchCol<T>(
    String name,
    T Function(Map<String, dynamic> data, String id) parse,
    bool Function(T value) keep,
  ) async* {
    yield await _listCol(name, parse, keep);
    await for (final _ in watchChanges()) {
      yield await _listCol(name, parse, keep);
    }
  }

  Future<List<T>> _listCol<T>(
    String name,
    T Function(Map<String, dynamic> data, String id) parse,
    bool Function(T value) keep,
  ) async {
    await ensureReady();
    final cached = _lists[name];
    if (cached != null) {
      return cached.cast<T>();
    }
    final pending = _inflight[name];
    if (pending != null) {
      return (await pending).cast<T>();
    }
    final future = () async {
      final forceServer = _preferServer.remove(name);
      if (!forceServer) {
        try {
          final fromCache = await _readCol(name, parse, keep, Source.cache);
          if (fromCache.isNotEmpty) {
            unawaited(() async {
              try {
                await _readCol(name, parse, keep, Source.server);
                _scheduleRemoteRefreshNotify();
              } catch (_) {}
            }());
            return fromCache;
          }
        } catch (_) {}
      }
      return _readCol(name, parse, keep, Source.server);
    }();
    _inflight[name] = future;
    try {
      return (await future).cast<T>();
    } finally {
      _inflight.remove(name);
    }
  }

  Future<void> prefetchHotCollections() async {
    await ensureReady();
    await Future.wait([
      listProducts(),
      listCustomers(),
      listSales(),
      listCollections(),
      listAccounts(),
    ]);
    unawaited(
      Future.wait([
        listSaleItems(),
        listMovements(),
        listExpenses(),
      ]),
    );
  }

  T? _cachedById<T>(String name, bool Function(T value) match) {
    final cached = _lists[name];
    if (cached == null) return null;
    for (final row in cached.cast<T>()) {
      if (match(row)) return row;
    }
    return null;
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
    _invalidate(section);
    _localChanges.add(null);
    unawaited(_touchCompanyRev(section));
  }

  Future<void> _delete(String section, String id) async {
    await ensureReady();
    await _col(section).doc(id).delete();
    _invalidate(section);
    _localChanges.add(null);
    unawaited(_touchCompanyRev(section));
  }

  @override
  Stream<void> watchChanges() {
    return _watchChanges ??= mergeAndDebounce([
      _localChanges.stream,
      _company.snapshots().where((snap) {
        final data = snap.data();
        final rev = '${data?['dataRev'] ?? ''}';
        if (_lastDataRev == null) {
          _lastDataRev = rev;
          return false;
        }
        if (rev == _lastDataRev) return false;
        _lastDataRev = rev;
        final section = data?['lastSection'] as String?;
        if (section != null && section.isNotEmpty) {
          _invalidate(section);
        } else {
          _lists.clear();
          _inflight.clear();
        }
        return true;
      }).map((_) {}),
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
    final cached = _cachedById<Product>('products', (row) => row.id == id);
    if (cached != null) return cached;
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
    final cached = _cachedById<Customer>('customers', (row) => row.id == id);
    if (cached != null) return cached;
    await ensureReady();
    final doc = await _col('customers').doc(id).get();
    if (!doc.exists) return null;
    return customerFromMap(doc.data()!, doc.id);
  }

  @override
  Future<void> putCustomer(Customer customer) =>
      _put('customers', customer.id, customer.toMap());
  @override
  Future<void> deleteCustomer(String id) => _delete('customers', id);

  @override
  Future<List<CustomerAccount>> listAccounts() =>
      _listCol('accounts', accountFromMap, (_) => true);
  @override
  Future<CustomerAccount?> getAccountByCustomer(String customerId) async {
    final accounts = await listAccounts();
    final byCustomer = {
      for (final account in accounts) account.customerId: account,
    };
    return byCustomer[customerId];
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
    final cached = _cachedById<Sale>('sales', (row) => row.id == id);
    if (cached != null) return cached;
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
    final cached = _cachedById<AppUser>('users', (row) => row.id == id);
    if (cached != null) return cached;
    await ensureReady();
    final doc = await _col('users').doc(id).get();
    if (!doc.exists) return null;
    return userFromMap(doc.data()!, doc.id);
  }

  @override
  Future<AppUser?> getUserByUsername(String username) async {
    return UserIdentity.pickByUsername(await listUsers(), username);
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
    final cached = _cachedById<Supplier>('suppliers', (row) => row.id == id);
    if (cached != null) return cached;
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
    final cached = _cachedById<Purchase>('purchases', (row) => row.id == id);
    if (cached != null) return cached;
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
  Future<List<Expense>> listExpenses() async {
    final rows = await _listCol('expenses', expenseFromMap, (e) => !e.isDeleted);
    return rows..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  @override
  Stream<List<Expense>> watchExpenses() {
    return _watchCol('expenses', expenseFromMap, (e) => !e.isDeleted).map((rows) {
      rows.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return rows;
    });
  }

  @override
  Future<Expense?> getExpense(String id) async {
    final cached = _cachedById<Expense>('expenses', (row) => row.id == id);
    if (cached != null) return cached;
    await ensureReady();
    final doc = await _col('expenses').doc(id).get();
    if (!doc.exists) return null;
    return expenseFromMap(doc.data()!, doc.id);
  }

  @override
  Future<void> putExpense(Expense expense) async {
    final previous = _lists['expenses']?.cast<Expense>().toList();
    await _put(
      'expenses',
      expense.id,
      expense.toMap(),
      operation: expense.isDeleted ? 'delete' : 'update',
    );
    if (previous == null) return;
    _remember('expenses', previous);
    _upsertCached<Expense>(
      'expenses',
      expense,
      (row) => row.id == expense.id,
      (row) => !row.isDeleted,
      (a, b) => b.occurredAt.compareTo(a.occurredAt),
    );
  }

  @override
  Future<String?> getSetting(String key) async {
    final settings = await listSettings();
    for (final row in settings) {
      if (row.key == key) return row.value;
    }
    return null;
  }

  @override
  Future<void> putSetting(String key, String value) => _put('settings', key, {
    'key': key,
    'value': value,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'version': 1,
  });

  @override
  Future<List<AppSetting>> listSettings() {
    return _listCol(
      'settings',
      (data, id) => AppSetting(
        key: id,
        value: mapText(data, const ['value']),
        updatedAt: mapDate(data, const ['updated_at', 'updatedAt']),
      ),
      (_) => true,
    );
  }
}

