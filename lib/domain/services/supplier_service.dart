import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../../data/sync/sync_engine.dart';
import '../entities/erp_models.dart';
import '../session.dart';
import 'audit_service.dart';
import 'supplier_account_service.dart';

class SupplierService {
  SupplierService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
    required SupplierAccountService accounts,
    required SyncEngine sync,
  }) : _store = store,
       _devices = devices,
       _audit = audit,
       _accounts = accounts,
       _sync = sync;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AuditService _audit;
  final SupplierAccountService _accounts;
  final SyncEngine _sync;

  Stream<List<Supplier>> watch(String query) {
    return _store.watchSuppliers().map((items) => _filter(items, query));
  }

  Stream<List<SupplierListEntry>> watchEntries(String query) async* {
    await for (final suppliers in watch(query)) {
      yield await _enrichEntries(suppliers);
    }
  }

  Future<List<SupplierListEntry>> _enrichEntries(List<Supplier> suppliers) async {
    if (suppliers.isEmpty) return const [];
    final accounts = await _store.listSupplierAccounts();
    final accountBySupplier = {
      for (final account in accounts) account.supplierId: account,
    };
    final purchases = await _store.listPurchases();
    final txs = await _store.listSupplierTx();
    return [
      for (final supplier in suppliers)
        SupplierListEntry(
          supplier: supplier,
          totals: _totalsFromCache(
            supplierId: supplier.id,
            purchases: purchases,
            txs: txs,
            account: accountBySupplier[supplier.id],
          ),
        ),
    ];
  }

  SupplierTotals _totalsFromCache({
    required String supplierId,
    required List<Purchase> purchases,
    required List<SupplierAccountTransaction> txs,
    SupplierAccount? account,
  }) {
    var purchaseTotal = Money.zero();
    var paymentTotal = Money.zero();
    for (final purchase in purchases) {
      if (purchase.supplierId != supplierId || purchase.status == 'cancelled') {
        continue;
      }
      purchaseTotal += Money.parse(purchase.subtotal);
    }
    for (final tx in txs) {
      if (tx.supplierId != supplierId) continue;
      if (tx.type == 'payment' ||
          tx.type == 'receipt' ||
          tx.type == 'purchase_return') {
        final signed = Money.parse(tx.amount);
        paymentTotal += signed.isNegative ? -signed : signed;
      }
    }
    return SupplierTotals(
      purchases: purchaseTotal,
      payments: paymentTotal,
      outstanding: Money.parse(account?.cachedBalance ?? '0'),
    );
  }

  Future<SupplierPortfolioSummary> portfolioSummary() async {
    final suppliers = await _store.listSuppliers();
    final accounts = await _store.listSupplierAccounts();
    final purchases = await _store.listPurchases();
    final txs = await _store.listSupplierTx();
    final accountBySupplier = {
      for (final account in accounts) account.supplierId: account,
    };
    var outstanding = Money.zero();
    var payments = Money.zero();
    var activeCount = 0;
    for (final supplier in suppliers) {
      if (supplier.isDeleted) continue;
      if (SupplierListEntry.isActiveSupplier(supplier)) activeCount++;
      final totals = _totalsFromCache(
        supplierId: supplier.id,
        purchases: purchases,
        txs: txs,
        account: accountBySupplier[supplier.id],
      );
      if (totals.outstanding.isPositive) {
        outstanding += totals.outstanding;
      }
      payments += totals.payments;
    }
    return SupplierPortfolioSummary(
      totalOutstanding: outstanding,
      totalPayments: payments,
      activeSuppliers: activeCount,
    );
  }

  Future<List<Supplier>> search(String query) async =>
      _filter(await _store.listSuppliers(), query);

  List<Supplier> _filter(List<Supplier> items, String query) {
    final q = query.trim();
    if (q.isEmpty) return items;
    return [
      for (final item in items)
        if (item.name.contains(q) ||
            (item.phone ?? '').contains(q) ||
            (item.area ?? '').contains(q))
          item,
    ];
  }

  Future<Supplier?> get(String id) => _store.getSupplier(id);

  Future<String> upsert({
    required AppSession session,
    String? id,
    required String name,
    String? phone,
    String? address,
    String? area,
    String? notes,
    String? linkedCustomerId,
    String goodsType = '',
    String? status,
    bool isActive = true,
  }) async {
    final isCreate = id == null;
    if (isCreate && !session.can(AppPermission.suppliersCreate)) {
      throw const PermissionException();
    }
    if (!isCreate && !session.can(AppPermission.suppliersUpdate)) {
      throw const PermissionException();
    }
    if (name.trim().isEmpty) {
      throw const ValidationException('اسم المورد مطلوب.');
    }
    final now = EgyptTime.nowUtc();
    final deviceId = await _devices.deviceId();
    final supplierId = id ?? newId();
    final existing = id == null ? null : await _store.getSupplier(id);
    final nextLink = linkedCustomerId ?? existing?.linkedCustomerId;
    final resolvedStatus = status ?? existing?.status ?? (isActive ? 'active' : 'closed');
    final supplier = Supplier(
      id: supplierId,
      name: name.trim(),
      phone: phone,
      address: address,
      area: area,
      notes: notes,
      linkedCustomerId: nextLink?.trim().isEmpty == true ? null : nextLink,
      goodsType: goodsType.trim(),
      status: resolvedStatus,
      isActive: isActive && resolvedStatus != 'closed',
      version: (existing?.version ?? 0) + 1,
      deviceId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.putSupplier(supplier);
    await _syncLinkedCustomer(
      supplierId,
      existing?.linkedCustomerId,
      supplier.linkedCustomerId,
    );
    if (existing == null) {
      await _store.putSupplierAccount(
        SupplierAccount(
          id: newId(),
          supplierId: supplierId,
          cachedBalance: Money.zero().toStorage(),
          deviceId: deviceId,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: isCreate ? 'supplier.create' : 'supplier.update',
      entityType: 'supplier',
      entityId: supplierId,
    );
    await _sync.maybeSyncAfterLocalWrite();
    return supplierId;
  }

  Future<void> _syncLinkedCustomer(
    String supplierId,
    String? previousCustomerId,
    String? nextCustomerId,
  ) async {
    if (previousCustomerId == nextCustomerId) return;
    if (previousCustomerId != null && previousCustomerId.isNotEmpty) {
      final previous = await _store.getCustomer(previousCustomerId);
      if (previous != null && previous.linkedSupplierId == supplierId) {
        await _store.putCustomer(
          Customer(
            id: previous.id,
            name: previous.name,
            phone: previous.phone,
            address: previous.address,
            area: previous.area,
            notes: previous.notes,
            linkedSupplierId: null,
            isActive: previous.isActive,
            version: previous.version + 1,
            deviceId: previous.deviceId,
            createdAt: previous.createdAt,
            updatedAt: EgyptTime.nowUtc(),
            isDeleted: previous.isDeleted,
          ),
        );
      }
    }
    if (nextCustomerId != null && nextCustomerId.isNotEmpty) {
      final next = await _store.getCustomer(nextCustomerId);
      if (next == null) return;
      if (next.linkedSupplierId == supplierId) return;
      await _store.putCustomer(
        Customer(
          id: next.id,
          name: next.name,
          phone: next.phone,
          address: next.address,
          area: next.area,
          notes: next.notes,
          linkedSupplierId: supplierId,
          isActive: next.isActive,
          version: next.version + 1,
          deviceId: next.deviceId,
          createdAt: next.createdAt,
          updatedAt: EgyptTime.nowUtc(),
          isDeleted: next.isDeleted,
        ),
      );
    }
  }

  Future<SupplierDeleteInspection> inspectDelete(String id) async {
    final purchases = await _store.listPurchases(supplierId: id);
    final active = [
      for (final purchase in purchases)
        if (purchase.status != 'cancelled' && !purchase.isDeleted) purchase,
    ];
    final account = await _store.getAccountBySupplier(id);
    final balance = Money.parse(account?.cachedBalance ?? '0');
    final blockers = <String>[];
    if (active.isNotEmpty) {
      blockers.add(
        'يوجد ${active.length} فاتورة غير ملغاة. سوِّ المتبقي أو ألغِ الفواتير أولاً.',
      );
    }
    if (!balance.isZero) {
      blockers.add(
        'رصيد الحساب ${balance.toDisplay()} ${Money.currencySymbol}. سجّل دفعة أو قيد تصحيح حتى يصبح الرصيد صفراً.',
      );
    }
    return SupplierDeleteInspection(
      canDelete: blockers.isEmpty,
      blockers: blockers,
      activePurchases: active.length,
      archivedPurchases: purchases.length - active.length,
      balance: balance,
    );
  }

  Future<void> delete({
    required AppSession session,
    required String id,
  }) async {
    if (!session.can(AppPermission.suppliersDelete)) {
      throw const PermissionException();
    }
    final inspection = await inspectDelete(id);
    if (!inspection.canDelete) {
      throw ValidationException(inspection.blockers.join('\n'));
    }
    final deviceId = await _devices.deviceId();
    await _store.deleteSupplier(id);
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'supplier.delete',
      entityType: 'supplier',
      entityId: id,
    );
    await _sync.maybeSyncAfterLocalWrite();
  }

  Stream<({SupplierAccount? account, List<SupplierAccountTransaction> txs})>
  watchStatement(String supplierId) async* {
    Future<({SupplierAccount? account, List<SupplierAccountTransaction> txs})>
    load() async {
      return (
        account: await _store.getAccountBySupplier(supplierId),
        txs: await _store.listSupplierTx(supplierId: supplierId),
      );
    }

    yield await load();
    await for (final _ in _store.watchChanges()) {
      yield await load();
    }
  }

  Future<SupplierTotals> totals(String supplierId) async {
    final purchases = await _store.listPurchases(supplierId: supplierId);
    final txs = await _store.listSupplierTx(supplierId: supplierId);
    var purchaseTotal = Money.zero();
    var paymentTotal = Money.zero();
    for (final purchase in purchases) {
      if (purchase.status == 'cancelled') continue;
      purchaseTotal += Money.parse(purchase.subtotal);
    }
    for (final tx in txs) {
      if (tx.type == 'payment' || tx.type == 'receipt' || tx.type == 'purchase_return') {
        final signed = Money.parse(tx.amount);
        paymentTotal += signed.isNegative ? -signed : signed;
      }
    }
    final account = await _store.getAccountBySupplier(supplierId);
    return SupplierTotals(
      purchases: purchaseTotal,
      payments: paymentTotal,
      outstanding: Money.parse(account?.cachedBalance ?? '0'),
    );
  }

  Future<List<Purchase>> purchases(String supplierId) =>
      _store.listPurchases(supplierId: supplierId);

  Future<void> recordPayment({
    required AppSession session,
    required String supplierId,
    required Money amount,
    String? notes,
  }) async {
    if (!session.can(AppPermission.purchasesCreate) &&
        !session.can(AppPermission.suppliersUpdate)) {
      throw const PermissionException();
    }
    if (!amount.isPositive) {
      throw const ValidationException('المبلغ غير صالح.');
    }
    final deviceId = await _devices.deviceId();
    await _accounts.post(
      supplierId: supplierId,
      type: 'payment',
      amount: amount,
      createdBy: session.userId,
      deviceId: deviceId,
      referenceType: 'supplier_payment',
      notes: notes,
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'supplier.payment',
      entityType: 'supplier',
      entityId: supplierId,
      newValue: {'amount': amount.toStorage(), 'notes': notes},
    );
    await _sync.maybeSyncAfterLocalWrite();
  }

  Future<void> recordReceipt({
    required AppSession session,
    required String supplierId,
    required Money amount,
    String? notes,
  }) async {
    if (!session.can(AppPermission.purchasesCreate) &&
        !session.can(AppPermission.suppliersUpdate)) {
      throw const PermissionException();
    }
    if (!amount.isPositive) {
      throw const ValidationException('المبلغ غير صالح.');
    }
    final deviceId = await _devices.deviceId();
    await _accounts.post(
      supplierId: supplierId,
      type: 'receipt',
      amount: amount,
      createdBy: session.userId,
      deviceId: deviceId,
      referenceType: 'supplier_receipt',
      notes: notes,
      allowNegative: true,
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'supplier.receipt',
      entityType: 'supplier',
      entityId: supplierId,
      newValue: {'amount': amount.toStorage(), 'notes': notes},
    );
    await _sync.maybeSyncAfterLocalWrite();
  }

  Future<void> updateTransactionNotes({
    required AppSession session,
    required String transactionId,
    required String notes,
  }) async {
    if (!session.can(AppPermission.suppliersUpdate) &&
        !session.can(AppPermission.purchasesCreate)) {
      throw const PermissionException();
    }
    final txs = await _store.listSupplierTx();
    SupplierAccountTransaction? found;
    for (final tx in txs) {
      if (tx.id == transactionId) found = tx;
    }
    if (found == null) {
      throw const ValidationException('الحركة غير موجودة.');
    }
    final deviceId = await _devices.deviceId();
    await _store.putSupplierTx(found.copyWith(notes: notes.trim()));
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'supplier.tx.notes',
      entityType: 'supplier_tx',
      entityId: transactionId,
      oldValue: {'notes': found.notes},
      newValue: {'notes': notes.trim()},
    );
    await _sync.maybeSyncAfterLocalWrite();
  }

  Future<void> postCorrection({
    required AppSession session,
    required String supplierId,
    required bool debit,
    required Money amount,
    required String reason,
  }) async {
    if (!session.can(AppPermission.suppliersUpdate)) {
      throw const PermissionException();
    }
    if (!amount.isPositive) {
      throw const ValidationException('مبلغ التصحيح غير صالح.');
    }
    if (reason.trim().isEmpty) {
      throw const ValidationException('سبب التصحيح مطلوب للتدقيق.');
    }
    final deviceId = await _devices.deviceId();
    await _accounts.post(
      supplierId: supplierId,
      type: debit ? 'manual_debit' : 'manual_credit',
      amount: amount,
      createdBy: session.userId,
      deviceId: deviceId,
      referenceType: 'statement_correction',
      notes: reason.trim(),
      allowNegative: !debit,
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'supplier.correction',
      entityType: 'supplier',
      entityId: supplierId,
      newValue: {
        'type': debit ? 'manual_debit' : 'manual_credit',
        'amount': amount.toStorage(),
        'reason': reason.trim(),
      },
    );
    await _sync.maybeSyncAfterLocalWrite();
  }

  Future<void> reverseTransaction({
    required AppSession session,
    required String transactionId,
    required String reason,
  }) async {
    if (!session.can(AppPermission.suppliersUpdate) &&
        !session.can(AppPermission.purchasesCancel)) {
      throw const PermissionException();
    }
    if (reason.trim().isEmpty) {
      throw const ValidationException('سبب العكس مطلوب.');
    }
    final txs = await _store.listSupplierTx();
    SupplierAccountTransaction? found;
    for (final tx in txs) {
      if (tx.id == transactionId) found = tx;
    }
    if (found == null) {
      throw const ValidationException('الحركة غير موجودة.');
    }
    const reversible = {
      'payment',
      'receipt',
      'manual_debit',
      'manual_credit',
    };
    if (!reversible.contains(found.type)) {
      throw const ValidationException(
        'لا يُعكس قيد الفاتورة من الكشف. استخدم إلغاء الفاتورة أو المرتجع أو تعديل البنود.',
      );
    }
    final already = txs.any(
      (tx) =>
          tx.referenceType == 'tx_reversal' && tx.referenceId == found!.id,
    );
    if (already) {
      throw const ValidationException('تم عكس هذه الحركة مسبقاً.');
    }
    final reverseType = switch (found.type) {
      'payment' => 'payment_cancel',
      'receipt' => 'manual_debit',
      'manual_debit' => 'manual_credit',
      'manual_credit' => 'manual_debit',
      _ => found.type,
    };
    final unsigned = Money.parse(found.amount);
    final amount = unsigned.isNegative ? -unsigned : unsigned;
    final deviceId = await _devices.deviceId();
    await _accounts.post(
      supplierId: found.supplierId,
      type: reverseType,
      amount: amount,
      createdBy: session.userId,
      deviceId: deviceId,
      referenceType: 'tx_reversal',
      referenceId: found.id,
      notes: reason.trim(),
      allowNegative: true,
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'supplier.tx.reverse',
      entityType: 'supplier_tx',
      entityId: transactionId,
      oldValue: {'type': found.type, 'amount': found.amount},
      newValue: {'reason': reason.trim()},
    );
    await _sync.maybeSyncAfterLocalWrite();
  }

  Future<SupplierAging> aging(String supplierId) async {
    final purchases = await _store.listPurchases(supplierId: supplierId);
    final now = EgyptTime.nowUtc();
    var d0 = Money.zero();
    var d30 = Money.zero();
    var d60 = Money.zero();
    var d90 = Money.zero();
    for (final purchase in purchases) {
      if (purchase.status == 'cancelled' || purchase.isDeleted) continue;
      if (purchase.status != 'completed' &&
          purchase.status != 'partial') {
        continue;
      }
      final remaining = Money.parse(purchase.remainingAmount);
      if (!remaining.isPositive) continue;
      final days = now.difference(purchase.purchasedAt.toUtc()).inDays;
      if (days <= 30) {
        d0 += remaining;
      } else if (days <= 60) {
        d30 += remaining;
      } else if (days <= 90) {
        d60 += remaining;
      } else {
        d90 += remaining;
      }
    }
    return SupplierAging(d0to30: d0, d31to60: d30, d61to90: d60, over90: d90);
  }
}

