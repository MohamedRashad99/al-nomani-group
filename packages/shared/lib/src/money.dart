/// Fixed-scale money. Never uses IEEE floating point.
///
/// Scale is 3 (thousandths) so Omani rial baisa and similar currencies stay exact.
/// Storage: decimal string (`"12.500"`) or integer minor units (`12500`).
class Money implements Comparable<Money> {
  static const int scale = 3;
  static const String currencyCode = 'OMR';
  static const String currencySymbol = 'ر.ع.';

  final BigInt minorUnits;

  const Money._(this.minorUnits);

  factory Money.zero() => Money._(BigInt.zero);

  factory Money.fromMinorUnits(BigInt units) => Money._(units);

  factory Money.fromInt(int major) =>
      Money._(BigInt.from(major) * BigInt.from(1000));

  /// Parses a decimal string such as `"1000"`, `"400.000"`, `"12.5"`.
  factory Money.parse(String raw) {
    final value = raw.trim().replaceAll(',', '').replaceAll('٬', '');
    if (value.isEmpty) {
      throw const FormatException('المبلغ فارغ.');
    }
    final negative = value.startsWith('-');
    final unsigned = negative ? value.substring(1) : value;
    final parts = unsigned.split('.');
    if (parts.length > 2) {
      throw FormatException('تنسيق المبلغ غير صالح: $raw');
    }
    final whole = parts[0].isEmpty ? '0' : parts[0];
    if (!_digits.hasMatch(whole) ||
        (parts.length == 2 &&
            parts[1].isNotEmpty &&
            !_digits.hasMatch(parts[1]))) {
      throw FormatException('تنسيق المبلغ غير صالح: $raw');
    }
    final fraction = parts.length == 1 ? '' : parts[1];
    if (fraction.length > scale) {
      throw FormatException('المبلغ يتجاوز $scale خانات عشرية: $raw');
    }
    final padded = fraction.padRight(scale, '0');
    final units =
        BigInt.parse(whole) * BigInt.from(1000) +
        BigInt.parse(padded.isEmpty ? '0' : padded);
    return Money._(negative ? -units : units);
  }

  static final _digits = RegExp(r'^\d+$');

  bool get isZero => minorUnits == BigInt.zero;
  bool get isNegative => minorUnits < BigInt.zero;
  bool get isPositive => minorUnits > BigInt.zero;

  Money operator +(Money other) => Money._(minorUnits + other.minorUnits);
  Money operator -(Money other) => Money._(minorUnits - other.minorUnits);
  Money operator -() => Money._(-minorUnits);

  Money min(Money other) => compareTo(other) <= 0 ? this : other;
  Money max(Money other) => compareTo(other) >= 0 ? this : other;

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  /// Canonical storage / wire format, always 3 decimal places.
  String toStorage() {
    final negative = minorUnits < BigInt.zero;
    final abs = minorUnits.abs();
    final whole = abs ~/ BigInt.from(1000);
    final frac = (abs % BigInt.from(1000)).toString().padLeft(scale, '0');
    return '${negative ? '-' : ''}$whole.$frac';
  }

  String toDisplay() => toStorage();

  @override
  String toString() => toStorage();
}
