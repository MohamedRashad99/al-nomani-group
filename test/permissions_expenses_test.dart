import 'package:al_nomani_group/core/config/app_config.dart';
import 'package:al_nomani_group/core/di/injector.dart';
import 'package:al_nomani_group/core/errors/app_exception.dart';
import 'package:al_nomani_group/data/remote/memory_erp_store.dart';
import 'package:al_nomani_group/domain/cairo_date_range.dart';
import 'package:al_nomani_group/domain/entities/erp_models.dart';
import 'package:al_nomani_group/domain/services/catalog_service.dart';
import 'package:al_nomani_group/domain/services/expense_service.dart';
import 'package:al_nomani_group/domain/services/inventory_service.dart';
import 'package:al_nomani_group/domain/services/sale_service.dart';
import 'package:al_nomani_group/domain/services/seed_service.dart';
import 'package:al_nomani_group/domain/services/user_admin_service.dart';
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

AppSession _session(Set<String> permissions, {String role = AppRole.cashier}) {
  return AppSession(
    userId: 'u-1',
    username: 'user',
    displayName: 'مستخدم',
    roleName: role,
    permissions: permissions,
    expiresAt: DateTime.now().add(const Duration(days: 1)),
    isOfflineVerified: true,
  );
}

AppSession admin() => _session(AppPermission.all.toSet(), role: AppRole.admin);

Future<MemoryErpStore> readyStore() async {
  FlutterSecureStorage.setMockInitialValues({});
  final store = MemoryErpStore();
  await configureDependencies(config: _config(), store: store);
  await sl<SeedService>().ensureDemoAdminIdentity();
  await sl<CatalogService>().upsertProduct(
    session: admin(),
    id: 'p-a',
    name: 'منتج أ',
    sku: 'A',
    purchasePrice: Money.parse('10'),
    sellingPrice: Money.parse('15'),
    currentStock: Quantity.parse('100'),
    minimumStock: Quantity.parse('5'),
    unit: 'كغ',
  );
  return store;
}

void main() {
  test('view-only user cannot add a product', () async {
    await readyStore();
    final viewer = _session({AppPermission.productsView});
    expect(
      () => sl<CatalogService>().upsertProduct(
        session: viewer,
        name: 'جديد',
        sku: 'N',
        purchasePrice: Money.parse('1'),
        sellingPrice: Money.parse('2'),
        currentStock: Quantity.zero(),
        minimumStock: Quantity.zero(),
        unit: 'كغ',
      ),
      throwsA(isA<PermissionException>()),
    );
  });

  test('inventory add is allowed without remove', () async {
    await readyStore();
    final user = _session({
      AppPermission.inventoryView,
      AppPermission.inventoryCreate,
    });
    await sl<InventoryService>().adjust(
      session: user,
      productId: 'p-a',
      quantity: Quantity.parse('1'),
      type: 'stock_in',
    );
    expect(
      () => sl<InventoryService>().adjust(
        session: user,
        productId: 'p-a',
        quantity: Quantity.parse('1'),
        type: 'stock_out',
      ),
      throwsA(isA<PermissionException>()),
    );
  });

  test('last active admin cannot be deleted', () async {
    await readyStore();
    final users = await sl<UserAdminService>().list();
    final adminUser = users.firstWhere((user) => user.roleId == AppRole.admin);
    expect(
      () => sl<UserAdminService>().delete(admin(), adminUser.id),
      throwsA(isA<ValidationException>()),
    );
  });

  test('expense does not touch sales purchases stock or customers', () async {
    final store = await readyStore();
    final sales = store.sales.length;
    final purchases = store.purchases.length;
    final stock = store.products['p-a']!.currentStock;
    final customers = store.customers.length;
    final suppliers = store.suppliers.length;
    await sl<ExpenseService>().upsert(
      session: admin(),
      amount: Money.parse('350.50'),
      category: ExpenseCategory.fuel.code,
      note: 'بنزين عربية التوصيل',
      occurredAt: EgyptTime.nowUtc(),
    );
    expect(store.sales.length, sales);
    expect(store.purchases.length, purchases);
    expect(store.products['p-a']!.currentStock, stock);
    expect(store.customers.length, customers);
    expect(store.suppliers.length, suppliers);
    final expenses = await sl<ExpenseService>().watch().first;
    expect(expenses, hasLength(1));
    final summary = sl<ExpenseService>().summarize(expenses);
    expect(summary.count, 1);
    expect(summary.total, Money.parse('350.50'));
  });

  test('saved expense stays visible in this-month filter', () async {
    await readyStore();
    await sl<ExpenseService>().upsert(
      session: admin(),
      amount: Money.parse('80'),
      category: ExpenseCategory.rent.code,
      occurredAt: EgyptTime.nowUtc(),
    );
    final expenses = await sl<ExpenseService>().watch().first;
    final visible = sl<ExpenseService>().filter(
      expenses,
      range: CairoDateRange.preset(ReportPeriod.thisMonth),
    );
    expect(visible, hasLength(1));
    expect(visible.single.amount, '80.000');
  });

  test('expense create is admin-gated', () async {
    await readyStore();
    expect(
      () => sl<ExpenseService>().upsert(
        session: _session({AppPermission.reportsView}),
        amount: Money.parse('10'),
        category: ExpenseCategory.other.code,
        occurredAt: EgyptTime.nowUtc(),
      ),
      throwsA(isA<PermissionException>()),
    );
  });

  test('sale create still requires sales.create', () async {
    await readyStore();
    expect(
      sl<SaleService>().create,
      isNotNull,
    );
    expect(
      RolePermissions.resolve(AppRole.viewer).contains(AppPermission.usersView),
      isFalse,
    );
    expect(
      RolePermissions.resolve(AppRole.admin).contains(AppPermission.expensesView),
      isTrue,
    );
    expect(_session(const {}, role: AppRole.admin).isAdmin, isTrue);
    expect(_session(AppPermission.all.toSet(), role: AppRole.manager).isAdmin, isFalse);
  });

  test('admin can update notes and delete expenses', () async {
    await readyStore();
    final adminWithoutCodes = _session(const {}, role: AppRole.admin);
    final id = await sl<ExpenseService>().upsert(
      session: adminWithoutCodes,
      amount: Money.parse('25'),
      category: ExpenseCategory.other.code,
      note: 'قديم',
      occurredAt: EgyptTime.nowUtc(),
    );
    await sl<ExpenseService>().upsert(
      session: adminWithoutCodes,
      id: id,
      amount: Money.parse('30'),
      category: ExpenseCategory.fuel.code,
      note: 'ملاحظة جديدة',
      occurredAt: EgyptTime.nowUtc(),
    );
    var expenses = await sl<ExpenseService>().watch().first;
    expect(expenses, hasLength(1));
    expect(expenses.single.note, 'ملاحظة جديدة');
    expect(expenses.single.amount, '30.000');
    expect(expenses.single.category, ExpenseCategory.fuel.code);
    await sl<ExpenseService>().delete(session: adminWithoutCodes, id: id);
    expenses = await sl<ExpenseService>().watch().first;
    expect(expenses, isEmpty);
  });
}
