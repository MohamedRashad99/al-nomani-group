import 'package:al_nomani_shared/al_nomani_shared.dart';

import 'sale_unit.dart';

class SaleLineDraft {
  final String productId;
  final Quantity quantity;
  final String unit;
  final Money unitPrice;
  final SaleUnitKind selectedUnit;
  final Quantity inputQuantity;
  final String inputUnit;
  final Quantity convertedPackageQuantity;

  const SaleLineDraft({
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.selectedUnit = SaleUnitKind.package,
    Quantity? inputQuantity,
    String? inputUnit,
    Quantity? convertedPackageQuantity,
  })  : inputQuantity = inputQuantity ?? quantity,
        inputUnit = inputUnit ?? unit,
        convertedPackageQuantity = convertedPackageQuantity ?? quantity;

  factory SaleLineDraft.fromBreakdown({
    required String productId,
    required String unit,
    required SaleQuantityBreakdown breakdown,
  }) {
    return SaleLineDraft(
      productId: productId,
      quantity: breakdown.packageQuantity,
      unit: unit,
      unitPrice: breakdown.unitPrice,
      selectedUnit: breakdown.selectedUnit,
      inputQuantity: breakdown.inputQuantity,
      inputUnit: breakdown.inputUnit,
      convertedPackageQuantity: breakdown.packageQuantity,
    );
  }

  String get quantityLabel =>
      '${inputQuantity.toDisplay()} $inputUnit';

  Money get lineTotal {
    final units = convertedPackageQuantity.milli * unitPrice.minorUnits;
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
