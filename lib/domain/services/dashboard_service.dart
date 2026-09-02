import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../operational_status.dart';
import 'inventory_measure.dart';

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

class DashboardInsight {
  const DashboardInsight({
    required this.id,
    required this.name,
    required this.detail,
  });

  final String id;
  final String name;
  final String detail;
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
  final List<Product> outOfStockProducts;
  final List<DashboardInsight> fastMoving;
  final List<DashboardInsight> slowMoving;
  final List<DashboardInsight> expectedShortages;
  final List<DashboardInsight> expectedPurchases;
  final List<DashboardInsight> consumption;
  final List<DashboardInsight> fastMovingToday;
  final List<DashboardInsight> fastMovingWeek;
  final List<DashboardInsight> reorderAlerts;

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
    this.outOfStockProducts = const [],
    this.fastMoving = const [],
    this.slowMoving = const [],
    this.expectedShortages = const [],
    this.expectedPurchases = const [],
    this.consumption = const [],
    this.fastMovingToday = const [],
    this.fastMovingWeek = const [],
    this.reorderAlerts = const [],
  });
}

class DashboardService {
  DashboardService(this._store);
  final ErpStore _store;
  String? _lastFingerprint;

  Stream<DashboardSnapshot> watch() async* {
    final first = await load();
    _lastFingerprint = _fingerprint(first);
    yield first;
    await for (final _ in _store.watchChanges()) {
      final next = await load();
      final key = _fingerprint(next);
      if (key == _lastFingerprint) continue;
      _lastFingerprint = key;
      yield next;
    }
  }

  String _fingerprint(DashboardSnapshot snapshot) {
    return [
      snapshot.todaySales.toStorage(),
      snapshot.weeklySales.toStorage(),
      snapshot.monthlySales.toStorage(),
      snapshot.outstandingDebt.toStorage(),
      snapshot.monthlyCollections.toStorage(),
      snapshot.totalProducts,
      snapshot.lowStock,
      snapshot.outOfStock,
      snapshot.recentSales.map((row) => '${row.id}:${row.updatedAt}').join(),
      snapshot.recentCollections.map((row) => row.id).join(),
      snapshot.recentMovements.map((row) => row.id).join(),
      snapshot.fastMoving.map((row) => row.id).join(),
      snapshot.expectedShortages.map((row) => row.id).join(),
      snapshot.consumption.map((row) => '${row.id}:${row.detail}').join(),
      snapshot.reorderAlerts.map((row) => row.id).join(),
    ].join('|');
  }

  Future<DashboardSnapshot> load() async {
    final now = EgyptTime.nowUtc();
    final startToday = EgyptTime.startOfTodayCairo();
    final cairoToday = EgyptTime.toCairo(startToday);
    final startWeek = startToday.subtract(
      Duration(days: cairoToday.weekday % 7),
    );
    final cairoNow = EgyptTime.toCairo(now);
    final startMonth = EgyptTime.startOfDayCairo(
      DateTime.utc(cairoNow.year, cairoNow.month, 1),
    );
    final startYesterday = startToday.subtract(const Duration(days: 1));

    final allSalesFuture = _store.listSales();
    final collectionsFuture = _store.listCollections();
    final productsFuture = _store.listProducts();
    final accountsFuture = _store.listAccounts();
    final saleItemsFuture = _store.listSaleItems();
    final customersFuture = _store.listCustomers();
    final movementsFuture = _store.listMovements();
    final allSales = await allSalesFuture;
    final collectionsRaw = await collectionsFuture;
    final products = await productsFuture;
    final accounts = await accountsFuture;
    final saleItems = await saleItemsFuture;
    final customers = await customersFuture;
    final movements = await movementsFuture;
    final sales = [
      for (final sale in allSales)
        if (OperationalStatus.isActiveSale(sale)) sale,
    ];
    final completedIds = {for (final sale in sales) sale.id};
    final collections = [
      for (final row in collectionsRaw)
        if (OperationalStatus.isActiveCollection(row)) row,
    ];

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
      final measure = InventoryMeasure.fromProduct(p);
      if (measure.isOutOfStock) {
        out++;
      } else if (measure.isLowStock) {
        low++;
      }
    }

