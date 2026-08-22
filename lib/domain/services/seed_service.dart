import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../../core/config/app_config.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';

/// Inserts Arabic agricultural demo data only when the database is empty
/// and [AppConfig.allowSeed] is true. Never overwrites production rows.
class SeedService {
  SeedService(this._db, this._metadata, this._config);
  final AppDatabase _db;
  final MetadataStore _metadata;
  final AppConfig _config;

  static const demoAdminUsername = 'admin';
  static const demoAdminPassword = 'ChangeMe!Admin1';

  Future<void> seedIfEmpty() async {
    if (!_config.allowSeed) return;
    final existingUsers = await _db.select(_db.users).get();
    if (existingUsers.isNotEmpty) return;
    await _seed();
    await _metadata.set('seed_applied', 'demo');
    await _metadata.set('seed_warning', 'بيانات تجريبية للتطوير فقط');
  }

  Future<void> _seed() async {
    final now = DateTime.now().toUtc();
    final deviceId = await _metadata.deviceId();

    for (final code in AppPermission.all) {
      await _db
          .into(_db.permissions)
          .insert(PermissionsCompanion.insert(id: code, code: code));
    }

    const roles = {
      AppRole.admin: 'مدير النظام',
      AppRole.manager: 'مدير',
      AppRole.cashier: 'أمين صندوق',
      AppRole.viewer: 'عرض فقط',
    };
    for (final entry in roles.entries) {
      await _db
          .into(_db.roles)
          .insert(
            RolesCompanion.insert(
              id: entry.key,
              name: entry.key,
              displayNameAr: entry.value,
              createdAt: now,
              updatedAt: now,
              deviceId: Value(deviceId),
            ),
          );
      for (final perm
          in RolePermissions.matrix[entry.key] ?? const <String>[]) {
        await _db
            .into(_db.rolePermissionLinks)
            .insert(
              RolePermissionLinksCompanion.insert(
                roleId: entry.key,
                permissionId: perm,
              ),
            );
      }
    }

    final adminId = newId();
    await _db
        .into(_db.users)
        .insert(
          UsersCompanion.insert(
            id: adminId,
            username: demoAdminUsername,
            displayName: 'أحمد نعمان الجابري',
            passwordHash: BCrypt.hashpw(demoAdminPassword, BCrypt.gensalt()),
            roleId: AppRole.admin,
            createdAt: now,
            updatedAt: now,
            deviceId: Value(deviceId),
          ),
        );

    final categories = {
      'cat-pest': 'مبيدات زراعية',
      'cat-fert': 'أسمدة',
      'cat-nutri': 'مغذيات نباتية',
      'cat-supply': 'مستلزمات زراعية',
    };
    for (final e in categories.entries) {
      await _db
          .into(_db.productCategories)
          .insert(
            ProductCategoriesCompanion.insert(
              id: e.key,
              name: e.value,
              createdAt: now,
              updatedAt: now,
              deviceId: Value(deviceId),
            ),
          );
    }

    Future<void> product({
      required String id,
      required String name,
      required String sku,
      required String categoryId,
      required String brand,
      required String purchase,
      required String sell,
      required String stock,
      required String min,
      required String unit,
    }) {
      return _db
          .into(_db.products)
          .insert(
            ProductsCompanion.insert(
              id: id,
              name: name,
              sku: sku,
              categoryId: Value(categoryId),
              brand: Value(brand),
              purchasePrice: purchase,
              sellingPrice: sell,
              currentStock: stock,
              minimumStock: min,
              unit: unit,
              createdAt: now,
              updatedAt: now,
              deviceId: Value(deviceId),
            ),
          );
    }

    await product(
      id: 'p-imidacloprid',
      name: 'إيميداكلوبريد 35% مركز معلق',
      sku: 'PEST-IMI-35',
      categoryId: 'cat-pest',
      brand: 'الواحة الزراعية',
      purchase: '4.200',
      sell: '5.500',
      stock: '80.000',
      min: '10.000',
      unit: 'l',
    );
    await product(
      id: 'p-glyphosate',
      name: 'غليفوسات 48% مبيد أعشاب',
      sku: 'PEST-GLY-48',
      categoryId: 'cat-pest',
      brand: 'الواحة الزراعية',
      purchase: '3.100',
      sell: '4.000',
      stock: '120.000',
      min: '15.000',
      unit: 'l',
    );
    await product(
      id: 'p-npk',
      name: 'سماد مركب NPK 20-20-20',
      sku: 'FERT-NPK-2020',
      categoryId: 'cat-fert',
      brand: 'خصوبة',
      purchase: '8.000',
      sell: '10.500',
      stock: '200.000',
      min: '25.000',
      unit: 'kg',
    );
    await product(
      id: 'p-urea',
      name: 'يوريا 46%',
      sku: 'FERT-UREA-46',
      categoryId: 'cat-fert',
      brand: 'خصوبة',
      purchase: '0.280',
      sell: '0.380',
      stock: '1500.000',
      min: '200.000',
      unit: 'kg',
    );
    await product(
      id: 'p-humic',
      name: 'حامض الهيوميك سائل',
      sku: 'NUT-HUM-01',
      categoryId: 'cat-nutri',
      brand: 'نماء',
      purchase: '2.400',
      sell: '3.250',
      stock: '60.000',
      min: '8.000',
      unit: 'l',
    );
    await product(
      id: 'p-drip',
      name: 'خرطوم ري بالتنقيط 16 مم',
      sku: 'SUP-DRIP-16',
      categoryId: 'cat-supply',
      brand: 'ريّان',
      purchase: '0.120',
      sell: '0.180',
      stock: '5.000',
      min: '20.000',
      unit: 'pcs',
    );

    Future<void> customer(
      String id,
      String name,
      String phone,
      String area,
    ) async {
      await _db
          .into(_db.customers)
          .insert(
            CustomersCompanion.insert(
              id: id,
              name: name,
              phone: Value(phone),
              area: Value(area),
              createdAt: now,
              updatedAt: now,
              deviceId: Value(deviceId),
            ),
          );
      await _db
          .into(_db.customerAccounts)
          .insert(
            CustomerAccountsCompanion.insert(
              id: 'acc-$id',
              customerId: id,
              cachedBalance: '0.000',
              createdAt: now,
              updatedAt: now,
              deviceId: Value(deviceId),
            ),
          );
    }

    await customer('c-walkin', 'عميل نقدي عام', '', 'المحل');
    await customer('c-ahmed', 'أحمد سعيد المزروعي', '91234567', 'بركاء');
    await customer('c-salem', 'سالم بن علي الحارثي', '99881234', 'السيب');
    await customer('c-fatima', 'فاطمة راشد الهنائي', '92110044', 'نزوى');

    await _db
        .into(_db.settings)
        .insert(
          SettingsCompanion.insert(
            key: SyncConfigKeys.syncIntervalDays,
            value: '${_config.syncIntervalDays}',
            updatedAt: now,
          ),
        );
    await _db
        .into(_db.settings)
        .insert(
          SettingsCompanion.insert(
            key: SyncConfigKeys.syncMode,
            value: _config.syncMode.name,
            updatedAt: now,
          ),
        );
  }
}
