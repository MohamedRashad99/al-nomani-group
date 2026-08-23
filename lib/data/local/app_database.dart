import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
