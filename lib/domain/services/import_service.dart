import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:csv/csv.dart';

import '../../core/errors/app_exception.dart';
import '../session.dart';
import 'catalog_service.dart';
import 'inventory_service.dart';

class ImportPreviewRow {
  final int line;
  final Map<String, String> values;
  final String? error;

  const ImportPreviewRow({
    required this.line,
    required this.values,
    this.error,
  });
}

class ImportService {
  ImportService(this._catalog, this._inventory);
  final CatalogService _catalog;
  final InventoryService _inventory;

  List<ImportPreviewRow> previewProducts(String csv) {
    final rows = const CsvToListConverter(eol: '\n').convert(csv);
    if (rows.isEmpty) return const [];
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final out = <ImportPreviewRow>[];
    for (var i = 1; i < rows.length; i++) {
      final map = <String, String>{};
      for (var c = 0; c < header.length && c < rows[i].length; c++) {
        map[header[c]] = rows[i][c].toString();
      }
      String? error;
      try {
        if ((map['name'] ?? '').trim().isEmpty) error = 'اسم المنتج مطلوب';
        if ((map['sku'] ?? '').trim().isEmpty) error = 'رمز المنتج مطلوب';
        Money.parse(map['selling_price'] ?? '0');
        Quantity.parse(map['stock'] ?? '0');
      } catch (e) {
        error = e.toString();
      }
      out.add(ImportPreviewRow(line: i + 1, values: map, error: error));
    }
    return out;
  }

  Future<int> confirmProducts(
    AppSession session,
    List<ImportPreviewRow> rows,
  ) async {
    final valid = rows.where((r) => r.error == null).toList();
    if (valid.isEmpty) {
      throw const ValidationException('لا توجد صفوف صالحة للاستيراد.');
    }
    var count = 0;
    for (final row in valid) {
      final id = await _catalog.upsertProduct(
        session: session,
        name: row.values['name'] ?? '',
        sku: row.values['sku'] ?? '',
        brand: row.values['brand'],
        purchasePrice: Money.parse(row.values['purchase_price'] ?? '0'),
        sellingPrice: Money.parse(row.values['selling_price'] ?? '0'),
        currentStock: Quantity.zero(),
        minimumStock: Quantity.parse(row.values['minimum_stock'] ?? '0'),
        unit: row.values['unit'] ?? 'kg',
      );
      final stock = Quantity.parse(row.values['stock'] ?? '0');
      if (stock.isPositive) {
        await _inventory.adjust(
          session: session,
          productId: id,
          quantity: stock,
          type: 'stock_in',
          notes: 'استيراد مخزون افتتاحي',
        );
      }
      count++;
    }
    return count;
  }
}
