import 'package:al_nomani_group/data/remote/erp_map.dart';
import 'package:al_nomani_group/domain/entities/erp_models.dart';
import 'package:al_nomani_group/domain/models/sale_draft.dart';
import 'package:al_nomani_group/domain/models/sale_unit.dart';
import 'package:al_nomani_group/domain/services/sale_unit_conversion.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  String stock = '18',
  String? packageSize = '500',
  String? unitOfMeasure = 'g',
  String? packageType = 'عبوة',
  String sellingPrice = '250',
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Product(
    id: 'p1',
    name: 'منتج',
    sku: 'SKU',
    packageSize: packageSize,
    unitOfMeasure: unitOfMeasure,
    packageType: packageType,
    purchasePrice: '100',
    sellingPrice: sellingPrice,
    currentStock: stock,
    minimumStock: '0',
    unit: 'عبوة',
    createdAt: now,
    updatedAt: now,
  );
}

extension _ConverterHelpers on SaleUnitConverter {
  SaleUnitOption get packageOption =>
      options.firstWhere((option) => option.isPackage);

  List<SaleUnitOption> get subUnitOptions =>
      options.where((option) => !option.isPackage).toList();

  SaleQuantityBreakdown breakdown(SaleUnitOption option, Quantity input) {
    final result = evaluate(
      option: option,
      rawInput: input.toDisplay(),
      availablePackages: Quantity.parse('999999'),
    );
    expect(result.error, isNull, reason: result.error);
    return result.breakdown!;
  }
}

extension _ResultHelpers on SaleQuantityResult {
  bool get isValid => error == null && breakdown != null;
}

void main() {
  group('unit options', () {
    test('offers package, gram and kilogram for a 500g package', () {
      final converter = SaleUnitConverter.forProduct(_product());
      expect(
        converter.options.map((option) => option.label).toList(),
        ['عبوة', 'جم', 'كجم'],
      );
      expect(converter.hasSubUnits, isTrue);
    });

    test('250 grams is half a package at half price', () {
      final converter = SaleUnitConverter.forProduct(_product());
      final grams = converter.subUnitOptions.first;
      final result = converter.breakdown(grams, Quantity.parse('250'));
      expect(result.packageQuantity.toDisplay(), '0.5');
      expect(result.totalPrice.toDisplay(), '125.000');
    });
  });

  group('validation', () {
    final converter = SaleUnitConverter.forProduct(_product());
    final grams = converter.subUnitOptions.first;
    final available = Quantity.parse('18');

    test('rejects over-stock sub-unit quantity', () {
      final result = converter.evaluate(
        option: grams,
        rawInput: '9500',
        availablePackages: available,
      );
      expect(result.isValid, isFalse);
      expect(result.error, 'المخزون غير كافٍ.');
    });
  });

  group('sale item persistence', () {
    test('legacy row without unit fields loads as package sale', () {
      final item = saleItemFromMap(const {
        'sale_id': 's1',
        'product_id': 'p1',
        'quantity': '2.000',
        'unit': 'عبوة',
        'unit_price': '250.000',
        'line_total': '500.000',
      }, 'i1');
      expect(SaleUnitKind.fromStorage(item.selectedUnit), SaleUnitKind.package);
      expect(item.inputQuantity, item.convertedPackageQuantity);
    });
  });
}
