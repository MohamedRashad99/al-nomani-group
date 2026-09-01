import 'package:al_nomani_group/domain/entities/erp_models.dart';
import 'package:al_nomani_group/domain/models/sale_unit.dart';
import 'package:al_nomani_group/domain/services/sale_unit_conversion.dart';
import 'package:al_nomani_group/data/remote/erp_map.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  String stock = '18',
  String packageSize = '500',
  String unitOfMeasure = 'g',
  String packageType = 'عبوة',
  String sellingPrice = '250',
  String unit = 'عبوة',
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Product(
    id: 'p1',
    name: 'مانوميتا',
    sku: 'SKU',
    packageSize: packageSize,
    unitOfMeasure: unitOfMeasure,
    packageType: packageType,
    purchasePrice: '0',
    sellingPrice: sellingPrice,
    currentStock: stock,
    minimumStock: '0',
    unit: unit,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('SaleUnitConverter', () {
    test('package sale keeps quantity and multiplies package price', () {
      final converter = SaleUnitConverter.forProduct(_product());
      final package = converter.options.firstWhere((o) => o.isPackage);
      final result = converter.evaluate(
        option: package,
        rawInput: '2',
        availablePackages: Quantity.parse('18'),
      );
      expect(result.error, isNull);
      expect(result.breakdown!.packageQuantity.toDisplay(), '2');
      expect(result.breakdown!.totalPrice.toStorage(), '500.000');
    });

    test('fractional gram sale converts to half package', () {
      final converter = SaleUnitConverter.forProduct(_product());
      final grams = converter.options.firstWhere((o) => o.label == 'جم');
      final result = converter.evaluate(
        option: grams,
        rawInput: '250',
        availablePackages: Quantity.parse('18'),
      );
      expect(result.error, isNull);
      expect(result.breakdown!.packageQuantity.toDisplay(), '0.5');
      expect(result.breakdown!.totalPrice.toStorage(), '125.000');
      expect(
        '${result.breakdown!.packageLabel} | الإجمالي: ${result.breakdown!.totalPrice.toDisplay()} ${Money.currencySymbol}',
        '0.5 عبوة | الإجمالي: 125.000 ج.م.',
      );
    });

    test('kilogram input converts when base unit is grams', () {
      final converter = SaleUnitConverter.forProduct(_product());
      final kg = converter.options.firstWhere((o) => o.label == 'كجم');
      final result = converter.evaluate(
        option: kg,
        rawInput: '0.25',
        availablePackages: Quantity.parse('18'),
      );
      expect(result.error, isNull);
      expect(result.breakdown!.packageQuantity.toDisplay(), '0.5');
      expect(result.breakdown!.totalPrice.toStorage(), '125.000');
    });

    test('rejects over-stock sub-unit sale', () {
      final converter = SaleUnitConverter.forProduct(_product(stock: '1'));
      final grams = converter.options.firstWhere((o) => o.label == 'جم');
      final result = converter.evaluate(
        option: grams,
        rawInput: '600',
        availablePackages: Quantity.parse('1'),
      );
      expect(result.breakdown, isNull);
      expect(result.error, 'المخزون غير كافٍ.');
    });

    test('hides sub units when package size is one piece', () {
      final converter = SaleUnitConverter.forProduct(
        _product(packageSize: '1', unitOfMeasure: 'pcs', packageType: 'قطعة'),
      );
      expect(converter.hasSubUnits, isFalse);
      expect(converter.options, hasLength(1));
    });

    test('non-numeric input is rejected', () {
      final converter = SaleUnitConverter.forProduct(_product());
      final result = converter.evaluate(
        option: converter.options.first,
        rawInput: 'abc',
        availablePackages: Quantity.parse('5'),
      );
      expect(result.breakdown, isNull);
      expect(result.error, 'الكمية غير صالحة.');
    });
  });

  group('convertUnitFamily', () {
    test('kg to g and back', () {
      final grams = convertUnitFamily(
        Quantity.parse('0.25'),
        ProductUnit.kilogram,
        ProductUnit.gram,
      );
      expect(grams.toDisplay(), '250');
      final kilos = convertUnitFamily(
        grams,
        ProductUnit.gram,
        ProductUnit.kilogram,
      );
      expect(kilos.toDisplay(), '0.25');
    });
  });

  group('legacy sale item deserialization', () {
    test('old invoices default to package sale of quantity', () {
      final item = saleItemFromMap({
        'sale_id': 's1',
        'product_id': 'p1',
        'quantity': '2',
        'unit': 'عبوة',
        'unit_price': '250',
        'line_total': '500',
        'created_at': '2026-01-01T00:00:00.000Z',
      }, 'i1');
      expect(item.selectedUnit, 'package');
      expect(item.inputQuantity, '2');
      expect(item.convertedPackageQuantity, '2');
      expect(item.inputUnit, 'عبوة');
    });

    test('new fields round-trip', () {
      final item = saleItemFromMap({
        'sale_id': 's1',
        'product_id': 'p1',
        'quantity': '0.5',
        'unit': 'عبوة',
        'unit_price': '250',
        'line_total': '125',
        'selected_unit': 'subUnit',
        'input_quantity': '250',
        'input_unit': 'جم',
        'created_at': '2026-01-01T00:00:00.000Z',
      }, 'i1');
      expect(item.selectedUnit, 'subUnit');
      expect(item.inputQuantity, '250');
      expect(item.convertedPackageQuantity, '0.5');
      expect(SaleUnitKind.fromStorage(item.selectedUnit), SaleUnitKind.subUnit);
    });
  });
}
