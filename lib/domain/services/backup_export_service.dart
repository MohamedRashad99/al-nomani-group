import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../data/local/app_database.dart';

/// Complete local backup of business-critical tables. Never deletes data.
class BackupExportService {
  BackupExportService(this._db);
  final AppDatabase _db;

  Future<String> exportJson() async {
    final map = {
      'app_version': AppVersions.appVersion,
      'database_version': AppVersions.databaseVersion,
      'sync_protocol_version': AppVersions.syncProtocolVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'products': (await _db.select(_db.products).get())
          .map((e) => e.toJson())
          .toList(),
      'product_categories': (await _db.select(_db.productCategories).get())
          .map((e) => e.toJson())
          .toList(),
      'customers': (await _db.select(_db.customers).get())
          .map((e) => e.toJson())
          .toList(),
      'customer_accounts': (await _db.select(_db.customerAccounts).get())
          .map((e) => e.toJson())
          .toList(),
      'customer_account_transactions':
          (await _db.select(_db.customerAccountTransactions).get())
              .map((e) => e.toJson())
              .toList(),
      'sales': (await _db.select(_db.sales).get())
          .map((e) => e.toJson())
          .toList(),
      'sale_items': (await _db.select(_db.saleItems).get())
          .map((e) => e.toJson())
          .toList(),
      'collections': (await _db.select(_db.collections).get())
          .map((e) => e.toJson())
          .toList(),
      'inventory_movements': (await _db.select(_db.inventoryMovements).get())
          .map((e) => e.toJson())
          .toList(),
      'users': (await _db.select(_db.users).get())
          .map((e) => e.toJson()..['passwordHash'] = '***')
          .toList(),
      'audit_logs': (await _db.select(_db.auditLogs).get())
          .map((e) => e.toJson())
          .toList(),
      'sync_queue': (await _db.select(_db.syncQueue).get())
          .map((e) => e.toJson())
          .toList(),
      'sync_logs': (await _db.select(_db.syncLogs).get())
          .map((e) => e.toJson())
          .toList(),
      'conflicts': (await _db.select(_db.conflicts).get())
          .map((e) => e.toJson())
          .toList(),
      'settings': (await _db.select(_db.settings).get())
          .map((e) => e.toJson())
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
