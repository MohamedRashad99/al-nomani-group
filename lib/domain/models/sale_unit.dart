import 'package:al_nomani_shared/al_nomani_shared.dart';

/// Unit the seller typed the quantity in when adding an invoice line.
///
/// Stock, prices and every existing calculation stay in packages; the sub unit
/// is only an input convenience that is converted before it leaves the sheet.
enum SaleUnitKind {
  /// Whole packages (عبوة / شكارة / كيس …).
  package,

  /// The product measurement unit (جم / كجم / مل / لتر).
  subUnit;

  String get storageValue => switch (this) {
    SaleUnitKind.package => 'package',
    SaleUnitKind.subUnit => 'subUnit',
  };

  /// Anything unknown or missing reads back as a package sale so invoices
  /// saved before multi-unit selling keep their original meaning.
  static SaleUnitKind fromStorage(String? raw) {
    final value = (raw ?? '').trim();
    return value == SaleUnitKind.subUnit.storageValue
        ? SaleUnitKind.subUnit
        : SaleUnitKind.package;
  }
}

/// One choice of the unit selector in the add-item sheet.
class SaleUnitOption {
  const SaleUnitOption({
    required this.kind,
    required this.label,
    required this.quantityLabel,
    required this.storageCode,
    required this.baseUnitsPerUnit,
    this.unit,
  });

  final SaleUnitKind kind;

  /// Short label on the selector chip: `عبوة`, `جم`, `كجم`.
  final String label;

  /// Label of the quantity field: `الكمية بالعبوة`, `الكمية بالغرام`.
  final String quantityLabel;

  /// Value persisted in `input_unit`.
  final String storageCode;

  /// Base units (the product [ProductUnit]) held by one unit of this option:
  /// the package size for a package, `1` for the base unit itself and `1000`
  /// for the promoted unit (kg over g, l over ml).
  final Quantity baseUnitsPerUnit;

  /// `null` for the package option.
  final ProductUnit? unit;

  bool get isPackage => kind == SaleUnitKind.package;

  String format(Quantity value) => '${value.toDisplay()} $label';

  @override
  bool operator ==(Object other) =>
      other is SaleUnitOption &&
      other.kind == kind &&
      other.storageCode == storageCode &&
      other.baseUnitsPerUnit == baseUnitsPerUnit;

  @override
  int get hashCode => Object.hash(kind, storageCode, baseUnitsPerUnit);
}

/// Everything the invoice needs about one typed quantity.
class SaleQuantityBreakdown {
  const SaleQuantityBreakdown({
    required this.option,
    required this.packageType,
    required this.inputQuantity,
    required this.packageQuantity,
    required this.baseQuantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  final SaleUnitOption option;

  /// Package label of the product (`عبوة`, `شكارة`).
  final String packageType;

  /// What the seller typed, in [option] units (250 grams).
  final Quantity inputQuantity;

  /// The same amount expressed in packages (0.5). Stock is deducted with this.
  final Quantity packageQuantity;

  /// The same amount in the product base unit (250 g).
  final Quantity baseQuantity;

  /// Price of one whole package.
  final Money unitPrice;

  final Money totalPrice;

  SaleUnitKind get selectedUnit => option.kind;

  String get inputUnit => option.storageCode;

  /// `250 جم` / `2 عبوة`.
  String get inputLabel => option.format(inputQuantity);

  /// `0.5 عبوة`.
  String get packageLabel => '${packageQuantity.toDisplay()} $packageType';
}
