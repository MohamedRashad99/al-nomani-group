import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';

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
  final List<(String, Money)> topProducts;
  final List<(String, Money)> topCustomers;

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
  });
}

class DashboardService {
  DashboardService(this._db);
  final AppDatabase _db;

  Future<DashboardSnapshot> load() async {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day).toUtc();
    final startWeek = startToday.subtract(
      Duration(days: startToday.weekday % 7),
    );
    final startMonth = DateTime.utc(now.year, now.month, 1);

    final sales =
        await (_db.select(_db.sales)..where(
              (t) => t.isDeleted.equals(false) & t.status.equals('completed'),
            ))
            .get();
    final collections =
        await (_db.select(_db.collections)..where(
              (t) => t.isDeleted.equals(false) & t.status.equals('completed'),
            ))
            .get();
    final products = await (_db.select(
      _db.products,
    )..where((t) => t.isDeleted.equals(false))).get();
    final accounts = await _db.select(_db.customerAccounts).get();

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

    final recentSales = [...sales]
      ..sort((a, b) => b.soldAt.compareTo(a.soldAt));
    final recentCols = [...collections]
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    final movements =
        await (_db.select(_db.inventoryMovements)
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(8))
            .get();

    return DashboardSnapshot(
      todaySales: sumSales(startToday),
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
      recentMovements: movements,
      topProducts: const [],
      topCustomers: const [],
    );
  }
}
