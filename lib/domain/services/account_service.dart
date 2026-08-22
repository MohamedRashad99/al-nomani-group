import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_queue_repository.dart';

class AccountService {
  AccountService(this._db, this._queue);
  final AppDatabase _db;
  final SyncQueueRepository _queue;

  Future<CustomerAccount> requireAccount(String customerId) async {
    final account = await (_db.select(
      _db.customerAccounts,
    )..where((t) => t.customerId.equals(customerId))).getSingleOrNull();
    if (account == null) {
      throw const ValidationException('حساب العميل غير موجود.');
    }
    return account;
  }

  /// Must run inside an existing transaction.
  Future<void> post({
    required String customerId,
    required String type,
    required Money amount,
    required String createdBy,
    required String deviceId,
    String? referenceType,
    String? referenceId,
    String? notes,
    bool enqueue = true,
  }) async {
    final account = await requireAccount(customerId);
    final current = Money.parse(account.cachedBalance);
    final signed = switch (type) {
      'sale' => amount,
      'payment' => -amount,
      'sale_cancel' => -amount,
      'payment_cancel' => amount,
      'opening_balance' => amount,
      'manual_debit' => amount,
      'manual_credit' => -amount,
      _ => throw ValidationException('نوع حركة الحساب غير معروف: $type'),
    };
    if (current + signed < Money.zero()) {
      throw const ValidationException(
        'لا يمكن أن يصبح رصيد العميل سالباً من هذه الحركة.',
      );
    }
    final next = current + signed;
    final now = DateTime.now().toUtc();
    final txId = newId();

    await (_db.update(
      _db.customerAccounts,
    )..where((t) => t.id.equals(account.id))).write(
      CustomerAccountsCompanion(
        cachedBalance: Value(next.toStorage()),
        version: Value(account.version + 1),
        updatedAt: Value(now),
        deviceId: Value(deviceId),
      ),
    );

    final payload = {
      'id': txId,
      'account_id': account.id,
      'customer_id': customerId,
      'type': type,
      'amount': signed.toStorage(),
      'running_balance': next.toStorage(),
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
      'created_by': createdBy,
      'device_id': deviceId,
      'created_at': now.toIso8601String(),
    };

    await _db
        .into(_db.customerAccountTransactions)
        .insert(
          CustomerAccountTransactionsCompanion.insert(
            id: txId,
            accountId: account.id,
            customerId: customerId,
            type: type,
            amount: signed.toStorage(),
            runningBalance: next.toStorage(),
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            notes: Value(notes),
            createdBy: createdBy,
            deviceId: deviceId,
            createdAt: now,
          ),
        );

    if (enqueue) {
      await _queue.enqueue(
        entityType: SyncEntityType.customerAccountTransaction,
        entityId: txId,
        operation: SyncOperationType.create,
        payload: payload,
        operationId: txId,
      );
    }
  }
}
