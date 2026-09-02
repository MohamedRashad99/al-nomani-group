import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../operational_status.dart';
import 'inventory_measure.dart';

class ProductInsight {
  const ProductInsight({
    required this.product,
    required this.measure,
    required this.soldPackages,
    required this.purchasedPackages,
    required this.returnedPackages,
    required this.inventoryValue,
    this.monthlyConsumption,
    this.daysRemaining,
  });

  final Product product;
  final InventoryMeasure measure;
  final Quantity soldPackages;
  final Quantity purchasedPackages;
  final Quantity returnedPackages;
  final Money inventoryValue;
  final Quantity? monthlyConsumption;
  final double? daysRemaining;

  Quantity get remainingPackages => measure.packages;
  String get currentStockLabel => measure.packagesLabel;
  String get remainingLabel => measure.actualLabel;
  String get soldLabel => measure.formatActual(soldPackages);
  String get purchasedLabel => measure.formatActual(purchasedPackages);
  String get returnedLabel => measure.formatActual(returnedPackages);
  bool get needsReorder => measure.needsReorder;
}

class InventoryKpiPreview {
  const InventoryKpiPreview({
    required this.inventoryValue,
    required this.lowestStock,
    required this.topSelling,
    required this.reorderCount,
  });

  final Money inventoryValue;
  final List<ProductInsight> lowestStock;
  final List<ProductInsight> topSelling;
  final int reorderCount;
}

class InventoryAnalytics {
  InventoryAnalytics(this._store);

  final ErpStore _store;

  Future<ProductInsight> insightFor(Product product) async {
    final sales = await _store.listSales();
    final saleItems = await _store.listSaleItems(productId: product.id);
    final purchaseItems = await _store.listPurchaseItems(productId: product.id);
    final movements = await _store.listMovements(productId: product.id);
    return _insight(
      product,
      sales: sales,
      saleItems: saleItems,
      purchaseItems: purchaseItems,
      movements: movements,
    );
  }

  Future<Map<String, ProductInsight>> insightsFor(List<Product> products) async {
    final sales = await _store.listSales();
    final saleItems = await _store.listSaleItems();
    final purchaseItems = await _store.listPurchaseItems();
    final movements = await _store.listMovements();
    return {
      for (final product in products)
        product.id: _insight(
          product,
          sales: sales,
          saleItems: [
            for (final item in saleItems)
              if (item.productId == product.id) item,
          ],
          purchaseItems: [
            for (final item in purchaseItems)
              if (item.productId == product.id) item,
          ],
          movements: [
            for (final row in movements)
              if (row.productId == product.id) row,
          ],
        ),
    };
  }

  ProductInsight _insight(
    Product product, {
    required List<Sale> sales,
    required List<SaleItem> saleItems,
    required List<PurchaseItem> purchaseItems,
    required List<InventoryMovement> movements,
  }) {
    final measure = InventoryMeasure.fromProduct(product);
    final activeSales = {
      for (final sale in sales)
        if (OperationalStatus.isActiveSale(sale)) sale.id,
    };
    var sold = Quantity.zero();
    for (final item in saleItems) {
      if (!activeSales.contains(item.saleId)) continue;
      sold += _qty(item.quantity);
    }
    var purchased = Quantity.zero();
    for (final item in purchaseItems) {
      purchased += _qty(item.quantity);
    }
    var returned = Quantity.zero();
    for (final row in movements) {
      if (row.type == 'return' ||
          row.type == 'sale_return' ||
          row.type == 'purchase_return') {
        returned += _qty(row.quantity);
      }
    }
    final monthly = _monthlySold(sales, saleItems, product.id);
    double? daysLeft;
    if (monthly != null && monthly.isPositive && measure.packages.isPositive) {
      final dailyMilli = monthly.milli ~/ BigInt.from(30);
      if (dailyMilli > BigInt.zero) {
        daysLeft =
            measure.packages.milli.toDouble() / dailyMilli.toDouble();
      }
    }
    Money unitPrice;
    try {
      unitPrice = Money.parse(product.purchasePrice);
    } catch (_) {
      unitPrice = Money.zero();
    }
    final inventoryValue = Money.fromMinorUnits(
      (unitPrice.minorUnits * measure.packages.milli) ~/ BigInt.from(1000),
    );
    return ProductInsight(
      product: product,
      measure: measure,
      soldPackages: sold,
      purchasedPackages: purchased,
      returnedPackages: returned,
      inventoryValue: inventoryValue,
      monthlyConsumption: monthly,
      daysRemaining: daysLeft,
    );
  }

  Quantity? _monthlySold(
    List<Sale> sales,
    List<SaleItem> items,
    String productId,
  ) {
    final now = EgyptTime.nowUtc();
    final start = DateTime.utc(now.year, now.month, 1);
    final ids = {
      for (final sale in sales)
        if (OperationalStatus.isActiveSale(sale) &&
            !sale.soldAt.isBefore(start))
          sale.id,
    };
    var qty = Quantity.zero();
    var any = false;
    for (final item in items) {
      if (item.productId != productId || !ids.contains(item.saleId)) continue;
      qty += _qty(item.quantity);
      any = true;
    }
    return any ? qty : null;
  }

  InventoryKpiPreview kpis(List<ProductInsight> insights) {
    var value = Money.zero();
    var reorder = 0;
    final lowest = [...insights]
      ..sort(
        (a, b) => a.measure.actual.compareTo(b.measure.actual),
      );
    final top = [...insights]
      ..sort((a, b) => b.soldPackages.compareTo(a.soldPackages));
    for (final row in insights) {
      value += row.inventoryValue;
      if (row.needsReorder) reorder++;
    }
    return InventoryKpiPreview(
      inventoryValue: value,
      lowestStock: lowest.take(5).toList(),
      topSelling: [
        for (final row in top.take(5))
          if (row.soldPackages.isPositive) row,
      ],
      reorderCount: reorder,
    );
  }

  static Quantity _qty(String raw) {
    try {
      return Quantity.parse(raw);
    } catch (_) {
      return Quantity.zero();
    }
  }
}
