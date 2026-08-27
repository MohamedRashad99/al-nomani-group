import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../data/remote/erp_store.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/operational_status.dart';

class ArabicWorkbookBuilder {
  ArabicWorkbookBuilder(this._store);
  final ErpStore _store;

  Future<Map<String, List<List<Object?>>>> build() async {
    final customers = await _store.listCustomers();
    final products = await _store.listProducts();
    final categories = CatalogCategories.all;
    final accounts = await _store.listAccounts();
    final accountTx = await _store.listAccountTx();
    final sales = await _store.listSales();
    final items = await _store.listSaleItems();
    final collections = await _store.listCollections();
    final movements = await _store.listMovements();
    final users = await _store.listUsers();
    final settings = await _store.listSettings();
    final audits = await _store.listAudits();
    final suppliers = await _store.listSuppliers();
    final purchases = await _store.listPurchases();

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
        ['وقت التحديث', SheetArabic.cell(DateTime.now())],
        ['التصنيفات', categories.length],
        ['المنتجات', products.length],
        ['العملاء', customers.length],
        ['الموردون', suppliers.length],
        ['المبيعات المكتملة', completedSales.length],
        ['المبيعات الملغاة', cancelledSales.length],
        ['المشتريات المكتملة', completedPurchases.length],
        ['المشتريات الملغاة', cancelledPurchases.length],
        ['التحصيلات', completedCollections.length],
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
        ['رقم الفاتورة', 'المورد', 'الحالة', 'الإجمالي', 'المدفوع', 'المتبقي'],
        purchases.map(
          (row) => [
            row.purchaseNumber,
            supplierNames[row.supplierId] ?? '',
            row.status,
            row.subtotal,
            row.paidAmount,
            row.remainingAmount,
          ],
        ),
      ),
    };
  }
}
