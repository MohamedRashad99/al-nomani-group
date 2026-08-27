import 'entities/erp_models.dart';

/// Single source of truth for operational vs historical records.
///
/// Cancelled and deleted documents stay in storage for audit; they must not
/// drive KPIs, deletion blockers, or report totals.
abstract final class OperationalStatus {
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static bool isCompleted(String status) => status == completed;

  static bool isCancelled(String status) => status == cancelled;

  static bool isActive({
    required String status,
    bool isDeleted = false,
  }) =>
      !isDeleted && status == completed;

  static bool isActiveSale(Sale sale) =>
      isActive(status: sale.status, isDeleted: sale.isDeleted);

  static bool isActivePurchase(Purchase purchase) =>
      isActive(status: purchase.status, isDeleted: purchase.isDeleted);

  static bool isActiveCollection(Collection collection) =>
      isActive(status: collection.status, isDeleted: collection.isDeleted);
}
