import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import '../models/purchase_draft.dart';
import '../session.dart';
import 'audit_service.dart';
import 'inventory_service.dart';
import 'supplier_account_service.dart';

class PurchaseResult {
  const PurchaseResult({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.subtotal,
    required this.paid,
    required this.remaining,
  });

  final String purchaseId;
  final String purchaseNumber;
  final Money subtotal;
  final Money paid;
  final Money remaining;
}

class PurchaseListEntry {
  const PurchaseListEntry({
    required this.purchase,
    required this.supplierName,
    required this.itemCount,
  });

  final Purchase purchase;
  final String supplierName;
  final int itemCount;

  String get paymentType {
    final total = Money.parse(purchase.subtotal);
    final paid = Money.parse(purchase.paidAmount);
    if (paid.isZero) return 'credit';
    if (paid >= total) return 'cash';
    return 'partial';
  }
}

class PurchaseDetails {
  const PurchaseDetails({
    required this.purchase,
    this.supplier,
    required this.items,
    required this.productNames,
  });

  final Purchase purchase;
  final Supplier? supplier;
  final List<PurchaseItem> items;
  final Map<String, String> productNames;
}

class PurchaseService {
  PurchaseService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
    required InventoryService inventory,
    required SupplierAccountService accounts,
  }) : _store = store,
       _devices = devices,
       _audit = audit,
       _inventory = inventory,
       _accounts = accounts;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AuditService _audit;
  final InventoryService _inventory;
  final SupplierAccountService _accounts;

  Stream<List<Purchase>> watch() => _store.watchPurchases();

  Stream<List<PurchaseListEntry>> watchEntries() async* {
    yield await listEntries();
    await for (final _ in _store.watchChanges()) {
      yield await listEntries();
    }
  }

  Future<List<PurchaseListEntry>> listEntries({String? supplierId}) async {
    final purchasesFuture = _store.listPurchases(supplierId: supplierId);
    final suppliersFuture = _store.listSuppliers();
    final itemsFuture = _store.listPurchaseItems();
    final purchases = await purchasesFuture;
    final suppliers = {
      for (final supplier in await suppliersFuture) supplier.id: supplier.name,
    };
    final items = await itemsFuture;
    final counts = <String, int>{};
    for (final item in items) {
      counts.update(
        item.purchaseId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return [
      for (final purchase in purchases)
        if (!purchase.isDeleted)
          PurchaseListEntry(
            purchase: purchase,
            supplierName: suppliers[purchase.supplierId] ?? 'مورد غير متاح',
            itemCount: counts[purchase.id] ?? 0,
          ),
    ];
  }

  Future<PurchaseDetails?> loadDetails(String purchaseId) async {
    final purchase = await _store.getPurchase(purchaseId);
    if (purchase == null) return null;
    final supplier = await _store.getSupplier(purchase.supplierId);
    final items = await _store.listPurchaseItems(purchaseId: purchaseId);
    final products = await _store.listProducts();
    return PurchaseDetails(
      purchase: purchase,
      supplier: supplier,
      items: items,
      productNames: {for (final product in products) product.id: product.name},
    );
  }

  Future<Purchase?> get(String id) => _store.getPurchase(id);

  Future<List<PurchaseItem>> items(String purchaseId) =>
      _store.listPurchaseItems(purchaseId: purchaseId);

  Future<PurchaseResult> create(AppSession session, PurchaseDraft draft) async {
    if (!session.can(AppPermission.purchasesCreate)) {
      throw const PermissionException();
    }
    if (draft.lines.isEmpty) {
      throw const ValidationException('أضف منتجاً واحداً على الأقل.');
    }
    if (draft.paidAmount.isNegative || draft.paidAmount > draft.subtotal) {
      throw const ValidationException('المبلغ المدفوع غير صالح.');
    }
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final purchaseId = newId();
    final number = await _nextNumber();
    final remaining = draft.remaining;
    await _store.putPurchase(
      Purchase(
        id: purchaseId,
        supplierId: draft.supplierId,
        purchaseNumber: number,
        subtotal: draft.subtotal.toStorage(),
        paidAmount: draft.paidAmount.toStorage(),
        remainingAmount: remaining.toStorage(),
        notes: draft.notes,
        purchasedAt: now,
        createdBy: session.userId,
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (final line in draft.lines) {
      if (!line.quantity.isPositive) {
        throw const ValidationException('الكمية غير صالحة.');
      }
      await _store.putPurchaseItem(
        PurchaseItem(
          id: newId(),
          purchaseId: purchaseId,
          productId: line.productId,
          quantity: line.quantity.toStorage(),
          unit: line.unit,
          unitPrice: line.unitPrice.toStorage(),
          lineTotal: line.lineTotal.toStorage(),
          deviceId: deviceId,
          createdAt: now,
        ),
      );
      await _inventory.apply(
        session: session,
        productId: line.productId,
        quantity: line.quantity,
        type: 'purchase',
        referenceType: 'purchase',
        referenceId: purchaseId,
      );
    }
    if (!draft.subtotal.isZero) {
      await _accounts.post(
        supplierId: draft.supplierId,
        type: 'purchase',
        amount: draft.subtotal,
        createdBy: session.userId,
        deviceId: deviceId,
        referenceType: 'purchase',
        referenceId: purchaseId,
      );
    }
    if (draft.paidAmount.isPositive) {
      await _accounts.post(
        supplierId: draft.supplierId,
        type: 'payment',
        amount: draft.paidAmount,
        createdBy: session.userId,
        deviceId: deviceId,
        referenceType: 'purchase_payment',
        referenceId: purchaseId,
      );
    }
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'purchase.create',
      entityType: 'purchase',
      entityId: purchaseId,
    );
    return PurchaseResult(
      purchaseId: purchaseId,
      purchaseNumber: number,
      subtotal: draft.subtotal,
      paid: draft.paidAmount,
      remaining: remaining,
    );
  }

  Future<void> cancel(AppSession session, String purchaseId, String reason) async {
    if (!session.can(AppPermission.purchasesCancel)) {
      throw const PermissionException();
    }
    final purchase = await _store.getPurchase(purchaseId);
    if (purchase == null || purchase.isDeleted) {
      throw const ValidationException('فاتورة الشراء غير موجودة.');
    }
    if (purchase.status == 'cancelled') {
      throw const ValidationException('الفاتورة ملغاة مسبقاً.');
    }
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final items = await _store.listPurchaseItems(purchaseId: purchaseId);
    for (final item in items) {
      await _inventory.apply(
        session: session,
        productId: item.productId,
        quantity: Quantity.parse(item.quantity),
        type: 'purchase_cancel',
        referenceType: 'purchase_cancel',
        referenceId: purchaseId,
      );
    }
    final remaining = Money.parse(purchase.remainingAmount);
    final paid = Money.parse(purchase.paidAmount);
    final subtotal = Money.parse(purchase.subtotal);
    final account = await _accounts.requireAccount(purchase.supplierId);
    final current = Money.parse(account.cachedBalance);
    final netReverse = remaining.isNegative ? Money.zero() : remaining;
    if (current + (Money.zero() - netReverse) >= Money.zero()) {
      if (paid.isPositive) {
        await _accounts.post(
          supplierId: purchase.supplierId,
          type: 'payment_cancel',
          amount: paid,
          createdBy: session.userId,
          deviceId: deviceId,
          referenceType: 'purchase_cancel',
          referenceId: purchaseId,
        );
      }
      if (!subtotal.isZero) {
        await _accounts.post(
          supplierId: purchase.supplierId,
          type: 'purchase_cancel',
          amount: subtotal,
          createdBy: session.userId,
          deviceId: deviceId,
          referenceType: 'purchase_cancel',
          referenceId: purchaseId,
        );
      }
    } else if (current.isPositive) {
      await _accounts.post(
        supplierId: purchase.supplierId,
        type: 'purchase_cancel',
        amount: current,
        createdBy: session.userId,
        deviceId: deviceId,
        referenceType: 'purchase_cancel',
        referenceId: purchaseId,
      );
    }
    await _store.putPurchase(
      Purchase(
        id: purchase.id,
        supplierId: purchase.supplierId,
        purchaseNumber: purchase.purchaseNumber,
        status: 'cancelled',
        subtotal: purchase.subtotal,
        paidAmount: purchase.paidAmount,
        remainingAmount: Money.zero().toStorage(),
        notes: purchase.notes,
        purchasedAt: purchase.purchasedAt,
        createdBy: purchase.createdBy,
        cancelledAt: now,
        cancelledBy: session.userId,
        cancelReason: reason,
        version: purchase.version + 1,
        deviceId: deviceId,
        createdAt: purchase.createdAt,
        updatedAt: now,
      ),
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'purchase.cancel',
      entityType: 'purchase',
      entityId: purchaseId,
    );
  }

  Future<void> returnLines(
    AppSession session,
    String purchaseId, {
    Map<String, Quantity>? quantitiesByItemId,
    String? notes,
  }) async {
    if (!session.can(AppPermission.purchasesCreate) &&
        !session.can(AppPermission.purchasesCancel)) {
      throw const PermissionException();
    }
    final purchase = await _store.getPurchase(purchaseId);
    if (purchase == null || purchase.isDeleted) {
      throw const ValidationException('فاتورة الشراء غير موجودة.');
    }
    if (purchase.status == 'cancelled' || purchase.status == 'returned') {
      throw const ValidationException('لا يمكن إرجاع هذه الفاتورة.');
    }
    final items = await _store.listPurchaseItems(purchaseId: purchaseId);
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    var credit = Money.zero();
    var anyReturned = false;
    var allFullyReturned = true;
    for (final item in items) {
      final original = Quantity.parse(item.quantity);
      final already = Quantity.parse(item.returnedQuantity);
      var remaining = original - already;
      if (remaining.isNegative) remaining = Quantity.zero();
      final requested = quantitiesByItemId == null
          ? remaining
          : (quantitiesByItemId[item.id] ?? Quantity.zero());
      if (requested.isNegative || requested.isZero) {
        if (remaining.isPositive) allFullyReturned = false;
        continue;
      }
      if (requested > remaining) {
        throw const ValidationException('كمية المرتجع أكبر من المتبقي.');
      }
      anyReturned = true;
      final nextReturned = already + requested;
      if (nextReturned < original) allFullyReturned = false;
      final lineCredit = Money.fromMinorUnits(
        (requested.milli * Money.parse(item.unitPrice).minorUnits) ~/
            BigInt.from(1000),
      );
      credit += lineCredit;
      await _inventory.apply(
        session: session,
        productId: item.productId,
        quantity: requested,
        type: 'purchase_return',
        notes: notes,
        referenceType: 'purchase_return',
        referenceId: purchaseId,
      );
      await _store.putPurchaseItem(
        PurchaseItem(
          id: item.id,
          purchaseId: item.purchaseId,
          productId: item.productId,
          quantity: item.quantity,
          unit: item.unit,
          unitPrice: item.unitPrice,
          lineTotal: item.lineTotal,
          returnedQuantity: nextReturned.toStorage(),
          version: item.version + 1,
          deviceId: deviceId,
          createdAt: item.createdAt,
        ),
      );
    }
    if (!anyReturned) {
      throw const ValidationException('حدد كمية مرتجع واحدة على الأقل.');
    }
    if (credit.isPositive) {
      await _accounts.post(
        supplierId: purchase.supplierId,
        type: 'purchase_return',
        amount: credit,
        createdBy: session.userId,
        deviceId: deviceId,
        referenceType: 'purchase_return',
        referenceId: purchaseId,
        notes: notes,
        allowNegative: true,
      );
    }
    final remainingUnpaid = Money.parse(purchase.remainingAmount) - credit;
    await _store.putPurchase(
      Purchase(
        id: purchase.id,
        supplierId: purchase.supplierId,
        purchaseNumber: purchase.purchaseNumber,
        status: allFullyReturned ? 'returned' : 'partial',
        subtotal: purchase.subtotal,
        paidAmount: purchase.paidAmount,
        remainingAmount: remainingUnpaid.isNegative
            ? Money.zero().toStorage()
            : remainingUnpaid.toStorage(),
        notes: purchase.notes,
        purchasedAt: purchase.purchasedAt,
        createdBy: purchase.createdBy,
        cancelledAt: purchase.cancelledAt,
        cancelledBy: purchase.cancelledBy,
        cancelReason: purchase.cancelReason,
        version: purchase.version + 1,
        deviceId: deviceId,
        createdAt: purchase.createdAt,
        updatedAt: now,
      ),
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'purchase.return',
      entityType: 'purchase',
      entityId: purchaseId,
      newValue: {'credit': credit.toStorage(), 'notes': notes},
    );
  }

  Future<String> _nextNumber() async {
    final count = (await _store.listPurchases()).length;
    return 'P-${(count + 1).toString().padLeft(6, '0')}';
  }
}
