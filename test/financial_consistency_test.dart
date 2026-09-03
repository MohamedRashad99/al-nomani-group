import 'package:al_nomani_group/core/config/app_config.dart';
import 'package:al_nomani_group/core/di/injector.dart';
import 'package:al_nomani_group/data/remote/memory_erp_store.dart';
import 'package:al_nomani_group/domain/models/purchase_draft.dart';
import 'package:al_nomani_group/domain/models/sale_draft.dart';
import 'package:al_nomani_group/domain/services/catalog_service.dart';
import 'package:al_nomani_group/domain/services/collection_service.dart';
import 'package:al_nomani_group/domain/services/inventory_service.dart';
import 'package:al_nomani_group/domain/services/purchase_service.dart';
import 'package:al_nomani_group/domain/services/sale_service.dart';
import 'package:al_nomani_group/domain/services/seed_service.dart';
import 'package:al_nomani_group/domain/services/supplier_service.dart';
import 'package:al_nomani_group/domain/session.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig _config() => const AppConfig(
  environment: 'test',
  apiBaseUrl: 'http://127.0.0.1:9',
  syncIntervalDays: 5,
  syncMode: SyncMode.scheduled,
  allowSeed: true,
  googleLiveSpreadsheetId: 'test',
  appVersion: AppVersions.appVersion,
  databaseVersion: AppVersions.databaseVersion,
  syncProtocolVersion: AppVersions.syncProtocolVersion,
);

AppSession admin() => AppSession(
  userId: 'test-admin',
  username: 'admin',
  displayName: 'مدير',
  roleName: AppRole.admin,
  permissions: AppPermission.all.toSet(),
  expiresAt: DateTime.now().add(const Duration(days: 1)),
  isOfflineVerified: true,
);

Future<MemoryErpStore> readyStore() async {
  FlutterSecureStorage.setMockInitialValues({});
  final store = MemoryErpStore();
  await configureDependencies(config: _config(), store: store);
  await sl<SeedService>().ensureDemoAdminIdentity();
  final session = admin();
  await sl<CatalogService>().upsertProduct(
    session: session,
    id: 'p-a',
    name: 'منتج أ',
    sku: 'A',
    purchasePrice: Money.parse('10'),
    sellingPrice: Money.parse('15'),
    currentStock: Quantity.parse('100'),
    minimumStock: Quantity.parse('5'),
    unit: 'كغ',
    packSize: '1',
  );
  await sl<CatalogService>().upsertCustomer(
    session: session,
    id: 'c-a',
    name: 'عميل أ',
  );
  return store;
}

