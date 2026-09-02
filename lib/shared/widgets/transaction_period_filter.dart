import 'package:al_nomani_shared/al_nomani_shared.dart';

/// Preset transaction date windows using Cairo calendar days.
enum TransactionPeriod {
  all,
  today,
  week,
  month,
}

abstract final class TransactionPeriodFilter {
  static DateTime? startUtc(TransactionPeriod period) {
    final now = EgyptTime.nowUtc();
    return switch (period) {
      TransactionPeriod.all => null,
      TransactionPeriod.today => EgyptTime.startOfTodayCairo(),
      TransactionPeriod.week =>
        EgyptTime.startOfDayCairo(now.subtract(const Duration(days: 7))),
      TransactionPeriod.month => _startOfMonthCairo(now),
    };
  }

  static bool includes(DateTime instantUtc, TransactionPeriod period) {
    final from = startUtc(period);
    if (from == null) return true;
    return !instantUtc.toUtc().isBefore(from);
  }

  static DateTime _startOfMonthCairo(DateTime anchorUtc) {
    final cairo = EgyptTime.toCairo(anchorUtc);
    return EgyptTime.startOfDayCairo(
      DateTime.utc(cairo.year, cairo.month, 1),
    );
  }

  static String label(TransactionPeriod period) => switch (period) {
    TransactionPeriod.all => 'كل التواريخ',
    TransactionPeriod.today => 'اليوم',
    TransactionPeriod.week => 'آخر ٧ أيام',
    TransactionPeriod.month => 'هذا الشهر',
  };
}
