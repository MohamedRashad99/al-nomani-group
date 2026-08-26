import 'dart:async';

import '../../domain/entities/erp_models.dart';
import 'erp_store.dart';

class MemoryErpStore implements ErpStore {
  final _changes = StreamController<void>.broadcast();
  final products = <String, Product>{};
  final customers = <String, Customer>{};
  final accounts = <String, CustomerAccount>{};
  final accountTx = <String, CustomerAccountTransaction>{};
  final sales = <String, Sale>{};
  final saleItems = <String, SaleItem>{};
  final collections = <String, Collection>{};
  final movements = <String, InventoryMovement>{};
  final users = <String, AppUser>{};
  final audits = <String, AuditLog>{};
  final suppliers = <String, Supplier>{};
  final supplierAccounts = <String, SupplierAccount>{};
  final supplierTx = <String, SupplierAccountTransaction>{};
  final purchases = <String, Purchase>{};
  final purchaseItems = <String, PurchaseItem>{};
  final settings = <String, AppSetting>{};

  void _touch() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() load) async* {
    yield load();
    await for (final _ in _changes.stream) {
      yield load();
    }
  }

  @override
  Stream<void> watchChanges() => _changes.stream;

  List<Product> _products() =>
      products.values.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  List<Customer> _customers() =>
      customers.values.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  List<Supplier> _suppliers() =>
      suppliers.values.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  List<Sale> _sales() => sales.values.where((e) => !e.isDeleted).toList()
    ..sort((a, b) => b.soldAt.compareTo(a.soldAt));

  List<Purchase> _purchases() =>
      purchases.values.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));

  List<Collection> _collections() =>
      collections.values.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));

  List<AppUser> _users() => users.values.where((e) => !e.isDeleted).toList();

  @override
  Future<List<Product>> listProducts() async => _products();
  @override
  Stream<List<Product>> watchProducts() => _watch(_products);
  @override
  Future<Product?> getProduct(String id) async => products[id];
  @override
  Future<void> putProduct(Product product) async {
    products[product.id] = product;
    _touch();
  }

  @override
  Future<void> deleteProduct(String id) async {
    products.remove(id);
    _touch();
  }

  @override
  Future<List<Customer>> listCustomers() async => _customers();
  @override
  Stream<List<Customer>> watchCustomers() => _watch(_customers);
  @override
  Future<Customer?> getCustomer(String id) async => customers[id];
  @override
  Future<void> putCustomer(Customer customer) async {
    customers[customer.id] = customer;
    _touch();
  }

  @override
  Future<List<CustomerAccount>> listAccounts() async => accounts.values.toList();
  @override
  Future<CustomerAccount?> getAccountByCustomer(String customerId) async {
    for (final account in accounts.values) {
      if (account.customerId == customerId) return account;
    }
    return null;
  }

  @override
  Future<void> putAccount(CustomerAccount account) async {
    accounts[account.id] = account;
    _touch();
  }

  @override
  Future<List<CustomerAccountTransaction>> listAccountTx({
    String? customerId,
    String? referenceId,
  }) async {
    return accountTx.values.where((tx) {
      if (customerId != null && tx.customerId != customerId) return false;
      if (referenceId != null && tx.referenceId != referenceId) return false;
      return true;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> putAccountTx(CustomerAccountTransaction tx) async {
    accountTx[tx.id] = tx;
    _touch();
  }

  @override
  Future<List<Sale>> listSales() async => _sales();
  @override
  Stream<List<Sale>> watchSales() => _watch(_sales);
  @override
  Future<Sale?> getSale(String id) async => sales[id];
  @override
  Future<void> putSale(Sale sale) async {
    sales[sale.id] = sale;
    _touch();
  }

  @override
  Future<List<SaleItem>> listSaleItems({String? saleId, String? productId}) async {
    return saleItems.values.where((item) {
      if (saleId != null && item.saleId != saleId) return false;
      if (productId != null && item.productId != productId) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> putSaleItem(SaleItem item) async {
    saleItems[item.id] = item;
    _touch();
  }

  @override
  Future<List<Collection>> listCollections() async => _collections();
  @override
  Stream<List<Collection>> watchCollections() => _watch(_collections);
  @override
  Future<void> putCollection(Collection collection) async {
    collections[collection.id] = collection;
    _touch();
  }

  @override
  Future<List<InventoryMovement>> listMovements({String? productId}) async {
    return movements.values.where((row) {
      if (productId != null && row.productId != productId) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Stream<List<InventoryMovement>> watchMovements({String? productId}) {
    return _watch(() => movements.values.where((row) {
      if (productId != null && row.productId != productId) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  @override
  Future<void> putMovement(InventoryMovement movement) async {
    movements[movement.id] = movement;
    _touch();
  }

  @override
  Future<List<AppUser>> listUsers() async => _users();
  @override
  Stream<List<AppUser>> watchUsers() => _watch(_users);
  @override
  Future<AppUser?> getUser(String id) async => users[id];
  @override
  Future<AppUser?> getUserByUsername(String username) async {
    final needle = username.trim();
    for (final user in users.values) {
      if (user.username == needle && !user.isDeleted) return user;
    }
    return null;
  }

  @override
  Future<void> putUser(AppUser user) async {
    users[user.id] = user;
    _touch();
  }

  @override
  Future<void> putAudit(AuditLog log) async {
    audits[log.id] = log;
    _touch();
  }

  @override
  Future<List<AuditLog>> listAudits() async => audits.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<List<Supplier>> listSuppliers() async => _suppliers();
  @override
  Stream<List<Supplier>> watchSuppliers() => _watch(_suppliers);
  @override
  Future<Supplier?> getSupplier(String id) async => suppliers[id];
  @override
  Future<void> putSupplier(Supplier supplier) async {
    suppliers[supplier.id] = supplier;
    _touch();
  }

  @override
  Future<void> deleteSupplier(String id) async {
    suppliers.remove(id);
    _touch();
  }

  @override
  Future<List<SupplierAccount>> listSupplierAccounts() async =>
      supplierAccounts.values.toList();
  @override
  Future<SupplierAccount?> getAccountBySupplier(String supplierId) async {
    for (final account in supplierAccounts.values) {
      if (account.supplierId == supplierId) return account;
    }
    return null;
  }

  @override
  Future<void> putSupplierAccount(SupplierAccount account) async {
    supplierAccounts[account.id] = account;
    _touch();
  }

  @override
  Future<List<SupplierAccountTransaction>> listSupplierTx({
    String? supplierId,
    String? referenceId,
  }) async {
    return supplierTx.values.where((tx) {
      if (supplierId != null && tx.supplierId != supplierId) return false;
      if (referenceId != null && tx.referenceId != referenceId) return false;
      return true;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> putSupplierTx(SupplierAccountTransaction tx) async {
    supplierTx[tx.id] = tx;
    _touch();
  }

  @override
  Future<List<Purchase>> listPurchases({String? supplierId}) async {
    return _purchases().where((row) {
      if (supplierId != null && row.supplierId != supplierId) return false;
      return true;
    }).toList();
  }

  @override
  Stream<List<Purchase>> watchPurchases() => _watch(_purchases);
  @override
  Future<Purchase?> getPurchase(String id) async => purchases[id];
  @override
  Future<void> putPurchase(Purchase purchase) async {
    purchases[purchase.id] = purchase;
    _touch();
  }

  @override
  Future<List<PurchaseItem>> listPurchaseItems({
    String? purchaseId,
    String? productId,
  }) async {
    return purchaseItems.values.where((item) {
      if (purchaseId != null && item.purchaseId != purchaseId) return false;
      if (productId != null && item.productId != productId) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> putPurchaseItem(PurchaseItem item) async {
    purchaseItems[item.id] = item;
    _touch();
  }

  @override
  Future<String?> getSetting(String key) async => settings[key]?.value;
  @override
  Future<void> putSetting(String key, String value) async {
    settings[key] = AppSetting(key: key, value: value, updatedAt: DateTime.now().toUtc());
    _touch();
  }

  @override
  Future<List<AppSetting>> listSettings() async => settings.values.toList();
}