void main() {
  test('cash sale updates customer balance and stock', () async {
    final store = await readyStore();
    final session = admin();
    final before = store.products['p-a']!;
    await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-a',
        paidAmount: Money.parse('30'),
        lines: [
          SaleLineDraft(
            productId: 'p-a',
            quantity: Quantity.parse('2'),
            unit: 'كغ',
            unitPrice: Money.parse('15'),
          ),
        ],
      ),
    );
    expect(
      Quantity.parse(store.products['p-a']!.currentStock),
      Quantity.parse(before.currentStock) - Quantity.parse('2'),
    );
    final account = store.accounts.values.firstWhere((a) => a.customerId == 'c-a');
    expect(Money.parse(account.cachedBalance).isZero, isTrue);
  });

  test('credit sale leaves customer debt', () async {
    final store = await readyStore();
    final session = admin();
    await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-a',
        paidAmount: Money.zero(),
        lines: [
          SaleLineDraft(
            productId: 'p-a',
            quantity: Quantity.parse('2'),
            unit: 'كغ',
            unitPrice: Money.parse('15'),
          ),
        ],
      ),
    );
    final account = store.accounts.values.firstWhere((a) => a.customerId == 'c-a');
    expect(Money.parse(account.cachedBalance), Money.parse('30'));
  });

  test('sale cancel restores stock and reverses debt', () async {
    final store = await readyStore();
    final session = admin();
    final before = store.products['p-a']!.currentStock;
    final result = await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-a',
        paidAmount: Money.zero(),
        lines: [
          SaleLineDraft(
            productId: 'p-a',
            quantity: Quantity.parse('3'),
            unit: 'كغ',
            unitPrice: Money.parse('15'),
          ),
        ],
      ),
    );
    await sl<SaleService>().cancel(session, result.saleId, 'اختبار');
    expect(store.products['p-a']!.currentStock, before);
    final account = store.accounts.values.firstWhere((a) => a.customerId == 'c-a');
    expect(Money.parse(account.cachedBalance).isZero, isTrue);
  });

  test('credit purchase increases supplier payable and stock', () async {
    final store = await readyStore();
    final session = admin();
    final supplierId = await sl<SupplierService>().upsert(
      session: session,
      name: 'مورد مالي',
    );
    final beforeStock = store.products['p-a']!.currentStock;
    await sl<PurchaseService>().create(
      session,
      PurchaseDraft(
        supplierId: supplierId,
        paidAmount: Money.zero(),
        lines: [
          PurchaseLineDraft(
            productId: 'p-a',
            quantity: Quantity.parse('5'),
            unit: 'كغ',
            unitPrice: Money.parse('10'),
          ),
        ],
      ),
    );
    expect(
      Quantity.parse(store.products['p-a']!.currentStock),
      Quantity.parse(beforeStock) + Quantity.parse('5'),
    );
    final account = store.supplierAccounts.values.firstWhere(
      (row) => row.supplierId == supplierId,
    );
    expect(Money.parse(account.cachedBalance), Money.parse('50'));
  });

  test('supplier payment reduces payable balance', () async {
    final store = await readyStore();
    final session = admin();
    final supplierId = await sl<SupplierService>().upsert(
      session: session,
      name: 'مورد دفع',
    );
    await sl<PurchaseService>().create(
      session,
      PurchaseDraft(
        supplierId: supplierId,
        paidAmount: Money.zero(),
        lines: [
          PurchaseLineDraft(
            productId: 'p-a',
            quantity: Quantity.parse('4'),
            unit: 'كغ',
            unitPrice: Money.parse('10'),
          ),
        ],
      ),
    );
    await sl<SupplierService>().recordPayment(
      session: session,
      supplierId: supplierId,
      amount: Money.parse('20'),
    );
    final account = store.supplierAccounts.values.firstWhere(
      (row) => row.supplierId == supplierId,
    );
    expect(Money.parse(account.cachedBalance), Money.parse('20'));
  });

  test('customer collection reduces debt', () async {
    final store = await readyStore();
    final session = admin();
    await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-a',
        paidAmount: Money.zero(),
        lines: [
          SaleLineDraft(
            productId: 'p-a',
            quantity: Quantity.parse('2'),
            unit: 'كغ',
            unitPrice: Money.parse('15'),
          ),
        ],
      ),
    );
    await sl<CollectionService>().record(
      session: session,
      customerId: 'c-a',
      amount: Money.parse('10'),
      paymentMethod: 'cash',
    );
    final account = store.accounts.values.firstWhere((a) => a.customerId == 'c-a');
    expect(Money.parse(account.cachedBalance), Money.parse('20'));
  });

  test('manual inventory adjust updates stock and movement', () async {
    final store = await readyStore();
    final session = admin();
    final before = store.products['p-a']!.currentStock;
    await sl<InventoryService>().adjust(
      session: session,
      productId: 'p-a',
      quantity: Quantity.parse('7'),
      type: 'stock_in',
    );
    expect(
      Quantity.parse(store.products['p-a']!.currentStock),
      Quantity.parse(before) + Quantity.parse('7'),
    );
    expect(store.movements.values.any((m) => m.productId == 'p-a'), isTrue);
  });
}
