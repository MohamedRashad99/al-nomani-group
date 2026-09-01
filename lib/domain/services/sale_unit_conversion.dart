import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../entities/erp_models.dart';
import '../models/sale_unit.dart';
import 'inventory_measure.dart';

class SaleQuantityResult {
  const SaleQuantityResult({this.breakdown, this.error});

  final SaleQuantityBreakdown? breakdown;
  final String? error;
}

/// Converts typed sale quantities into package amounts for stock and pricing.
class SaleUnitConverter {
  SaleUnitConverter._({
    required this.measure,
    required this.unitPrice,
    required this.options,
  });

  final InventoryMeasure measure;
  final Money unitPrice;
  final List<SaleUnitOption> options;

  factory SaleUnitConverter.forProduct(
    Product product, {
    Money? unitPrice,
  }) {
    final measure = InventoryMeasure.fromProduct(product);
    Money price;
    try {
      price = unitPrice ?? Money.parse(product.sellingPrice);
    } catch (_) {
      price = Money.zero();
    }
    return SaleUnitConverter._(
      measure: measure,
      unitPrice: price,
      options: buildSaleUnitOptions(measure),
    );
  }

  bool get hasSubUnits => options.any((option) => !option.isPackage);

  String availabilityLabel(Quantity availablePackages) {
    final packages = availablePackages.isPositive
        ? availablePackages
        : Quantity.zero();
    return 'المتوفر ${measure.formatPackages(packages)} • ${measure.formatActual(packages)}';
  }

  SaleQuantityResult evaluate({
    required SaleUnitOption option,
    required String rawInput,
    required Quantity availablePackages,
  }) {
    final Quantity input;
    try {
      input = Quantity.parse(rawInput);
    } catch (_) {
      return const SaleQuantityResult(error: 'الكمية غير صالحة.');
    }
    if (!input.isPositive) {
      return const SaleQuantityResult(error: 'الكمية غير صالحة.');
    }
    if (!measure.packageSize.isPositive) {
      return const SaleQuantityResult(error: 'حجم العبوة غير صالح.');
    }

    final baseQuantity = Quantity.fromMilli(
      (input.milli * option.baseUnitsPerUnit.milli) ~/ BigInt.from(1000),
    );
    final packageQuantity = Quantity.fromMilli(
      (baseQuantity.milli * BigInt.from(1000)) ~/ measure.packageSize.milli,
    );
    if (!packageQuantity.isPositive) {
      return const SaleQuantityResult(
        error: 'الكمية أصغر من أن تُحوَّل إلى عبوة.',
      );
    }
    if (packageQuantity > availablePackages) {
      return const SaleQuantityResult(error: 'المخزون غير كافٍ.');
    }

    final totalPrice = Money.fromMinorUnits(
      (packageQuantity.milli * unitPrice.minorUnits) ~/ BigInt.from(1000),
    );

    return SaleQuantityResult(
      breakdown: SaleQuantityBreakdown(
        option: option,
        packageType: measure.packageType,
        inputQuantity: input,
        packageQuantity: packageQuantity,
        baseQuantity: baseQuantity,
        unitPrice: unitPrice,
        totalPrice: totalPrice,
      ),
    );
  }
}

/// Package option plus optional base / promoted (kg, l) sub units.
List<SaleUnitOption> buildSaleUnitOptions(InventoryMeasure measure) {
  final package = SaleUnitOption(
    kind: SaleUnitKind.package,
    label: measure.packageType,
    quantityLabel: 'الكمية بال${measure.packageType}',
    storageCode: measure.packageType,
    baseUnitsPerUnit: measure.packageSize,
  );

  if (!measure.packageSize.isPositive ||
      measure.packageSize <= Quantity.parse('1')) {
    return [package];
  }

  final base = measure.unitOfMeasure;
  final options = <SaleUnitOption>[
    package,
    SaleUnitOption(
      kind: SaleUnitKind.subUnit,
      label: base.symbol,
      quantityLabel: 'الكمية ب${_quantityNoun(base)}',
      storageCode: base.symbol,
      baseUnitsPerUnit: Quantity.parse('1'),
      unit: base,
    ),
  ];

  final promoted = _promotedUnit(base);
  if (promoted != null) {
    options.add(
      SaleUnitOption(
        kind: SaleUnitKind.subUnit,
        label: promoted.symbol,
        quantityLabel: 'الكمية ب${_quantityNoun(promoted)}',
        storageCode: promoted.symbol,
        baseUnitsPerUnit: Quantity.parse('1000'),
        unit: promoted,
      ),
    );
  }
  return options;
}

ProductUnit? _promotedUnit(ProductUnit base) => switch (base) {
      ProductUnit.gram => ProductUnit.kilogram,
      ProductUnit.milliliter => ProductUnit.liter,
      _ => null,
    };

String _quantityNoun(ProductUnit unit) => switch (unit) {
      ProductUnit.gram => 'الغرام',
      ProductUnit.kilogram => 'الكيلوغرام',
      ProductUnit.milliliter => 'المليلتر',
      ProductUnit.liter => 'اللتر',
      ProductUnit.piece => 'القطعة',
      ProductUnit.custom => unit.arabicLabel,
    };

/// Converts a quantity between related mass/volume units (g↔kg, ml↔L).
Quantity convertUnitFamily(
  Quantity quantity,
  ProductUnit from,
  ProductUnit to,
) {
  if (from == to) return quantity;
  final fromSmall = from == ProductUnit.gram || from == ProductUnit.milliliter;
  final toSmall = to == ProductUnit.gram || to == ProductUnit.milliliter;
  final sameFamily =
      ((from == ProductUnit.gram || from == ProductUnit.kilogram) &&
          (to == ProductUnit.gram || to == ProductUnit.kilogram)) ||
      ((from == ProductUnit.milliliter || from == ProductUnit.liter) &&
          (to == ProductUnit.milliliter || to == ProductUnit.liter));
  if (!sameFamily) {
    throw FormatException(
      'تعذر تحويل الوحدة من ${from.symbol} إلى ${to.symbol}.',
    );
  }
  final asSmallest =
      fromSmall ? quantity.milli : quantity.milli * BigInt.from(1000);
  final resultMilli =
      toSmall ? asSmallest : asSmallest ~/ BigInt.from(1000);
  return Quantity.fromMilli(resultMilli);
}
