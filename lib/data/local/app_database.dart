import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

part 'tables.dart';
part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Roles,
    Permissions,
    RolePermissionLinks,
    Users,
    ProductCategories,
    Products,
    Customers,
    CustomerAccounts,
    Sales,
    SaleItems,
    Collections,
    CustomerAccountTransactions,
    InventoryMovements,
    AuditLogs,
    SyncQueue,
    SyncLogs,
    Conflicts,
    AppMetadata,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => AppVersions.databaseVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sales_sold_at ON sales(sold_at);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status);',
      );
    },
    onUpgrade: (m, from, to) async {
      // Sequential, data-preserving migrations only.
      // Never drop business tables. Never clear sync_queue.
      if (from < 1) {
        await m.createAll();
      }
      if (from < 2) {
        await customStatement(
          "INSERT OR IGNORE INTO permissions (id, code) VALUES ('outstanding.view', 'outstanding.view')",
        );
        await customStatement(
          "INSERT OR IGNORE INTO permissions (id, code) VALUES ('outstanding.create', 'outstanding.create')",
        );
        await customStatement(
          "INSERT OR IGNORE INTO role_permission_links (role_id, permission_id) VALUES ('admin', 'outstanding.view')",
        );
        await customStatement(
          "INSERT OR IGNORE INTO role_permission_links (role_id, permission_id) VALUES ('admin', 'outstanding.create')",
        );
        await customStatement(
          "INSERT OR IGNORE INTO role_permission_links (role_id, permission_id) VALUES ('manager', 'outstanding.view')",
        );
        await customStatement(
          "INSERT OR IGNORE INTO role_permission_links (role_id, permission_id) VALUES ('manager', 'outstanding.create')",
        );
        await customStatement(
          "INSERT OR IGNORE INTO role_permission_links (role_id, permission_id) VALUES ('viewer', 'outstanding.view')",
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

QueryExecutor _open() {
  return driftDatabase(
    name: 'al_nomani_erp',
    web: DriftWebOptions(
      sqlite3Wasm: _webAssetUri('sqlite3.wasm'),
      driftWorker: _webAssetUri('drift_worker.js'),
      onResult: (result) {
        debugPrint(
          'Drift web storage: ${result.chosenImplementation} '
          'missing=${result.missingFeatures}',
        );
        if (result.chosenImplementation == WasmStorageImplementation.inMemory) {
          debugPrint(
            'تحذير: قاعدة البيانات تعمل في الذاكرة فقط ولن تُحفظ بعد إغلاق التطبيق.',
          );
        }
      },
    ),
  );
}

Uri _webAssetUri(String name) {
  final base = Uri.base;
  final path = base.path;
  final directory = path.endsWith('.html') || path.split('/').last.contains('.')
      ? path.substring(0, path.lastIndexOf('/') + 1)
      : path.endsWith('/')
      ? path
      : '$path/';
  return base.replace(path: directory).resolve(name);
}
