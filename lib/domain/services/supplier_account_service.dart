import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';

class SupplierAccountService {
  SupplierAccountService(this._store);
  final ErpStore _store;

  Future<SupplierAccount> requireAccount(String supplierId) async {
    final account = await _store.getAccountBySupplier(supplierId);
    if (account == null) {
      throw const ValidationException('حساب المورد غير موجود.');
    }
    return account;
  }

  Future<void> post({
    required String supplierId,
    required String type,
    required Money amount,
    required String createdBy,
    required String deviceId,
    String? referenceType,
    String? referenceId,
    String? notes,
    bool allowNegative = false,
  }) async {
    final account = await requireAccount(supplierId);
    final current = Money.parse(account.cachedBalance);
    final signed = switch (type) {
      'purchase' => amount,
      'payment' => -amount,
      'purchase_cancel' => -amount,
      'payment_cancel' => amount,
      'purchase_return' => -amount,
      'receipt' => -amount,
      'manual_debit' => amount,
      'manual_credit' => -amount,
      _ => throw ValidationException('نوع حركة حساب المورد غير معروف: $type'),
    };
    if (!allowNegative && current + signed < Money.zero()) {
      throw const ValidationException(
        'لا يمكن أن يصبح رصيد المورد سالباً من هذه الحركة.',
      );
    }
    final next = current + signed;
    final now = EgyptTime.nowUtc();
    await _store.putSupplierAccount(
      account.copyWith(
        cachedBalance: next.toStorage(),
        version: account.version + 1,
        updatedAt: now,
        deviceId: deviceId,
      ),
    );
    await _store.putSupplierTx(
      SupplierAccountTransaction(
        id: newId(),
        accountId: account.id,
        supplierId: supplierId,
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
