import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(EgyptTime.ensureInitialized);

  group('EgyptTime', () {
    test('formatDate and formatTime use Africa/Cairo', () {
      // 2026-09-01 12:45 UTC = 15:45 Cairo (UTC+3, no DST in Sep).
      final utc = DateTime.utc(2026, 9, 1, 12, 45);
      expect(EgyptTime.formatDate(utc), '01/09/2026');
      expect(EgyptTime.formatTime(utc), '03:45 PM');
      expect(EgyptTime.formatDateTime(utc), '01/09/2026 - 03:45 PM');
    });

    test('startOfDayCairo differs from device-local midnight', () {
      final utc = DateTime.utc(2026, 9, 1, 22, 0);
      final start = EgyptTime.startOfDayCairo(utc);
      expect(start, DateTime.utc(2026, 9, 1, 21));
      expect(EgyptTime.formatDate(utc), '02/09/2026');
    });

    test('nowUtc returns UTC instant', () {
      final now = EgyptTime.nowUtc();
      expect(now.isUtc, isTrue);
    });

    test('buildLabel matches Cairo wall clock parts', () {
      final utc = DateTime.utc(2026, 9, 3, 9, 5, 7);
      expect(EgyptTime.buildLabel(utc), 'v1:030926:12:05:07');
    });
  });
}