class SupplierTotals {
  const SupplierTotals({
    required this.purchases,
    required this.payments,
    required this.outstanding,
  });

  final Money purchases;
  final Money payments;
  final Money outstanding;
}

class SupplierAging {
  const SupplierAging({
    required this.d0to30,
    required this.d31to60,
    required this.d61to90,
    required this.over90,
  });

  final Money d0to30;
  final Money d31to60;
  final Money d61to90;
  final Money over90;
}

class SupplierListEntry {
  const SupplierListEntry({required this.supplier, required this.totals});

  final Supplier supplier;
  final SupplierTotals totals;

  static bool isActiveSupplier(Supplier supplier) {
    if (supplier.isDeleted) return false;
    if (supplier.status == 'closed') return false;
    return supplier.isActive;
  }

  String get statusLabel => switch (supplier.status) {
    'suspended' => 'معلق',
    'closed' => 'مغلق',
    _ => supplier.isActive ? 'نشط' : 'مغلق',
  };

  bool get isActive => isActiveSupplier(supplier);
}

class SupplierDeleteInspection {
  const SupplierDeleteInspection({
    required this.canDelete,
    required this.blockers,
    required this.activePurchases,
    required this.archivedPurchases,
    required this.balance,
  });

  final bool canDelete;
  final List<String> blockers;
  final int activePurchases;
  final int archivedPurchases;
  final Money balance;
}

class SupplierPortfolioSummary {
  const SupplierPortfolioSummary({
    required this.totalOutstanding,
    required this.totalPayments,
    required this.activeSuppliers,
  });

  final Money totalOutstanding;
  final Money totalPayments;
  final int activeSuppliers;
}
