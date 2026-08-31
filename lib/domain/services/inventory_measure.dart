import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../entities/erp_models.dart';

/// Quantity-aware packaging. Calculations use [packageSize], [unitOfMeasure],
/// and package [packages] only — never display labels.
class InventoryMeasure {
  const InventoryMeasure({
    required this.packages,
    required this.packageSize,
    required this.unitOfMeasure,
    required this.packageType,
    required this.minimumPackages,
    this.reorderPoint,
    this.safetyStock,
  });

  final Quantity packages;
  final Quantity packageSize;
  final ProductUnit unitOfMeasure;
  final String packageType;
  final Quantity minimumPackages;
  final Quantity? reorderPoint;
  final Quantity? safetyStock;

  factory InventoryMeasure.fromProduct(Product product) {
    final parsed = PackingParser.parse(
      product.packSize,
      fallbackUnit: product.unit,
    );
    final size =
        _qtyOrNull(product.packageSize) ?? parsed?.size ?? Quantity.parse('1');
    final uom =
        _unitOrNull(product.unitOfMeasure) ??
        parsed?.unit ??
        _unitOrNull(product.unit) ??
        ProductUnit.piece;
    final type = _nz(product.packageType) ??
        _packageTypeOrNull(product.unit) ??
        PackageTypes.bottle;
    return InventoryMeasure(
      packages: _qty(product.currentStock),
      packageSize: size.isPositive ? size : Quantity.parse('1'),
      unitOfMeasure: uom,
      packageType: type,
      minimumPackages: _qty(product.minimumStock),
      reorderPoint: _qtyOrNull(product.reorderPoint),
      safetyStock: _qtyOrNull(product.safetyStock),
    );
  }

  Quantity get actual => packages * packageSize;

  Quantity get minimumActual => minimumPackages * packageSize;

  Quantity actualOf(Quantity packageCount) => packageCount * packageSize;

  bool get isOutOfStock => !packages.isPositive;

  bool get isLowStock =>
      !isOutOfStock &&
      (packages <= minimumPackages || actual <= minimumActual);

  bool get needsReorder {
    if (isOutOfStock) return true;
    final reorder = _thresholdAsBase(reorderPoint);
    if (reorder != null && !reorder.isZero && actual <= reorder) return true;
    final safety = _thresholdAsBase(safetyStock);
    if (safety != null && !safety.isZero && actual <= safety) return true;
    return isLowStock;
  }

  Quantity? _thresholdAsBase(Quantity? threshold) {
    if (threshold == null) return null;
    final display = _preferLarger(actual, unitOfMeasure);
    if (display.unit == unitOfMeasure) return threshold;
    if (display.unit == ProductUnit.liter &&
        unitOfMeasure == ProductUnit.milliliter) {
      return Quantity.fromMilli(threshold.milli * BigInt.from(1000));
    }
    if (display.unit == ProductUnit.kilogram &&
        unitOfMeasure == ProductUnit.gram) {
      return Quantity.fromMilli(threshold.milli * BigInt.from(1000));
    }
    return threshold;
  }

  String get packagesLabel => '${packages.toDisplay()} $packageType';

  String get actualLabel => formatQuantity(actual, unitOfMeasure);

  String get remainingLabel => 'المتبقي: $actualLabel';

  String formatPackages(Quantity count) =>
      '${count.toDisplay()} $packageType';

  String formatActual(Quantity packageCount) =>
      formatQuantity(actualOf(packageCount), unitOfMeasure);

  static String formatQuantity(Quantity value, ProductUnit unit) {
    final converted = _preferLarger(value, unit);
    return '${converted.quantity.toDisplay()} ${converted.unit.symbol}';
  }

  static ({Quantity quantity, ProductUnit unit}) _preferLarger(
    Quantity value,
    ProductUnit unit,
  ) {
    if (unit == ProductUnit.milliliter &&
        value.milli.abs() >= BigInt.from(1000000)) {
      return (
        quantity: Quantity.fromMilli(value.milli ~/ BigInt.from(1000)),
        unit: ProductUnit.liter,
      );
    }
    if (unit == ProductUnit.gram &&
        value.milli.abs() >= BigInt.from(1000000)) {
      return (
        quantity: Quantity.fromMilli(value.milli ~/ BigInt.from(1000)),
        unit: ProductUnit.kilogram,
      );
    }
    return (quantity: value, unit: unit);
  }
}

class PackHint {
  const PackHint({required this.size, required this.unit, this.packageType});

  final Quantity size;
  final ProductUnit unit;
  final String? packageType;
}

abstract final class PackingParser {
  static final _pattern = RegExp(
    r'([\d]+(?:[.,]\d+)?)\s*'
    r'(ml|ملل?|مليلتر|millilit(?:er|re)s?|'
    r'l|ltr|لتر|liter|litre|liters|litres|'
    r'kg|كجم|كغ|كيلو(?:غرام|جرام)?|kilograms?|'
    r'g|جم|غرام|جرام|grams?|'
    r'pcs|قطعة|قطع|حبة|pieces?)',
    caseSensitive: false,
  );

  static PackHint? parse(String? raw, {String? fallbackUnit}) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      final unit = _unitOrNull(fallbackUnit);
      if (unit == null) return null;
      return PackHint(size: Quantity.parse('1'), unit: unit);
    }
    final match = _pattern.firstMatch(text.replaceAll('٬', '').replaceAll(',', '.'));
    if (match != null) {
      final size = Quantity.parse(match.group(1)!.replaceAll(',', '.'));
      final unit = ProductUnit.fromCode(match.group(2)!);
      return PackHint(
        size: size,
        unit: unit == ProductUnit.custom ? ProductUnit.piece : unit,
        packageType: _packageTypeOrNull(text),
      );
    }
    final asQty = _qtyOrNull(text);
    if (asQty != null) {
      return PackHint(
        size: asQty,
        unit: _unitOrNull(fallbackUnit) ?? ProductUnit.piece,
      );
    }
    final unit = _unitOrNull(text) ?? _unitOrNull(fallbackUnit);
    if (unit == null) return null;
    return PackHint(size: Quantity.parse('1'), unit: unit);
  }
}

Quantity _qty(String raw) {
  try {
    return Quantity.parse(raw.isEmpty ? '0' : raw);
  } catch (_) {
    return Quantity.zero();
  }
}

Quantity? _qtyOrNull(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  try {
    return Quantity.parse(text);
  } catch (_) {
    return null;
  }
}

ProductUnit? _unitOrNull(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final unit = ProductUnit.fromCode(text);
  return unit == ProductUnit.custom ? null : unit;
}

String? _nz(String? raw) {
  final text = raw?.trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _packageTypeOrNull(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  for (final type in PackageTypes.all) {
    if (text.contains(type)) return type;
  }
  return null;
}
