import 'dart:convert';

import '../../data/remote/erp_store.dart';

class BackupExportService {
  BackupExportService(this._store);
  final ErpStore _store;

  Future<String> exportJson() async {
    final products = await _store.listProducts();
    final customers = await _store.listCustomers();
    final sales = await _store.listSales();
    final items = await _store.listSaleItems();
    final collections = await _store.listCollections();
    final suppliers = await _store.listSuppliers();
    final purchases = await _store.listPurchases();
    return jsonEncode({
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'products': [for (final row in products) row.toMap()],
      'customers': [for (final row in customers) row.toMap()],
      'sales': [for (final row in sales) row.toMap()],
      'sale_items': [for (final row in items) row.toMap()],
      'collections': [for (final row in collections) row.toMap()],
      'suppliers': [for (final row in suppliers) row.toMap()],
      'purchases': [for (final row in purchases) row.toMap()],
    });
  }
}
