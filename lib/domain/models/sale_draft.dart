import 'package:al_nomani_shared/al_nomani_shared.dart';

class SaleLineDraft {
  final String productId;
  final Quantity quantity;
  final String unit;
  final Money unitPrice;

  const SaleLineDraft({
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  Money get lineTotal {
    final units = quantity.milli * unitPrice.minorUnits;
    return Money.fromMinorUnits(units ~/ BigInt.from(1000));
  }
}

class SaleDraft {
  final String customerId;
  final List<SaleLineDraft> lines;
  final Money paidAmount;
  final String? notes;

  const SaleDraft({
    required this.customerId,
    required this.lines,
    required this.paidAmount,
    this.notes,
  });

  Money get subtotal =>
      lines.fold(Money.zero(), (sum, line) => sum + line.lineTotal);

  Money get remaining {
    final rem = subtotal - paidAmount;
    return rem.isNegative ? Money.zero() : rem;
  }
}
