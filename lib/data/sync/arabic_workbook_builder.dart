import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../data/remote/erp_store.dart';
import '../../domain/cairo_date_range.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/operational_status.dart';
import '../../domain/services/inventory_measure.dart';

class ArabicWorkbookBuilder {
  ArabicWorkbookBuilder(this._store);
  final ErpStore _store;

  Future<Map<String, List<List<Object?>>>> build({CairoDateRange? range}) async {
    late final List<Customer> customers;
    late final List<Product> products;
    late final List<CustomerAccount> accounts;
    late List<CustomerAccountTransaction> accountTx;
    late List<Sale> sales;
    late final List<SaleItem> items;
    late List<Collection> collections;
    late List<InventoryMovement> movements;
    late final List<AppUser> users;
    late final List<AppSetting> settings;
    late final List<AuditLog> audits;
    late final List<Supplier> suppliers;
    late List<Purchase> purchases;
    late List<Expense> expenses;
    await Future.wait([
      _store.listCustomers().then((value) => customers = value),
      _store.listProducts().then((value) => products = value),
      _store.listAccounts().then((value) => accounts = value),
      _store.listAccountTx().then((value) => accountTx = value),
      _store.listSales().then((value) => sales = value),
      _store.listSaleItems().then((value) => items = value),
      _store.listCollections().then((value) => collections = value),
      _store.listMovements().then((value) => movements = value),
      _store.listUsers().then((value) => users = value),
      _store.listSettings().then((value) => settings = value),
      _store.listAudits().then((value) => audits = value),
      _store.listSuppliers().then((value) => suppliers = value),
      _store.listPurchases().then((value) => purchases = value),
      _store.listExpenses().then((value) => expenses = value),
    ]);
    bool inRange(DateTime time) => range == null || range.includes(time);
    sales = [for (final sale in sales) if (inRange(sale.soldAt)) sale];
    purchases = [
      for (final purchase in purchases)
        if (inRange(purchase.purchasedAt)) purchase,
    ];
    collections = [
      for (final row in collections)
        if (inRange(row.collectedAt)) row,
    ];
    movements = [
      for (final row in movements)
        if (inRange(row.createdAt)) row,
    ];
    accountTx = [
      for (final row in accountTx)
        if (inRange(row.createdAt)) row,
    ];
    expenses = [
      for (final row in expenses)
        if (inRange(row.occurredAt)) row,
    ];
    final categories = CatalogCategories.all;

    final customerNames = {for (final row in customers) row.id: row.name};
    final productNames = {for (final row in products) row.id: row.name};
    final categoryNames = {for (final row in categories) row.id: row.name};
    final userNames = {for (final row in users) row.id: row.displayName};
    final supplierNames = {for (final row in suppliers) row.id: row.name};

    final completedSales = [
      for (final sale in sales)
        if (OperationalStatus.isActiveSale(sale)) sale,
    ];
    final cancelledSales = [
      for (final sale in sales)
        if (OperationalStatus.isCancelled(sale.status)) sale,
    ];
    final completedPurchases = [
      for (final purchase in purchases)
        if (OperationalStatus.isActivePurchase(purchase)) purchase,
    ];
    final cancelledPurchases = [
      for (final purchase in purchases)
        if (OperationalStatus.isCancelled(purchase.status)) purchase,
    ];
    final completedCollections = [
      for (final row in collections)
        if (OperationalStatus.isActiveCollection(row)) row,
    ];
    final salesById = {for (final sale in sales) sale.id: sale};

    List<List<Object?>> table(
      List<String> headers,
      Iterable<List<Object?>> rows,
    ) {
      return [
        headers,
        for (final row in rows)
          [for (final value in row) SheetArabic.cell(value)],
      ];
    }

    return {
      SheetArabic.overview: [
        ['البيان', 'العدد'],
        ['وقت التحديث', SheetArabic.cell(EgyptTime.formatDateTime(EgyptTime.nowUtc()))],
        if (range != null) ...[
          ['فترة التقرير', range.label],
          ['من', EgyptTime.formatDate(range.startUtc)],
          ['إلى', EgyptTime.formatDate(range.endInclusiveUtc)],
        ],
        ['التصنيفات', categories.length],
        ['المنتجات', products.length],
        ['العملاء', customers.length],
        ['الموردون', suppliers.length],
        ['المبيعات المكتملة', completedSales.length],
        ['المبيعات الملغاة', cancelledSales.length],
        ['المشتريات المكتملة', completedPurchases.length],
        ['المشتريات الملغاة', cancelledPurchases.length],
        ['التحصيلات', completedCollections.length],
        ['المصروفات', expenses.length],
      ],
      SheetArabic.sales: table(
        [
          'رقم الفاتورة',
          'العميل',
          'الحالة',
          'الإجمالي',
          'المدفوع',
          'المتبقي',
          'التاريخ',
        ],
        sales.map(
          (sale) => [
            sale.saleNumber,
            customerNames[sale.customerId] ?? '',
            sale.status,
            sale.subtotal,
            sale.paidAmount,
            sale.remainingAmount,
            sale.soldAt,
          ],
        ),
      ),
      SheetArabic.saleItems: table(
        ['رقم الفاتورة', 'المنتج', 'الكمية', 'الوحدة', 'سعر الوحدة', 'الإجمالي'],
        items.map((item) {
          final sale = salesById[item.saleId];
          if (sale == null || !OperationalStatus.isActiveSale(sale)) {
            return <Object?>[];
          }
          return [
            sale.saleNumber,
            productNames[item.productId] ?? item.productId,
            item.quantity,
            item.unit,
            item.unitPrice,
            item.lineTotal,
          ];
        }).where((row) => row.isNotEmpty),
      ),
      SheetArabic.customers: table(
        ['الاسم', 'الهاتف', 'العنوان', 'المنطقة', 'الرصيد الآجل', 'نشط'],
        customers.map((customer) {
          final account = accounts
              .where((row) => row.customerId == customer.id)
              .firstOrNull;
          return [
            customer.name,
            customer.phone ?? '',
            customer.address ?? '',
            customer.area ?? '',
            account?.cachedBalance ?? '0',
            customer.isActive,
          ];
        }),
      ),
      SheetArabic.outstanding: table(
        ['العميل', 'الرصيد الآجل'],
        accounts.map(
          (account) => [
            customerNames[account.customerId] ?? account.customerId,
            account.cachedBalance,
          ],
        ),
      ),
      SheetArabic.accountTransactions: table(
        ['التاريخ', 'العميل', 'النوع', 'المبلغ', 'الرصيد بعد الحركة', 'المستخدم'],
        accountTx.map(
          (tx) => [
            tx.createdAt,
            customerNames[tx.customerId] ?? tx.customerId,
            tx.type,
            tx.amount,
            tx.runningBalance,
            userNames[tx.createdBy] ?? tx.createdBy,
          ],
        ),
      ),
      SheetArabic.products: table(
        [
          'الاسم',
          'الرمز',
          'التصنيف',
          'الحجم',
          'سعر الشراء',
          'سعر البيع',
          'المخزون الحالي',
          'الكمية الفعلية',
          'الوحدة',
          'نشط',
        ],
        products.map(
          (product) => [
            product.name,
            product.sku,
            categoryNames[product.categoryId] ?? '',
            product.packSize ?? '',
            product.purchasePrice,
            product.sellingPrice,
            product.currentStock,
            InventoryMeasure.fromProduct(product).actualLabel,
            product.unit,
            product.isActive,
          ],
        ),
      ),
      SheetArabic.categories: table(
        ['الاسم', 'الوصف', 'نشط'],
        categories.map((row) => [row.name, row.description ?? '', row.isActive]),
      ),
      SheetArabic.inventory: table(
        [
          'التاريخ',
          'المنتج',
          'النوع',
          'الكمية',
          'المخزون السابق',
          'المخزون الجديد',
          'المستخدم',
        ],
        movements.map(
          (row) => [
            row.createdAt,
            productNames[row.productId] ?? row.productId,
            row.type,
            row.quantity,
            row.previousStock,
            row.newStock,
            userNames[row.createdBy] ?? row.createdBy,
          ],
        ),
      ),
      SheetArabic.collections: table(
        ['العميل', 'المبلغ', 'طريقة الدفع', 'التاريخ', 'المحصّل', 'الحالة'],
        collections.map(
          (row) => [
            customerNames[row.customerId] ?? row.customerId,
            row.amount,
            row.paymentMethod,
            row.collectedAt,
            userNames[row.createdBy] ?? row.createdBy,
            row.status,
          ],
        ),
      ),
      SheetArabic.users: table(
        ['اسم المستخدم', 'الاسم', 'الدور', 'نشط'],
        users.map(
          (row) => [row.username, row.displayName, row.roleId, row.isActive],
        ),
      ),
      SheetArabic.settings: table(
        ['المفتاح', 'القيمة'],
        settings.map((row) => [row.key, row.value]),
      ),
      SheetArabic.auditLogs: table(
        ['التاريخ', 'الإجراء', 'النوع', 'المستخدم'],
        audits.map(
          (row) => [
            row.createdAt,
            row.action,
            row.entityType,
            userNames[row.userId] ?? row.userId ?? '',
          ],
        ),
      ),
      'الموردون': table(
        ['الاسم', 'الهاتف', 'المنطقة'],
        suppliers.map((row) => [row.name, row.phone ?? '', row.area ?? '']),
      ),
      'المشتريات': table(
        [
          'رقم الفاتورة',
          'المورد',
          'الحالة',
          'الإجمالي',
          'المدفوع',
          'المتبقي',
          'التاريخ',
        ],
        purchases.map(
          (row) => [
            row.purchaseNumber,
            supplierNames[row.supplierId] ?? '',
            row.status,
            row.subtotal,
            row.paidAmount,
            row.remainingAmount,
            row.purchasedAt,
          ],
        ),
      ),
    };
  }
}
