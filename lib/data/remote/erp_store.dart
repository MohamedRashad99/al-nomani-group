import '../../domain/entities/erp_models.dart';

abstract class ErpStore {
  Stream<void> watchChanges();

  Future<List<Product>> listProducts();
  Stream<List<Product>> watchProducts();
  Future<Product?> getProduct(String id);
  Future<void> putProduct(Product product);
  Future<void> deleteProduct(String id);

  Future<List<Customer>> listCustomers();
  Stream<List<Customer>> watchCustomers();
  Future<Customer?> getCustomer(String id);
  Future<void> putCustomer(Customer customer);
  Future<void> deleteCustomer(String id);

  Future<List<CustomerAccount>> listAccounts();
  Future<CustomerAccount?> getAccountByCustomer(String customerId);
  Future<void> putAccount(CustomerAccount account);

  Future<List<CustomerAccountTransaction>> listAccountTx({
    String? customerId,
    String? referenceId,
  });
  Future<void> putAccountTx(CustomerAccountTransaction tx);

  Future<List<Sale>> listSales();
  Stream<List<Sale>> watchSales();
  Future<Sale?> getSale(String id);
  Future<void> putSale(Sale sale);

  Future<List<SaleItem>> listSaleItems({String? saleId, String? productId});
  Future<void> putSaleItem(SaleItem item);

  Future<List<Collection>> listCollections();
  Stream<List<Collection>> watchCollections();
  Future<void> putCollection(Collection collection);

  Future<List<InventoryMovement>> listMovements({String? productId});
  Stream<List<InventoryMovement>> watchMovements({String? productId});
  Future<void> putMovement(InventoryMovement movement);

  Future<List<AppUser>> listUsers();
  Stream<List<AppUser>> watchUsers();
  Future<AppUser?> getUser(String id);
  Future<AppUser?> getUserByUsername(String username);
  Future<void> putUser(AppUser user);

  Future<void> putAudit(AuditLog log);
  Future<List<AuditLog>> listAudits();

  Future<List<Supplier>> listSuppliers();
  Stream<List<Supplier>> watchSuppliers();
  Future<Supplier?> getSupplier(String id);
  Future<void> putSupplier(Supplier supplier);
  Future<void> deleteSupplier(String id);

  Future<List<SupplierAccount>> listSupplierAccounts();
  Future<SupplierAccount?> getAccountBySupplier(String supplierId);
  Future<void> putSupplierAccount(SupplierAccount account);

  Future<List<SupplierAccountTransaction>> listSupplierTx({
    String? supplierId,
    String? referenceId,
  });
  Future<void> putSupplierTx(SupplierAccountTransaction tx);

  Future<List<Purchase>> listPurchases({String? supplierId});
  Stream<List<Purchase>> watchPurchases();
  Future<Purchase?> getPurchase(String id);
  Future<void> putPurchase(Purchase purchase);

  Future<List<PurchaseItem>> listPurchaseItems({
    String? purchaseId,
    String? productId,
  });
  Future<void> putPurchaseItem(PurchaseItem item);

  Future<String?> getSetting(String key);
  Future<void> putSetting(String key, String value);
  Future<List<AppSetting>> listSettings();
}
