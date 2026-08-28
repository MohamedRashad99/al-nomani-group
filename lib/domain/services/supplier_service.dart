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
    final now = DateTime.now().toUtc();
    final deviceId = await _devices.deviceId();
    final supplierId = id ?? newId();
    final existing = id == null ? null : await _store.getSupplier(id);
    final nextLink = linkedCustomerId ?? existing?.linkedCustomerId;
    final supplier = Supplier(
      id: supplierId,
      name: name.trim(),
      phone: phone,
      address: address,
      area: area,
      notes: notes,
      linkedCustomerId: nextLink?.trim().isEmpty == true ? null : nextLink,
      isActive: isActive,
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
            updatedAt: DateTime.now().toUtc(),
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
          updatedAt: DateTime.now().toUtc(),
          isDeleted: next.isDeleted,
        ),
      );
    }
  }

  Future<void> delete({
    required AppSession session,
    required String id,
  }) async {
    if (!session.can(AppPermission.suppliersDelete)) {
      throw const PermissionException();
    }
    final purchases = await _store.listPurchases(supplierId: id);
    final account = await _store.getAccountBySupplier(id);
    if (purchases.isNotEmpty ||
        (account != null && !Money.parse(account.cachedBalance).isZero)) {
      throw const ValidationException(
        'لا يمكن حذف المورد لوجود مشتريات أو رصيد مستحق.',
      );
    }
    await _store.deleteSupplier(id);
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
    await _sync.maybeSyncAfterLocalWrite();
  }

  Future<SupplierAging> aging(String supplierId) async {
    final purchases = await _store.listPurchases(supplierId: supplierId);
    final now = DateTime.now().toUtc();
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
