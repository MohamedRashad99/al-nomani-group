import 'package:al_nomani_shared/al_nomani_shared.dart';

enum ReportPeriod {
  today,
  yesterday,
  last7Days,
  lastWeek,
  thisMonth,
  lastMonth,
  custom,
}

/// Half-open Cairo calendar range: `[startUtc, endExclusiveUtc)`.
class CairoDateRange {
  const CairoDateRange({
    required this.period,
    required this.startUtc,
    required this.endExclusiveUtc,
    this.customStart,
    this.customEnd,
  });

  final ReportPeriod period;
  final DateTime startUtc;
  final DateTime endExclusiveUtc;
  final DateTime? customStart;
  final DateTime? customEnd;

  DateTime get endInclusiveUtc =>
      endExclusiveUtc.subtract(const Duration(milliseconds: 1));

  String get label => switch (period) {
    ReportPeriod.today => 'اليوم',
    ReportPeriod.yesterday => 'أمس',
    ReportPeriod.last7Days => 'آخر ٧ أيام',
    ReportPeriod.lastWeek => 'الأسبوع الماضي',
    ReportPeriod.thisMonth => 'هذا الشهر',
    ReportPeriod.lastMonth => 'الشهر الماضي',
    ReportPeriod.custom => 'فترة مخصصة',
  };

  bool includes(DateTime instantUtc) {
    final instant = instantUtc.toUtc();
    return !instant.isBefore(startUtc) && instant.isBefore(endExclusiveUtc);
  }

  static CairoDateRange preset(ReportPeriod period, [DateTime? nowUtc]) {
    if (period == ReportPeriod.custom) {
      throw ArgumentError('استخدم CairoDateRange.custom للفترة المخصصة.');
    }
    EgyptTime.ensureInitialized();
    final now = nowUtc?.toUtc() ?? EgyptTime.nowUtc();
    final cairo = EgyptTime.toCairo(now);
    switch (period) {
      case ReportPeriod.today:
        final start = EgyptTime.startOfTodayCairo();
        return CairoDateRange(
          period: period,
          startUtc: start,
          endExclusiveUtc: EgyptTime.endOfDayCairo(now),
        );
      case ReportPeriod.yesterday:
        final start = EgyptTime.startOfDayCairo(
          now.subtract(const Duration(days: 1)),
        );
        return CairoDateRange(
          period: period,
          startUtc: start,
          endExclusiveUtc: EgyptTime.startOfTodayCairo(),
        );
      case ReportPeriod.last7Days:
        return CairoDateRange(
          period: period,
          startUtc: EgyptTime.startOfDayCairo(
            now.subtract(const Duration(days: 6)),
          ),
          endExclusiveUtc: EgyptTime.endOfDayCairo(now),
        );
      case ReportPeriod.lastWeek:
        final daysSinceSaturday = cairo.weekday == DateTime.saturday
            ? 0
            : (cairo.weekday % 7) + 1;
        final thisSaturday = EgyptTime.startOfDayCairo(
          now.subtract(Duration(days: daysSinceSaturday)),
        );
        return CairoDateRange(
          period: period,
          startUtc: thisSaturday.subtract(const Duration(days: 7)),
          endExclusiveUtc: thisSaturday,
        );
      case ReportPeriod.thisMonth:
        final start = EgyptTime.startOfDayCairo(
          DateTime.utc(cairo.year, cairo.month, 1),
        );
        return CairoDateRange(
          period: period,
          startUtc: start,
          endExclusiveUtc: EgyptTime.endOfDayCairo(now),
        );
      case ReportPeriod.lastMonth:
        final thisMonthStart = EgyptTime.startOfDayCairo(
          DateTime.utc(cairo.year, cairo.month, 1),
        );
        final previous = EgyptTime.toCairo(
          thisMonthStart.subtract(const Duration(days: 1)),
        );
        return CairoDateRange(
          period: period,
          startUtc: EgyptTime.startOfDayCairo(
            DateTime.utc(previous.year, previous.month, 1),
          ),
          endExclusiveUtc: thisMonthStart,
        );
      case ReportPeriod.custom:
        throw ArgumentError('استخدم CairoDateRange.custom للفترة المخصصة.');
    }
  }

  static CairoDateRange custom({
    required DateTime startDay,
    required DateTime endDay,
  }) {
    EgyptTime.ensureInitialized();
    final start = EgyptTime.startOfDayCairo(startDay.toUtc());
    final endExclusive = EgyptTime.endOfDayCairo(endDay.toUtc());
    if (!start.isBefore(endExclusive)) {
      throw const FormatException('تاريخ البداية يجب أن يسبق تاريخ النهاية أو يساويه.');
    }
    return CairoDateRange(
      period: ReportPeriod.custom,
      startUtc: start,
      endExclusiveUtc: endExclusive,
      customStart: start,
      customEnd: EgyptTime.startOfDayCairo(endDay.toUtc()),
    );
  }
}
