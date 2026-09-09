import 'package:al_nomani_group/domain/entities/erp_models.dart';
import 'package:al_nomani_group/domain/services/catalog_service.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  required String id,
  required String stock,
  required String purchase,
  required String sell,
}) {
  final now = DateTime.utc(2026, 9, 1);
  return Product(
    id: id,
    name: id,
    sku: id,
    purchasePrice: purchase,
    sellingPrice: sell,
    currentStock: stock,
    minimumStock: '0',
    unit: 'عبوة',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('empty catalog summary is zero', () {
    final summary = ProductValueSummary.fromProducts(const []);
    expect(summary.totalProducts, 0);
    expect(summary.purchaseValue.isZero, isTrue);
    expect(summary.sellingValue.isZero, isTrue);
    expect(summary.expectedProfit.isZero, isTrue);
    expect(ProductValueSummary.availableCount(const []), 0);
  });

  test('stock-valued product totals', () {
    final summary = ProductValueSummary.fromProducts([
      _product(id: 'a', stock: '2', purchase: '10', sell: '15'),
      _product(id: 'b', stock: '0', purchase: '8', sell: '20'),
    ]);
    expect(summary.totalProducts, 2);
    expect(summary.purchaseValue, Money.parse('20'));
    expect(summary.sellingValue, Money.parse('30'));
    expect(summary.expectedProfit, Money.parse('10'));
    expect(
      ProductValueSummary.availableCount([
        _product(id: 'a', stock: '2', purchase: '10', sell: '15'),
        _product(id: 'b', stock: '0', purchase: '8', sell: '20'),
      ]),
      1,
    );
  });
}
