import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';

class AccountService {
  AccountService(this._store);
  final ErpStore _store;

  Future<CustomerAccount> requireAccount(String customerId) async {
    final account = await _store.getAccountByCustomer(customerId);
    if (account == null) {
      throw const ValidationException('حساب العميل غير موجود.');
    }
    return account;
  }

  Future<void> post({
    required String customerId,
    required String type,
    required Money amount,
    required String createdBy,
    required String deviceId,
    String? referenceType,
    String? referenceId,
    String? notes,
    bool allowNegative = false,
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
    if (!allowNegative && current + signed < Money.zero()) {
      throw const ValidationException(
        'لا يمكن أن يصبح رصيد العميل سالباً من هذه الحركة.',
      );
    }
    final next = current + signed;
    final now = EgyptTime.nowUtc();
    final txId = newId();
    await _store.putAccount(
      account.copyWith(
        cachedBalance: next.toStorage(),
        version: account.version + 1,
        updatedAt: now,
        deviceId: deviceId,
      ),
    );
    await _store.putAccountTx(
      CustomerAccountTransaction(
        id: txId,
        accountId: account.id,
        customerId: customerId,
        type: type,
        amount: signed.toStorage(),
        runningBalance: next.toStorage(),
        referenceType: referenceType,
        referenceId: referenceId,
        notes: notes,
        createdBy: createdBy,
        deviceId: deviceId,
        createdAt: now,
      ),
    );
  }
}