    final recentSales = [...sales]..sort((a, b) => b.soldAt.compareTo(a.soldAt));
    final recentCols = [...collections]
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));

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
          final measure = InventoryMeasure.fromProduct(product);
          return measure.isLowStock || measure.needsReorder;
        }).toList()..sort(
          (a, b) => InventoryMeasure.fromProduct(
            a,
          ).actual.compareTo(InventoryMeasure.fromProduct(b).actual),
        );
    final outOfStockProducts =
        products
            .where((product) => InventoryMeasure.fromProduct(product).isOutOfStock)
            .toList();

    Quantity qtyOf(String raw) {
      try {
        return Quantity.parse(raw);
      } catch (_) {
        return Quantity.zero();
      }
    }

    Map<String, Quantity> soldIn(DateTime from) {
      final ids = {
        for (final sale in sales)
          if (!sale.soldAt.isBefore(from)) sale.id,
      };
      final qty = <String, Quantity>{};
      for (final item in saleItems) {
        if (!ids.contains(item.saleId)) continue;
        final amount = qtyOf(item.quantity);
        qty.update(
          item.productId,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      }
      return qty;
    }

    List<DashboardInsight> rankMoving(
      Map<String, Quantity> qty, {
      required String period,
      int take = 5,
    }) {
      final ranked = qty.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final out = <DashboardInsight>[];
      for (final entry in ranked) {
        final product = productById[entry.key];
        if (product == null) continue;
        out.add(
          DashboardInsight(
            id: entry.key,
            name: product.name,
            detail:
                'تم بيع ${InventoryMeasure.fromProduct(product).formatActual(entry.value)} $period',
          ),
        );
        if (out.length >= take) break;
      }
      return out;
    }

    final start30 = startToday.subtract(const Duration(days: 30));
    final qtyToday = soldIn(startToday);
    final qtyWeek = soldIn(startWeek);
    final qtyMonth = soldIn(startMonth);
    final qty30 = soldIn(start30);

    DashboardInsight insightFor(String id, String detail) => DashboardInsight(
      id: id,
      name: productById[id]?.name ?? 'منتج',
      detail: detail,
    );
    final fastMovingToday = rankMoving(qtyToday, period: 'اليوم');
    final fastMovingWeek = rankMoving(qtyWeek, period: 'هذا الأسبوع');
    final fastMoving = rankMoving(qtyMonth, period: 'هذا الشهر');
    final slowMoving = [
      for (final product in products)
        if (!qty30.containsKey(product.id) &&
            InventoryMeasure.fromProduct(product).packages.isPositive)
          insightFor(
            product.id,
            'بدون حركة بيع • ${InventoryMeasure.fromProduct(product).actualLabel}',
          ),
    ].take(5).toList();
    final consumption = [
      for (final entry in (qtyMonth.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))).take(6))
        insightFor(
          entry.key,
          'تم بيع ${InventoryMeasure.fromProduct(productById[entry.key]!).formatActual(entry.value)} من المنتج',
        ),
    ];
    final expectedShortages = <DashboardInsight>[];
    final expectedPurchases = <DashboardInsight>[];
    final reorderAlerts = <DashboardInsight>[];
    for (final product in products) {
      final measure = InventoryMeasure.fromProduct(product);
      if (measure.needsReorder) {
        reorderAlerts.add(
          insightFor(
            product.id,
            '${measure.remainingLabel} • الحد ${measure.formatActual(measure.minimumPackages)}',
          ),
        );
      }
      final sold = qty30[product.id];
      if (sold == null || sold.isZero) continue;
      final daily = sold.milli ~/ BigInt.from(30);
      if (daily <= BigInt.zero) continue;
      final daysLeft = measure.packages.milli ~/ daily;
      if (daysLeft <= BigInt.from(14)) {
        expectedShortages.add(
          insightFor(
            product.id,
            'يتوقع النفاد خلال ${daysLeft.toString()} يوماً • ${measure.actualLabel}',
          ),
        );
        expectedPurchases.add(
          insightFor(product.id, 'يحتاج شراء قبل نفاد ${measure.actualLabel}'),
        );
      }
    }

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
      outOfStockProducts: outOfStockProducts.take(6).toList(),
      fastMoving: fastMoving,
      slowMoving: slowMoving,
      expectedShortages: expectedShortages.take(5).toList(),
      expectedPurchases: expectedPurchases.take(5).toList(),
      consumption: consumption,
      fastMovingToday: fastMovingToday,
      fastMovingWeek: fastMovingWeek,
      reorderAlerts: reorderAlerts.take(6).toList(),
    );
  }
}
