/// Decimal quantity with scale 3 (supports 250 g as 0.250 kg when stored in kg,
/// or 250.000 pieces). Never IEEE double.
class Quantity implements Comparable<Quantity> {
  static const int scale = 3;
  final BigInt milli;

  const Quantity._(this.milli);

  factory Quantity.zero() => Quantity._(BigInt.zero);

  factory Quantity.fromMilli(BigInt milli) => Quantity._(milli);

  factory Quantity.parse(String raw) {
    final value = raw.trim().replaceAll(',', '').replaceAll('٬', '');
    if (value.isEmpty) {
      throw const FormatException('الكمية فارغة.');
    }
    final negative = value.startsWith('-');
    final unsigned = negative ? value.substring(1) : value;
    final parts = unsigned.split('.');
    if (parts.length > 2) {
      throw FormatException('تنسيق الكمية غير صالح: $raw');
    }
    final whole = parts[0].isEmpty ? '0' : parts[0];
    if (!_digits.hasMatch(whole) ||
        (parts.length == 2 &&
            parts[1].isNotEmpty &&
            !_digits.hasMatch(parts[1]))) {
      throw FormatException('تنسيق الكمية غير صالح: $raw');
    }
    final fraction = parts.length == 1 ? '' : parts[1];
    if (fraction.length > scale) {
      throw FormatException('الكمية تتجاوز $scale خانات عشرية: $raw');
    }
    final padded = fraction.padRight(scale, '0');
    final units =
        BigInt.parse(whole) * BigInt.from(1000) +
        BigInt.parse(padded.isEmpty ? '0' : padded);
    return Quantity._(negative ? -units : units);
  }

  static final _digits = RegExp(r'^\d+$');

  bool get isZero => milli == BigInt.zero;
  bool get isNegative => milli < BigInt.zero;
  bool get isPositive => milli > BigInt.zero;

  Quantity operator +(Quantity other) => Quantity._(milli + other.milli);
  Quantity operator -(Quantity other) => Quantity._(milli - other.milli);
  Quantity operator -() => Quantity._(-milli);

  /// Scale-preserving multiply: `100 packages * 250 ml = 25000 ml`.
  Quantity operator *(Quantity other) =>
      Quantity._((milli * other.milli) ~/ BigInt.from(1000));

  String toDisplay() {
    final stored = toStorage();
    if (stored.endsWith('.000')) {
      return stored.substring(0, stored.length - 4);
    }
    return stored.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  int compareTo(Quantity other) => milli.compareTo(other.milli);

  bool operator <(Quantity other) => compareTo(other) < 0;
  bool operator <=(Quantity other) => compareTo(other) <= 0;
  bool operator >(Quantity other) => compareTo(other) > 0;
  bool operator >=(Quantity other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is Quantity && other.milli == milli;

  @override
  int get hashCode => milli.hashCode;

  String toStorage() {
    final negative = milli < BigInt.zero;
    final abs = milli.abs();
    final whole = abs ~/ BigInt.from(1000);
    final frac = (abs % BigInt.from(1000)).toString().padLeft(scale, '0');
    return '${negative ? '-' : ''}$whole.$frac';
  }

  @override
  String toString() => toStorage();
}
