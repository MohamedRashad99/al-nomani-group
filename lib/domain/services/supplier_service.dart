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
    final supplier = Supplier(
      id: supplierId,
      name: name.trim(),
      phone: phone,
      address: address,
      area: area,
      notes: notes,
      isActive: isActive,
      version: (existing?.version ?? 0) + 1,
      deviceId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.putSupplier(supplier);
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
      if (tx.type == 'payment') {
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
