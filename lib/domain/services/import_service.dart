import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:csv/csv.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
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
  ImportService(this._catalog, this._inventory, this._db);
  final CatalogService _catalog;
  final InventoryService _inventory;
  final AppDatabase _db;

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

  List<ImportPreviewRow> previewCustomers(String csv) {
    return _preview(csv, (map) {
      if ((map['name'] ?? '').trim().isEmpty) return 'اسم العميل مطلوب';
      return null;
    });
  }

  List<ImportPreviewRow> previewOpeningInventory(String csv) {
    return _preview(csv, (map) {
      if ((map['sku'] ?? '').trim().isEmpty) return 'رمز المنتج مطلوب';
      try {
        final quantity = Quantity.parse(map['quantity'] ?? '0');
        if (!quantity.isPositive) return 'الكمية يجب أن تكون أكبر من صفر';
      } catch (error) {
        return error.toString();
      }
      return null;
    });
  }

  List<ImportPreviewRow> _preview(
    String csv,
    String? Function(Map<String, String> values) validate,
  ) {
    final rows = const CsvToListConverter(eol: '\n').convert(csv);
    if (rows.isEmpty) return const [];
    final header = rows.first.map((value) => value.toString().trim()).toList();
    return [
      for (var index = 1; index < rows.length; index++)
        ImportPreviewRow(
          line: index + 1,
          values: {
            for (
              var column = 0;
              column < header.length && column < rows[index].length;
              column++
            )
              header[column]: rows[index][column].toString().trim(),
          },
          error: validate({
            for (
              var column = 0;
              column < header.length && column < rows[index].length;
              column++
            )
              header[column]: rows[index][column].toString().trim(),
          }),
        ),
    ];
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

  Future<int> confirmCustomers(
    AppSession session,
    List<ImportPreviewRow> rows,
  ) async {
    final valid = rows.where((row) => row.error == null).toList();
    if (valid.isEmpty) {
      throw const ValidationException('لا توجد صفوف صالحة للاستيراد.');
    }
    for (final row in valid) {
      await _catalog.upsertCustomer(
        session: session,
        name: row.values['name'] ?? '',
        phone: row.values['phone'],
        address: row.values['address'],
        area: row.values['area'],
        notes: row.values['notes'],
      );
    }
    return valid.length;
  }

  Future<int> confirmOpeningInventory(
    AppSession session,
    List<ImportPreviewRow> rows,
  ) async {
    final valid = rows.where((row) => row.error == null).toList();
    var count = 0;
    for (final row in valid) {
      final sku = row.values['sku'] ?? '';
      final product =
          await (_db.select(
            _db.products,
          )..where((product) => product.sku.equals(sku))).getSingleOrNull();
      if (product == null) continue;
      await _inventory.adjust(
        session: session,
        productId: product.id,
        quantity: Quantity.parse(row.values['quantity'] ?? '0'),
        type: 'stock_in',
        notes: 'استيراد مخزون افتتاحي',
      );
      count++;
    }
    if (count == 0) {
      throw const ValidationException(
        'لم يتم العثور على رموز منتجات مطابقة.',
      );
    }
    return count;
  }
}
