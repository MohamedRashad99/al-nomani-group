import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../operational_status.dart';

class LinkedRecord {
  const LinkedRecord({
    required this.id,
    required this.title,
    required this.route,
  });

  final String id;
  final String title;
  final String route;
}

class EntityLinkReport {
  const EntityLinkReport({
    required this.entityType,
    required this.entityName,
    required this.canDelete,
    required this.summary,
    required this.activeSales,
    required this.cancelledSales,
    required this.activePurchases,
    required this.cancelledPurchases,
    required this.receipts,
    required this.accountEntries,
    required this.inventoryMovements,
    required this.returns,
    required this.outstanding,
    required this.activeSaleLinks,
    required this.activePurchaseLinks,
    required this.steps,
    this.extraLinks = const [],
    this.purchasesNotApplicable = false,
  });

  final String entityType;
  final String entityName;
  final bool canDelete;
  final String summary;
  final int activeSales;
  final int cancelledSales;
  final int activePurchases;
  final int cancelledPurchases;
  final int receipts;
  final int accountEntries;
  final int inventoryMovements;
  final int returns;
  final Money outstanding;
  final List<LinkedRecord> activeSaleLinks;
  final List<LinkedRecord> activePurchaseLinks;
  final List<String> steps;
  final List<LinkedRecord> extraLinks;
  final bool purchasesNotApplicable;
}

class EntityLinkInspector {
  EntityLinkInspector(this._store);
  final ErpStore _store;

  Future<EntityLinkReport> inspectProduct(String productId) async {
    final product = await _store.getProduct(productId);
    final name = product?.name ?? 'المنتج';
    final saleItems = await _store.listSaleItems(productId: productId);
    final purchaseItems = await _store.listPurchaseItems(productId: productId);
    final sales = await _store.listSales();
    final purchases = await _store.listPurchases();
    final movements = await _store.listMovements(productId: productId);
    final accountTx = await _store.listAccountTx();

    final salesById = {for (final sale in sales) sale.id: sale};
    final purchasesById = {
      for (final purchase in purchases) purchase.id: purchase,
    };

    final saleIds = {for (final item in saleItems) item.saleId};
    final purchaseIds = {for (final item in purchaseItems) item.purchaseId};

    final relatedSales = [
      for (final id in saleIds)
        if (salesById[id] != null) salesById[id]!,
    ];
    final relatedPurchases = [
      for (final id in purchaseIds)
        if (purchasesById[id] != null) purchasesById[id]!,
    ];

    final activeSales = [
      for (final sale in relatedSales)
        if (OperationalStatus.isActiveSale(sale)) sale,
    ];
    final cancelledSales = [
      for (final sale in relatedSales)
        if (OperationalStatus.isCancelled(sale.status)) sale,
    ];
    final activePurchases = [
      for (final purchase in relatedPurchases)
        if (OperationalStatus.isActivePurchase(purchase)) purchase,
    ];
    final cancelledPurchases = [
      for (final purchase in relatedPurchases)
        if (OperationalStatus.isCancelled(purchase.status)) purchase,
    ];

    final returns = [
      for (final row in movements)
        if (row.type == 'return' || row.type == 'sale_return') row,
    ];
    final relatedSaleIds = saleIds;
    final accounting = [
      for (final tx in accountTx)
        if (tx.referenceId != null && relatedSaleIds.contains(tx.referenceId))
          tx,
    ];

    final canDelete = activeSales.isEmpty && activePurchases.isEmpty;
    final steps = <String>[
      if (activeSales.isNotEmpty) 'إلغاء فواتير البيع المكتملة المرتبطة بالمنتج.',
      if (activePurchases.isNotEmpty)
        'إلغاء فواتير الشراء المكتملة المرتبطة بالمنتج.',
      'السجلات الملغاة تبقى في الأرشيف ولن تُحذف.',
      'بعد إلغاء الفواتير النشطة أعد محاولة الحذف.',
    ];

    return EntityLinkReport(
      entityType: 'product',
      entityName: name,
      canDelete: canDelete,
      summary: canDelete
          ? 'يمكن حذف المنتج. الفواتير الملغاة تبقى في السجل التاريخي.'
          : 'لا يمكن حذف المنتج لارتباطه بفواتير نشطة.',
      activeSales: activeSales.length,
      cancelledSales: cancelledSales.length,
      activePurchases: activePurchases.length,
      cancelledPurchases: cancelledPurchases.length,
      receipts: 0,
      accountEntries: accounting.length,
      inventoryMovements: movements.length,
      returns: returns.length,
      outstanding: Money.zero(),
      activeSaleLinks: [
        for (final sale in activeSales.take(12))
          LinkedRecord(
            id: sale.id,
            title: sale.saleNumber,
            route: '/sales/${sale.id}',
          ),
      ],
      activePurchaseLinks: [
        for (final purchase in activePurchases.take(12))
          LinkedRecord(
            id: purchase.id,
            title: purchase.purchaseNumber,
            route: '/purchases/${purchase.id}',
          ),
      ],
      steps: steps,
    );
  }

