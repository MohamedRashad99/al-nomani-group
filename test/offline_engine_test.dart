import 'dart:convert';

import 'package:al_nomani_group/app.dart';
import 'package:al_nomani_group/core/config/app_config.dart';
import 'package:al_nomani_group/core/di/injector.dart';
import 'package:al_nomani_group/core/utils/arabic_format.dart';
import 'package:al_nomani_group/data/remote/erp_store.dart';
import 'package:al_nomani_group/data/remote/memory_erp_store.dart';
import 'package:al_nomani_group/domain/models/purchase_draft.dart';
import 'package:al_nomani_group/domain/models/sale_draft.dart';
import 'package:al_nomani_group/domain/services/catalog_service.dart';
import 'package:al_nomani_group/domain/services/collection_service.dart';
import 'package:al_nomani_group/domain/services/dashboard_service.dart';
import 'package:al_nomani_group/domain/services/outstanding_service.dart';
import 'package:al_nomani_group/domain/services/purchase_service.dart';
import 'package:al_nomani_group/domain/services/sale_service.dart';
import 'package:al_nomani_group/domain/services/seed_service.dart';
import 'package:al_nomani_group/domain/services/supplier_service.dart';
import 'package:al_nomani_group/domain/session.dart';
import 'package:al_nomani_group/features/auth/auth_cubit.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/material.dart';
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
  final catalog = sl<CatalogService>();
  Future<void> product({
    required String id,
    required String name,
    required String sku,
    required String stock,
    required String unit,
    required String price,
  }) {
    return catalog.upsertProduct(
      session: session,
      id: id,
      name: name,
      sku: sku,
      purchasePrice: Money.parse(price),
      sellingPrice: Money.parse(price),
      currentStock: Quantity.parse(stock),
      minimumStock: Quantity.parse('1'),
      unit: unit,
      packSize: '1 Liter',
    );
  }

  await product(
    id: 'p-imidacloprid',
    name: 'إيميداكلوبريد',
    sku: 'IMI',
    stock: '20',
    unit: 'لتر',
    price: '5.500',
  );
  await product(
    id: 'p-npk',
    name: 'سماد NPK',
    sku: 'NPK',
    stock: '50',
    unit: 'كغ',
    price: '10.500',
  );
  await product(
    id: 'p-urea',
    name: 'يوريا',
    sku: 'UREA',
    stock: '10',
    unit: 'كغ',
    price: '1000',
  );
  await product(
    id: 'p-drip',
    name: 'نقاط',
    sku: 'DRIP',
    stock: '1',
    unit: 'قطعة',
    price: '0.180',
  );
  await product(
    id: 'p-humic',
    name: 'هيوميك',
    sku: 'HUM',
    stock: '10',
    unit: 'لتر',
    price: '1000',
  );
  await product(
    id: 'p-glyphosate',
    name: 'جليفوسات',
    sku: 'GLY',
    stock: '10',
    unit: 'لتر',
    price: '4.000',
  );
  await catalog.upsertCustomer(
    session: session,
    id: 'c-ahmed',
    name: 'أحمد',
  );
  await catalog.upsertCustomer(
    session: session,
    id: 'c-salem',
    name: 'سالم',
  );
  await catalog.upsertCustomer(
    session: session,
    id: 'c-fatima',
    name: 'فاطمة',
  );
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await sl.reset();
  });

  test('cash, credit and partial sales persist without a local database', () async {
    await readyStore();
    final session = admin();
    final sales = sl<SaleService>();

    final cash = await sales.create(
      session,
      SaleDraft(
        customerId: 'c-ahmed',
        paidAmount: Money.parse('5.500'),
        lines: [
          SaleLineDraft(
            productId: 'p-imidacloprid',
            quantity: Quantity.parse('1'),
            unit: 'لتر',
            unitPrice: Money.parse('5.500'),
          ),
        ],
      ),
    );
    expect(cash.remaining.isZero, isTrue);

    final credit = await sales.create(
      session,
      SaleDraft(
        customerId: 'c-salem',
        paidAmount: Money.zero(),
        lines: [
          SaleLineDraft(
            productId: 'p-npk',
            quantity: Quantity.parse('2'),
            unit: 'كغ',
            unitPrice: Money.parse('10.500'),
          ),
        ],
      ),
    );
    expect(credit.subtotal.toStorage(), '21.000');
    expect(credit.remaining.toStorage(), '21.000');

    final partial = await sales.create(
      session,
      SaleDraft(
        customerId: 'c-ahmed',
        paidAmount: Money.parse('400'),
        lines: [
          SaleLineDraft(
            productId: 'p-urea',
            quantity: Quantity.parse('1'),
            unit: 'كغ',
            unitPrice: Money.parse('1000'),
          ),
        ],
      ),
    );
    expect(partial.remaining.toStorage(), '600.000');
  });

  test('dashboard aggregates completed sales only', () async {
    await readyStore();
    final session = admin();
    await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-ahmed',
        paidAmount: Money.parse('5.500'),
        lines: [
          SaleLineDraft(
            productId: 'p-imidacloprid',
            quantity: Quantity.parse('1'),
            unit: 'لتر',
            unitPrice: Money.parse('5.500'),
          ),
        ],
      ),
    );

    final dashboard = await sl<DashboardService>().load();
    expect(dashboard.todaySales.toStorage(), '5.500');
    expect(dashboard.salesTrend, hasLength(7));
    expect(dashboard.topProducts.first.name, isNotEmpty);
    expect(dashboard.topCustomers.first.name, isNotEmpty);
  });

  test('sale cancellation restores stock and customer debt', () async {
    final store = await readyStore();
    final session = admin();
    final before = store.products['p-npk']!;
    final result = await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-salem',
        paidAmount: Money.zero(),
        lines: [
          SaleLineDraft(
            productId: 'p-npk',
            quantity: Quantity.parse('2'),
            unit: 'كغ',
            unitPrice: Money.parse('10.500'),
          ),
        ],
      ),
    );
    await sl<SaleService>().cancel(session, result.saleId, 'اختبار العكس');

    final sale = store.sales[result.saleId]!;
    final after = store.products['p-npk']!;
    final account = store.accounts.values.firstWhere(
      (row) => row.customerId == 'c-salem',
    );
    expect(sale.status, 'cancelled');
    expect(sale.cancelReason, 'اختبار العكس');
    expect(sale.isDeleted, isFalse);
    expect(after.currentStock, before.currentStock);
    expect(account.cachedBalance, '0.000');
  });

  test('cancel after collection reverses unpaid remainder only', () async {
    final store = await readyStore();
    final session = admin();
    final before = store.products['p-npk']!;
    final result = await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-salem',
        paidAmount: Money.zero(),
        lines: [
          SaleLineDraft(
            productId: 'p-npk',
            quantity: Quantity.parse('2'),
            unit: 'كغ',
            unitPrice: Money.parse('10.500'),
          ),
        ],
      ),
    );
    await sl<CollectionService>().record(
      session: session,
      customerId: 'c-salem',
      amount: Money.parse('21.000'),
      paymentMethod: 'cash',
    );
    await sl<SaleService>().cancel(session, result.saleId, 'بعد التحصيل');
    final account = store.accounts.values.firstWhere(
      (row) => row.customerId == 'c-salem',
    );
    expect(store.products['p-npk']!.currentStock, before.currentStock);
    expect(account.cachedBalance, '0.000');
    expect(store.sales[result.saleId]!.status, 'cancelled');
  });

  test('business codes are presented with Arabic labels', () {
    expect(ArabicFormat.paymentMethod('cash'), 'نقداً');
    expect(ArabicFormat.status('cancelled'), 'ملغاة');
    expect(ArabicFormat.movementType('stock_in'), 'إدخال مخزون');
  });

  testWidgets('dashboard has no overflow at iPhone 13 dimensions', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await readyStore();
    final user = (await sl<ErpStore>().listUsers()).first;
    await const FlutterSecureStorage().write(
      key: 'offline_session_v1',
      value: jsonEncode({
        'user_id': user.id,
        'username': user.username,
        'display_name': user.displayName,
        'role_name': user.roleId,
        'permissions': AppPermission.all,
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
      }),
    );
    await sl<AuthCubit>().restore();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const AlNomaniApp());
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('لوحة التحكم'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  test('sale fails when stock is insufficient', () async {
    await readyStore();
    expect(
      () => sl<SaleService>().create(
        admin(),
        SaleDraft(
          customerId: 'c-ahmed',
          paidAmount: Money.zero(),
          lines: [
            SaleLineDraft(
              productId: 'p-drip',
              quantity: Quantity.parse('9999'),
              unit: 'قطعة',
              unitPrice: Money.parse('0.180'),
            ),
          ],
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('customer balance is derived from account transactions', () async {
    final store = await readyStore();
    await sl<SaleService>().create(
      admin(),
      SaleDraft(
        customerId: 'c-fatima',
        paidAmount: Money.parse('250'),
        lines: [
          SaleLineDraft(
            productId: 'p-humic',
            quantity: Quantity.parse('1'),
            unit: 'لتر',
            unitPrice: Money.parse('1000'),
          ),
        ],
      ),
    );
    final account = store.accounts.values.firstWhere(
      (row) => row.customerId == 'c-fatima',
    );
    expect(Money.parse(account.cachedBalance).toStorage(), '750.000');
    final txs = store.accountTx.values.where(
      (tx) => tx.customerId == 'c-fatima',
    );
    expect(txs.length, 2);
  });

  test('permissions deny unauthorized sale', () async {
    await readyStore();
    final viewer = AppSession(
      userId: 'v',
      username: 'v',
      displayName: 'v',
      roleName: AppRole.viewer,
      permissions: RolePermissions.matrix[AppRole.viewer]!.toSet(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      isOfflineVerified: true,
    );
    expect(
      () => sl<SaleService>().create(
        viewer,
        SaleDraft(
          customerId: 'c-ahmed',
          paidAmount: Money.zero(),
          lines: const [],
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('sales survive without sqlite restart', () async {
    final store = await readyStore();
    await sl<SaleService>().create(
      admin(),
      SaleDraft(
        customerId: 'c-ahmed',
        paidAmount: Money.parse('4.000'),
        lines: [
          SaleLineDraft(
            productId: 'p-glyphosate',
            quantity: Quantity.parse('1'),
            unit: 'لتر',
            unitPrice: Money.parse('4.000'),
          ),
        ],
      ),
    );
    expect(store.sales.values, isNotEmpty);
    expect(store.sales.values.first.isDeleted, isFalse);
  });

  test('product watch emits the saved product immediately', () async {
    await readyStore();
    final catalog = sl<CatalogService>();
    await catalog.upsertProduct(
      session: admin(),
      name: 'سماد اختباري',
      sku: 'TEST-FERT',
      purchasePrice: Money.parse('1.000'),
      sellingPrice: Money.parse('1.500'),
      currentStock: Quantity.parse('10'),
      minimumStock: Quantity.parse('1'),
      unit: 'كغ',
    );
    final items = await catalog
        .watchProducts('سماد اختباري')
        .first
        .timeout(const Duration(seconds: 3));
    expect(items.any((item) => item.sku == 'TEST-FERT'), isTrue);
  });

  test('unused product can be deleted', () async {
    final store = await readyStore();
    await sl<CatalogService>().deleteProduct(
      session: admin(),
      id: 'p-drip',
    );
    expect(store.products.containsKey('p-drip'), isFalse);
  });

  test('used product cannot be deleted', () async {
    await readyStore();
    await sl<SaleService>().create(
      admin(),
      SaleDraft(
        customerId: 'c-ahmed',
        paidAmount: Money.parse('5.500'),
        lines: [
          SaleLineDraft(
            productId: 'p-imidacloprid',
            quantity: Quantity.parse('1'),
            unit: 'لتر',
            unitPrice: Money.parse('5.500'),
          ),
        ],
      ),
    );
    expect(
      () => sl<CatalogService>().deleteProduct(
        session: admin(),
        id: 'p-imidacloprid',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('outstanding add, set, and reduce keep a full ledger', () async {
    final store = await readyStore();
    final outstanding = sl<OutstandingService>();
    await outstanding.add(
      session: admin(),
      customerId: 'c-ahmed',
      amount: Money.parse('40.000'),
      notes: 'رصيد سابق قبل النظام',
    );
    var account = store.accounts.values.firstWhere(
      (row) => row.customerId == 'c-ahmed',
    );
    expect(Money.parse(account.cachedBalance).toStorage(), '40.000');

    await outstanding.setTarget(
      session: admin(),
      customerId: 'c-ahmed',
      target: Money.parse('25.000'),
      notes: 'تصحيح بعد مراجعة كشف قديم',
    );
    account = store.accounts.values.firstWhere(
      (row) => row.customerId == 'c-ahmed',
    );
    expect(Money.parse(account.cachedBalance).toStorage(), '25.000');

    await outstanding.reduce(
      session: admin(),
      customerId: 'c-ahmed',
      amount: Money.parse('5.000'),
      notes: 'خصم تسوية',
    );
    account = store.accounts.values.firstWhere(
      (row) => row.customerId == 'c-ahmed',
    );
    expect(Money.parse(account.cachedBalance).toStorage(), '20.000');

    await outstanding.collectCash(
      session: admin(),
      customerId: 'c-ahmed',
      amount: Money.parse('8.000'),
      notes: 'سداد نقدي',
    );
    account = store.accounts.values.firstWhere(
      (row) => row.customerId == 'c-ahmed',
    );
    expect(Money.parse(account.cachedBalance).toStorage(), '12.000');
    final due = await outstanding.listDue();
    expect(due.any((row) => row.customer.id == 'c-ahmed'), isTrue);
  });

  test('cashier cannot post outstanding amounts', () async {
    await readyStore();
    final cashier = AppSession(
      userId: 'cashier',
      username: 'cashier',
      displayName: 'أمين صندوق',
      roleName: AppRole.cashier,
      permissions: RolePermissions.matrix[AppRole.cashier]!.toSet(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      isOfflineVerified: true,
    );
    expect(
      () => sl<OutstandingService>().add(
        session: cashier,
        customerId: 'c-ahmed',
        amount: Money.parse('10.000'),
        notes: 'غير مسموح',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('purchase increases stock and supplier payable, cancel reverses both', () async {
    final store = await readyStore();
    final session = admin();
    final supplierId = await sl<SupplierService>().upsert(
      session: session,
      name: 'شركة الأسمدة',
    );
    final before = store.products['p-npk']!;
    final result = await sl<PurchaseService>().create(
      session,
      PurchaseDraft(
        supplierId: supplierId,
        paidAmount: Money.zero(),
        lines: [
          PurchaseLineDraft(
            productId: 'p-npk',
            quantity: Quantity.parse('3'),
            unit: 'كغ',
            unitPrice: Money.parse('8.000'),
          ),
        ],
      ),
    );
    expect(
      Quantity.parse(store.products['p-npk']!.currentStock),
      Quantity.parse(before.currentStock) + Quantity.parse('3'),
    );
    final account = store.supplierAccounts.values.firstWhere(
      (row) => row.supplierId == supplierId,
    );
    expect(account.cachedBalance, '24.000');
    await sl<PurchaseService>().cancel(session, result.purchaseId, 'عكس شراء');
    expect(store.products['p-npk']!.currentStock, before.currentStock);
    expect(
      store.supplierAccounts.values
          .firstWhere((row) => row.supplierId == supplierId)
          .cachedBalance,
      '0.000',
    );
  });
}
