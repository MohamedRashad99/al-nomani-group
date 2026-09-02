import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Canonical Africa/Cairo clock for business timestamps and display.
abstract final class EgyptTime {
  static var _ready = false;
  static late tz.Location _cairo;

  static Future<void> initialize() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    _cairo = tz.getLocation('Africa/Cairo');
    _ready = true;
  }

  static void ensureInitialized() {
    if (_ready) return;
    tz_data.initializeTimeZones();
    _cairo = tz.getLocation('Africa/Cairo');
    _ready = true;
  }

  /// Persisted value: always UTC.
  static DateTime nowUtc() => DateTime.now().toUtc();

  static tz.TZDateTime toCairo(DateTime utc) {
    ensureInitialized();
    return tz.TZDateTime.from(utc.toUtc(), _cairo);
  }

  static String formatDate(DateTime utc) {
    final cairo = toCairo(utc);
    return '${_two(cairo.day)}/${_two(cairo.month)}/${cairo.year}';
  }

  static String formatTime(DateTime utc) {
    final cairo = toCairo(utc);
    final hour = cairo.hour;
    final minute = cairo.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '${hour12.toString().padLeft(2, '0')}:${_two(minute)} $period';
  }

  static String formatDateTime(DateTime utc) =>
      '${formatDate(utc)} - ${formatTime(utc)}';

  /// Build stamp label in Cairo, e.g. `v1:030926:14:20:05`.
  static String buildLabel([DateTime? utcNow]) {
    final cairo = toCairo(utcNow ?? nowUtc());
    return 'v1:${_two(cairo.day)}${_two(cairo.month)}${_two(cairo.year % 100)}:'
        '${_two(cairo.hour)}:${_two(cairo.minute)}:${_two(cairo.second)}';
  }

  /// Start of the Cairo calendar day containing [anchorUtc], as UTC.
  static DateTime startOfDayCairo(DateTime anchorUtc) {
    ensureInitialized();
    final cairo = toCairo(anchorUtc);
    return tz.TZDateTime(_cairo, cairo.year, cairo.month, cairo.day).toUtc();
  }

  /// Exclusive end of the Cairo calendar day containing [anchorUtc], as UTC.
  static DateTime endOfDayCairo(DateTime anchorUtc) {
    return startOfDayCairo(anchorUtc).add(const Duration(days: 1));
  }

  static DateTime startOfTodayCairo() => startOfDayCairo(nowUtc());

  static String _two(int value) => value.toString().padLeft(2, '0');
}
