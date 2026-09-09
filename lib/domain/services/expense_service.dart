import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../../core/errors/app_exception.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../cairo_date_range.dart';
import '../entities/erp_models.dart';
import '../session.dart';
import 'audit_service.dart';

class ExpenseSummary {
  const ExpenseSummary({required this.count, required this.total});

  final int count;
  final Money total;
}

/// Future-facing helpers. Existing dashboard/report profit numbers stay unchanged.
abstract final class ProfitMath {
  static Money netProfit({required Money grossProfit, required Money expenses}) {
    return grossProfit - expenses;
  }
}

class ExpenseService {
  ExpenseService({
    required ErpStore store,
    required DeviceIdStore devices,
    required AuditService audit,
  }) : _store = store,
       _devices = devices,
       _audit = audit;

  final ErpStore _store;
  final DeviceIdStore _devices;
  final AuditService _audit;

  Stream<List<Expense>> watch({CairoDateRange? range, String query = ''}) {
    return _store.watchExpenses().map((items) => _filter(items, range, query));
  }

  List<Expense> _filter(
    List<Expense> items,
    CairoDateRange? range,
    String query,
  ) {
    final q = query.trim();
    return [
      for (final item in items)
        if ((range == null || range.includes(item.occurredAt)) &&
            (q.isEmpty ||
                item.note?.contains(q) == true ||
                ExpenseCategory.byCode(item.category).label.contains(q)))
          item,
    ];
  }

  ExpenseSummary summarize(List<Expense> items) {
    var total = Money.zero();
    for (final item in items) {
      try {
        total += Money.parse(item.amount);
      } catch (_) {}
    }
    return ExpenseSummary(count: items.length, total: total);
  }

  Future<String> upsert({
    required AppSession session,
    String? id,
    required Money amount,
    required String category,
    String? note,
    required DateTime occurredAt,
  }) async {
    final creating = id == null;
    if (creating && !session.can(AppPermission.expensesCreate)) {
      throw const PermissionException();
    }
    if (!creating && !session.can(AppPermission.expensesUpdate)) {
      throw const PermissionException();
    }
    if (!amount.isPositive) {
      throw const ValidationException('المبلغ غير صالح.');
    }
    final existing = id == null ? null : await _store.getExpense(id);
    if (!creating && (existing == null || existing.isDeleted)) {
      throw const ValidationException('المصروف غير موجود.');
    }
    final now = EgyptTime.nowUtc();
    final deviceId = await _devices.deviceId();
    final expenseId = id ?? newId();
    final expense = Expense(
      id: expenseId,
      amount: amount.toStorage(),
      category: ExpenseCategory.byCode(category).code,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      occurredAt: occurredAt.toUtc(),
      createdBy: existing?.createdBy ?? session.userId,
      version: (existing?.version ?? 0) + 1,
      deviceId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.putExpense(expense);
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: creating ? 'expense.create' : 'expense.update',
      entityType: 'expense',
      entityId: expenseId,
    );
    return expenseId;
  }

  Future<void> delete({
    required AppSession session,
    required String id,
  }) async {
    if (!session.can(AppPermission.expensesDelete)) {
      throw const PermissionException();
    }
    final existing = await _store.getExpense(id);
    if (existing == null || existing.isDeleted) {
      throw const ValidationException('المصروف غير موجود.');
    }
    final now = EgyptTime.nowUtc();
    final deviceId = await _devices.deviceId();
    await _store.putExpense(
      Expense(
        id: existing.id,
        amount: existing.amount,
        category: existing.category,
        note: existing.note,
        occurredAt: existing.occurredAt,
        createdBy: existing.createdBy,
        version: existing.version + 1,
        deviceId: deviceId,
        createdAt: existing.createdAt,
        updatedAt: now,
        isDeleted: true,
      ),
    );
    await _audit.write(
      userId: session.userId,
      deviceId: deviceId,
      action: 'expense.delete',
      entityType: 'expense',
      entityId: id,
    );
  }
}