  Future<EntityLinkReport> inspectCustomer(String customerId) async {
    final bundled = await Future.wait<Object?>([
      _store.getCustomer(customerId),
      _store.listSales(),
      _store.listCollections(),
      _store.getAccountByCustomer(customerId),
      _store.listAccountTx(customerId: customerId),
    ]);
    final customer = bundled[0] as Customer?;
    final name = customer?.name ?? 'العميل';
    final sales = [
      for (final sale in bundled[1] as List<Sale>)
        if (sale.customerId == customerId && !sale.isDeleted) sale,
    ];
    final collections = [
      for (final row in bundled[2] as List<Collection>)
        if (row.customerId == customerId && !row.isDeleted) row,
    ];
    final account = bundled[3] as CustomerAccount?;
    final txs = bundled[4] as List<CustomerAccountTransaction>;

    final activeSales = [
      for (final sale in sales)
        if (OperationalStatus.isActiveSale(sale)) sale,
    ];
    final cancelledSales = [
      for (final sale in sales)
        if (OperationalStatus.isCancelled(sale.status)) sale,
    ];
    final outstanding = Money.parse(account?.cachedBalance ?? '0');
    final canDelete = activeSales.isEmpty && outstanding.isZero;

    final steps = <String>[
      if (activeSales.isNotEmpty) 'إلغاء فواتير البيع المكتملة المتبقية.',
      if (!outstanding.isZero)
        'تسوية الرصيد الآجل حتى يصبح صفراً من كشف الحساب.',
      'عكس القيود يتم عبر إلغاء الفواتير؛ السجلات المحاسبية التاريخية لا تُحذف.',
      'التحصيلات الملغى أثرها تبقى في الأرشيف ولا تُمسح.',
      'بعد استيفاء الشروط أعد محاولة الحذف.',
    ];

    return EntityLinkReport(
      entityType: 'customer',
      entityName: name,
      canDelete: canDelete,
      summary: canDelete
          ? 'يمكن حذف العميل. الفواتير والتحصيلات الملغاة تبقى في السجل.'
          : 'لا يمكن حذف العميل لوجود فواتير نشطة أو رصيد آجل.',
      activeSales: activeSales.length,
      cancelledSales: cancelledSales.length,
      activePurchases: 0,
      cancelledPurchases: 0,
      receipts: collections.length,
      accountEntries: txs.length,
      inventoryMovements: 0,
      returns: 0,
      outstanding: outstanding,
      activeSaleLinks: [
        for (final sale in activeSales.take(12))
          LinkedRecord(
            id: sale.id,
            title: sale.saleNumber,
            route: '/sales/${sale.id}',
          ),
      ],
      activePurchaseLinks: const [],
      steps: steps,
      extraLinks: [
        LinkedRecord(
          id: customerId,
          title: 'كشف حساب العميل',
          route: '/customers/$customerId/statement',
        ),
        if (!outstanding.isZero)
          const LinkedRecord(
            id: 'outstanding',
            title: 'المبالغ الآجلة',
            route: '/outstanding',
          ),
      ],
      purchasesNotApplicable: true,
    );
  }
}
