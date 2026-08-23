import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../local/app_database.dart';

class ArabicWorkbookBuilder {
  ArabicWorkbookBuilder(this._db);
  final AppDatabase _db;

  Future<Map<String, List<List<Object?>>>> build() async {
    final customers = await _db.select(_db.customers).get();
    final products = await _db.select(_db.products).get();
    final categories = await _db.select(_db.productCategories).get();
    final accounts = await _db.select(_db.customerAccounts).get();
    final accountTx = await _db.select(_db.customerAccountTransactions).get();
    final sales = await _db.select(_db.sales).get();
    final items = await _db.select(_db.saleItems).get();
    final collections = await _db.select(_db.collections).get();
    final movements = await _db.select(_db.inventoryMovements).get();
    final users = await _db.select(_db.users).get();
    final roles = await _db.select(_db.roles).get();
    final settings = await _db.select(_db.settings).get();
    final audits = await _db.select(_db.auditLogs).get();

    final customerNames = {for (final row in customers) row.id: row.name};
    final productNames = {for (final row in products) row.id: row.name};
    final categoryNames = {for (final row in categories) row.id: row.name};
    final userNames = {for (final row in users) row.id: row.displayName};
    final roleNames = {for (final row in roles) row.id: row.displayNameAr};

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
        ['التصنيفات', categories.where((row) => !row.isDeleted).length],
        ['المنتجات', products.where((row) => !row.isDeleted).length],
        ['العملاء', customers.where((row) => !row.isDeleted).length],
        ['المبيعات', sales.where((row) => !row.isDeleted).length],
        ['بنود المبيعات', items.length],
        ['المبالغ الآجلة', accounts.length],
        ['التحصيلات', collections.where((row) => !row.isDeleted).length],
        ['المخزون', movements.length],
        ['المستخدمون', users.where((row) => !row.isDeleted).length],
      ],
      SheetArabic.sales: table(
        [
          'رقم الفاتورة',
          'العميل',
          'الحالة',
          'الإجمالي',
          'المدفوع',
          'المتبقي',
          'نوع الدفع',
          'البائع',
          'التاريخ',
        ],
        sales.where((row) => !row.isDeleted).map((sale) {
          final paid = double.tryParse(sale.paidAmount) ?? 0;
          final remaining = double.tryParse(sale.remainingAmount) ?? 0;
          final payType = paid <= 0
              ? 'credit'
              : remaining <= 0
              ? 'cash'
              : 'partial';
          return [
            sale.saleNumber,
            customerNames[sale.customerId] ?? '',
            sale.status,
            sale.subtotal,
            sale.paidAmount,
            sale.remainingAmount,
            payType,
            userNames[sale.createdBy] ?? sale.createdBy,
            sale.soldAt,
          ];
        }),
      ),
      SheetArabic.saleItems: table(
        [
          'رقم الفاتورة',
          'المنتج',
          'الكمية',
          'الوحدة',
          'سعر الوحدة',
          'الإجمالي',
        ],
        items.map((item) {
          final sale = sales.where((row) => row.id == item.saleId).firstOrNull;
          return [
            sale?.saleNumber ?? item.saleId,
            productNames[item.productId] ?? item.productId,
            item.quantity,
            item.unit,
            item.unitPrice,
            item.lineTotal,
          ];
        }),
      ),
      SheetArabic.customers: table(
        ['الاسم', 'الهاتف', 'العنوان', 'المنطقة', 'الرصيد الآجل', 'نشط'],
        customers.where((row) => !row.isDeleted).map((customer) {
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
        [
          'التاريخ',
          'العميل',
          'النوع',
          'المبلغ',
          'الرصيد بعد الحركة',
          'المستخدم',
        ],
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
          'سعر الشراء',
          'سعر البيع',
          'المخزون الحالي',
          'الوحدة',
          'نشط',
        ],
        products.where((row) => !row.isDeleted).map(
          (product) => [
            product.name,
            product.sku,
            categoryNames[product.categoryId] ?? '',
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
        categories.where((row) => !row.isDeleted).map(
          (row) => [row.name, row.description ?? '', row.isActive],
        ),
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
        collections.where((row) => !row.isDeleted).map(
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
        users.where((row) => !row.isDeleted).map(
          (row) => [
            row.username,
            row.displayName,
            roleNames[row.roleId] ?? row.roleId,
            row.isActive,
          ],
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
    };
  }
}
