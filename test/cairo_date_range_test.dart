import 'package:al_nomani_group/domain/cairo_date_range.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(EgyptTime.ensureInitialized);

  test('custom range includes the entire end date in Egypt time', () {
    final range = CairoDateRange.custom(
      startDay: DateTime.utc(2026, 9, 1),
      endDay: DateTime.utc(2026, 9, 7),
    );
    expect(range.includes(EgyptTime.startOfDayCairo(DateTime.utc(2026, 9, 1))), isTrue);
    expect(
      range.includes(
        EgyptTime.endOfDayCairo(DateTime.utc(2026, 9, 7)).subtract(
          const Duration(minutes: 1),
        ),
      ),
      isTrue,
    );
    expect(
      range.includes(EgyptTime.endOfDayCairo(DateTime.utc(2026, 9, 7))),
      isFalse,
    );
  });

  test('same start and end day is valid', () {
    final range = CairoDateRange.custom(
      startDay: DateTime.utc(2026, 9, 3),
      endDay: DateTime.utc(2026, 9, 3),
    );
    expect(range.includes(EgyptTime.startOfDayCairo(DateTime.utc(2026, 9, 3))), isTrue);
    expect(
      range.includes(EgyptTime.endOfDayCairo(DateTime.utc(2026, 9, 3))),
      isFalse,
    );
  });

  test('invalid custom range is rejected', () {
    expect(
      () => CairoDateRange.custom(
        startDay: DateTime.utc(2026, 9, 7),
        endDay: DateTime.utc(2026, 9, 1),
      ),
      throwsFormatException,
    );
  });

  test('yesterday is a closed Cairo day', () {
    final now = DateTime.utc(2026, 9, 9, 12);
    final range = CairoDateRange.preset(ReportPeriod.yesterday, now);
    expect(range.includes(EgyptTime.startOfDayCairo(DateTime.utc(2026, 9, 8))), isTrue);
    expect(range.includes(EgyptTime.startOfDayCairo(DateTime.utc(2026, 9, 9))), isFalse);
  });
}
