import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';

class DashboardRank {
  const DashboardRank({
    required this.id,
    required this.name,
    required this.amount,
    this.secondary,
  });

  final String id;
  final String name;
  final Money amount;
  final String? secondary;
}

class SalesTrendPoint {
  const SalesTrendPoint({required this.date, required this.amount});

  final DateTime date;
  final Money amount;
}

class DashboardSnapshot {
  final Money todaySales;
  final Money weeklySales;
  final Money monthlySales;
  final Money outstandingDebt;
  final int customersWithDebt;
  final Money todayCollections;
  final Money monthlyCollections;
  final int totalProducts;
  final int lowStock;
  final int outOfStock;
  final List<Sale> recentSales;
  final List<Collection> recentCollections;
  final List<InventoryMovement> recentMovements;
  final List<DashboardRank> topProducts;
  final List<DashboardRank> topCustomers;
  final List<Product> lowStockProducts;
  final List<SalesTrendPoint> salesTrend;
  final double todaySalesChangePercent;
  final Map<String, String> customerNames;
  final Map<String, String> productNames;

  const DashboardSnapshot({
    required this.todaySales,
    required this.weeklySales,
    required this.monthlySales,
    required this.outstandingDebt,
    required this.customersWithDebt,
    required this.todayCollections,
    required this.monthlyCollections,
    required this.totalProducts,
    required this.lowStock,
    required this.outOfStock,
    required this.recentSales,
    required this.recentCollections,
    required this.recentMovements,
    required this.topProducts,
    required this.topCustomers,
    required this.lowStockProducts,
    required this.salesTrend,
    required this.todaySalesChangePercent,
    required this.customerNames,
    required this.productNames,
  });
}

class DashboardService {
  DashboardService(this._store);
  final ErpStore _store;

  Stream<DashboardSnapshot> watch() async* {
    yield await load();
    await for (final _ in _store.watchChanges()) {
      yield await load();
    }
  }

  Future<DashboardSnapshot> load() async {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day).toUtc();
    final startWeek = startToday.subtract(
      Duration(days: startToday.weekday % 7),
    );
    final startMonth = DateTime.utc(now.year, now.month, 1);
    final startYesterday = startToday.subtract(const Duration(days: 1));

    final allSales = await _store.listSales();
    final sales = [
      for (final sale in allSales)
        if (!sale.isDeleted && sale.status == 'completed') sale,
    ];
    final completedIds = {for (final sale in sales) sale.id};
    final collections = [
      for (final row in await _store.listCollections())
        if (!row.isDeleted && row.status == 'completed') row,
    ];
    final products = await _store.listProducts();
    final accounts = await _store.listAccounts();
    final saleItems = await _store.listSaleItems();
    final customers = await _store.listCustomers();

    Money sumSales(DateTime from) => sales
        .where((s) => s.soldAt.isAfter(from) || s.soldAt.isAtSameMomentAs(from))
        .fold(Money.zero(), (m, s) => m + Money.parse(s.subtotal));

    Money sumCol(DateTime from) => collections
        .where(
          (c) =>
              c.collectedAt.isAfter(from) ||
              c.collectedAt.isAtSameMomentAs(from),
        )
        .fold(Money.zero(), (m, c) => m + Money.parse(c.amount));

    final debtAccounts = accounts
        .where((a) => Money.parse(a.cachedBalance).isPositive)
        .toList();
    final debt = debtAccounts.fold(
      Money.zero(),
      (m, a) => m + Money.parse(a.cachedBalance),
    );

    var low = 0;
    var out = 0;
    for (final p in products) {
      final stock = Quantity.parse(p.currentStock);
      if (!stock.isPositive) {
        out++;
      } else if (stock <= Quantity.parse(p.minimumStock)) {
        low++;
      }
    }

    final recentSales = [...sales]..sort((a, b) => b.soldAt.compareTo(a.soldAt));
    final recentCols = [...collections]
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    final movements = await _store.listMovements();

    final productById = {for (final product in products) product.id: product};
    final productTotals = <String, Money>{};
    for (final item in saleItems) {
      if (!completedIds.contains(item.saleId)) continue;
      productTotals.update(
        item.productId,
        (value) => value + Money.parse(item.lineTotal),
        ifAbsent: () => Money.parse(item.lineTotal),
      );
    }
    final topProducts =
        productTotals.entries
            .map(
              (entry) => DashboardRank(
                id: entry.key,
                name: productById[entry.key]?.name ?? 'منتج غير متاح',
                amount: entry.value,
                secondary: productById[entry.key]?.sku,
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    final customerById = {for (final customer in customers) customer.id: customer};
    final customerTotals = <String, Money>{};
    for (final sale in sales) {
      customerTotals.update(
        sale.customerId,
        (value) => value + Money.parse(sale.subtotal),
        ifAbsent: () => Money.parse(sale.subtotal),
      );
    }
    final topCustomers =
        customerTotals.entries
            .map(
              (entry) => DashboardRank(
                id: entry.key,
                name: customerById[entry.key]?.name ?? 'عميل غير متاح',
                amount: entry.value,
                secondary: customerById[entry.key]?.area,
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    final salesTrend = <SalesTrendPoint>[];
    for (var daysAgo = 6; daysAgo >= 0; daysAgo--) {
      final day = startToday.subtract(Duration(days: daysAgo));
      final nextDay = day.add(const Duration(days: 1));
      final amount = sales
          .where(
            (sale) =>
                !sale.soldAt.isBefore(day) && sale.soldAt.isBefore(nextDay),
          )
          .fold(Money.zero(), (sum, sale) => sum + Money.parse(sale.subtotal));
      salesTrend.add(SalesTrendPoint(date: day, amount: amount));
    }

    final todaySales = sumSales(startToday);
    final yesterdaySales = sales
        .where(
          (sale) =>
              !sale.soldAt.isBefore(startYesterday) &&
              sale.soldAt.isBefore(startToday),
        )
        .fold(Money.zero(), (sum, sale) => sum + Money.parse(sale.subtotal));
    final changePercent = yesterdaySales.isZero
        ? (todaySales.isZero ? 0.0 : 100.0)
        : ((todaySales.minorUnits - yesterdaySales.minorUnits).toDouble() /
                  yesterdaySales.minorUnits.toDouble()) *
              100;

    final lowStockProducts =
        products.where((product) {
          final stock = Quantity.parse(product.currentStock);
          return stock <= Quantity.parse(product.minimumStock);
        }).toList()..sort(
          (a, b) => Quantity.parse(
            a.currentStock,
          ).compareTo(Quantity.parse(b.currentStock)),
        );

    return DashboardSnapshot(
      todaySales: todaySales,
      weeklySales: sumSales(startWeek),
      monthlySales: sumSales(startMonth),
      outstandingDebt: debt,
      customersWithDebt: debtAccounts.length,
      todayCollections: sumCol(startToday),
      monthlyCollections: sumCol(startMonth),
      totalProducts: products.length,
      lowStock: low,
      outOfStock: out,
      recentSales: recentSales.take(6).toList(),
      recentCollections: recentCols.take(6).toList(),
      recentMovements: movements.take(8).toList(),
      topProducts: topProducts.take(5).toList(),
      topCustomers: topCustomers.take(5).toList(),
      lowStockProducts: lowStockProducts.take(6).toList(),
      salesTrend: salesTrend,
      todaySalesChangePercent: changePercent,
      customerNames: {
        for (final customer in customers) customer.id: customer.name,
      },
      productNames: {for (final product in products) product.id: product.name},
    );
  }
}
