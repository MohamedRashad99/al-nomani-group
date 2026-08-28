import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../../data/sync/sync_engine.dart';
import '../entities/erp_models.dart';
import '../session.dart';
import 'account_service.dart';
import 'audit_service.dart';
import 'collection_service.dart';

class OutstandingRow {
  const OutstandingRow({required this.customer, required this.balance});

  final Customer customer;
  final Money balance;
}

class OutstandingService {
  OutstandingService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AccountService accounts,
    required AuditService audit,
    required SyncEngine sync,
    required CollectionService collections,
  }) : _store = store,
       _devices = devices,
       _accounts = accounts,
       _audit = audit,
       _sync = sync,
       _collections = collections;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AccountService _accounts;
  final AuditService _audit;
  final SyncEngine _sync;
  final CollectionService _collections;

  Stream<List<OutstandingRow>> watch() async* {
    yield await list();
    await for (final _ in _store.watchChanges()) {
      yield await list();
    }
  }

  Future<List<OutstandingRow>> list() async {
    final customersFuture = _store.listCustomers();
    final accountsFuture = _store.listAccounts();
    final customers = await customersFuture;
    final accounts = await accountsFuture;
    final balances = {
      for (final account in accounts)
        account.customerId: Money.parse(account.cachedBalance),
    };
    return [
      for (final customer in customers)
        OutstandingRow(
          customer: customer,
          balance: balances[customer.id] ?? Money.zero(),
        ),
    ];
  }

  Future<List<OutstandingRow>> listDue() async {
    return [
      for (final row in await list())
        if (row.balance.isPositive) row,
    ];
  }

  Stream<List<OutstandingRow>> watchDue() {
    return watch().map(
      (rows) => [
        for (final row in rows)
          if (row.balance.isPositive) row,
      ],
    );
  }

  Money totalDue(List<OutstandingRow> rows) {
    return rows.fold(Money.zero(), (sum, row) => sum + row.balance);
  }

  Stream<({CustomerAccount? account, List<CustomerAccountTransaction> txs})>
  watchStatement(String customerId) async* {
    Future<({CustomerAccount? account, List<CustomerAccountTransaction> txs})>
    load() async {
      final account = await _store.getAccountByCustomer(customerId);
      final txs = await _store.listAccountTx(customerId: customerId);
      return (account: account, txs: txs);
    }

    yield await load();
    await for (final _ in _store.watchChanges()) {
      yield await load();
    }
  }

  Future<Customer?> getCustomer(String id) => _store.getCustomer(id);

  Stream<Customer?> watchCustomer(String id) {
    return _store.watchCustomers().map((rows) {
      for (final row in rows) {
        if (row.id == id) return row;
      }
      return null;
    });
  }

  Future<void> add({
    required AppSession session,
    required String customerId,
    required Money amount,
    required String notes,
  }) {
    return _post(
      session: session,
      customerId: customerId,
      amount: amount,
      notes: notes,
      type: 'manual_debit',
      action: 'outstanding.manual_debit',
    );
  }

  Future<void> collectCash({
    required AppSession session,
    required String customerId,
    required Money amount,
    String? notes,
  }) async {
    if (!session.can(AppPermission.outstandingCreate) &&
        !session.can(AppPermission.collectionsCreate)) {
      throw const PermissionException();
    }
    if (!amount.isPositive) {
      throw const ValidationException('المبلغ النقدي يجب أن يكون أكبر من صفر.');
    }
    if (session.can(AppPermission.collectionsCreate)) {
      await _collections.record(
        session: session,
        customerId: customerId,
        amount: amount,
        paymentMethod: 'cash',
        notes: (notes == null || notes.trim().isEmpty)
            ? 'تحصيل نقدي من المبالغ الآجلة'
            : notes.trim(),
      );
    } else {
      await _post(
        session: session.copyWith(
          permissions: {
            ...session.permissions,
            AppPermission.outstandingCreate,
          },
        ),
        customerId: customerId,
        amount: amount,
        notes: (notes == null || notes.trim().isEmpty)
            ? 'تحصيل نقدي من المبالغ الآجلة'
            : notes.trim(),
        type: 'payment',
        action: 'outstanding.cash_collection',
      );
      return;
    }
    await _sync.maybeSyncAfterLocalWrite();
  }

  Future<void> reduce({
    required AppSession session,
    required String customerId,
    required Money amount,
    required String notes,
  }) {
    return _post(
      session: session,
      customerId: customerId,
      amount: amount,
      notes: notes,
      type: 'manual_credit',
      action: 'outstanding.manual_credit',
    );
  }

  Future<void> setTarget({
    required AppSession session,
    required String customerId,
    required Money target,
    required String notes,
  }) async {
    if (target.isNegative) {
      throw const ValidationException(
        'الرصيد المستهدف لا يمكن أن يكون سالباً.',
      );
    }
    final account = await _accounts.requireAccount(customerId);
    final current = Money.parse(account.cachedBalance);
    final delta = target - current;
    if (delta.isZero) return;
    await _post(
      session: session,
      customerId: customerId,
      amount: delta.isNegative ? -delta : delta,
      notes: notes,
      type: current.isZero && delta.isPositive
          ? 'opening_balance'
          : delta.isPositive
          ? 'manual_debit'
          : 'manual_credit',
      action: 'outstanding.set_target',
    );
  }

  Future<void> _post({
    required AppSession session,
    required String customerId,
    required Money amount,
    required String notes,
    required String type,
    required String action,
  }) async {
    if (!session.can(AppPermission.outstandingCreate)) {
      throw const PermissionException();
    }
    if (!amount.isPositive) {
      throw const ValidationException('المبلغ يجب أن يكون أكبر من صفر.');
    }
    if (notes.trim().isEmpty) {
      throw const ValidationException('الملاحظات مطلوبة لتوثيق الحركة.');
    }
    final deviceId = await _devices.deviceId();
    await _accounts.post(
      customerId: customerId,
      type: type,
      amount: amount,
      createdBy: session.userId,
      deviceId: deviceId,
      referenceType: 'outstanding_adjustment',
      notes: notes.trim(),
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: action,
      entityType: 'customerAccountTransaction',
      entityId: customerId,
    );
    await _sync.maybeSyncAfterLocalWrite();
  }
}
