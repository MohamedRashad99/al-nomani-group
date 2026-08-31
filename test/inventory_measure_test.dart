import 'package:al_nomani_group/domain/entities/erp_models.dart';
import 'package:al_nomani_group/domain/services/inventory_measure.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  required String stock,
  String? packageSize,
  String? unitOfMeasure,
  String? packageType,
  String? packSize,
  String unit = 'عبوة',
  String minimum = '0',
  String? reorderPoint,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Product(
    id: 'p1',
    name: 'منتج',
    sku: 'SKU',
    packSize: packSize,
    packageSize: packageSize,
    unitOfMeasure: unitOfMeasure,
    packageType: packageType,
    reorderPoint: reorderPoint,
    purchasePrice: '0',
    sellingPrice: '0',
    currentStock: stock,
    minimumStock: minimum,
    unit: unit,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('100 bottles of 250 ml equal 25 liters', () {
    final measure = InventoryMeasure.fromProduct(
      _product(
        stock: '100',
        packageSize: '250',
        unitOfMeasure: 'ml',
        packageType: 'عبوة',
      ),
    );
    expect(measure.actual.toDisplay(), '25000');
    expect(measure.actualLabel, '25 لتر');
    expect(measure.packagesLabel, '100 عبوة');
  });

  test('20 sacks of 50 kg equal 1000 kg', () {
    final measure = InventoryMeasure.fromProduct(
      _product(
        stock: '20',
        packageSize: '50',
        unitOfMeasure: 'kg',
        packageType: 'شكارة',
      ),
    );
    expect(measure.actual.toDisplay(), '1000');
    expect(measure.actualLabel, '1000 كجم');
    expect(measure.formatActual(Quantity.parse('2')), '100 كجم');
  });

  test('does not use display text when structured fields exist', () {
    final measure = InventoryMeasure.fromProduct(
      _product(
        stock: '2',
        packageSize: '250',
        unitOfMeasure: 'ml',
        packageType: 'عبوة',
        packSize: 'ignore this 1 Liter text',
      ),
    );
    expect(measure.actualLabel, '500 مل');
  });

  test('parses legacy pack size text only as a fallback', () {
    final measure = InventoryMeasure.fromProduct(
      _product(stock: '20', packSize: '1 Liter', unit: 'لتر'),
    );
    expect(measure.actualLabel, '20 لتر');
  });

  test('reorder when remaining actual is at or below the reorder point', () {
    final measure = InventoryMeasure.fromProduct(
      _product(
        stock: '12',
        packageSize: '250',
        unitOfMeasure: 'ml',
        packageType: 'عبوة',
        minimum: '5',
        reorderPoint: '10',
      ),
    );
    expect(measure.actualLabel, '3 لتر');
    expect(measure.needsReorder, isTrue);
  });
}
