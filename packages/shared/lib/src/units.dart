enum ProductUnit {
  kilogram,
  gram,
  liter,
  milliliter,
  piece,
  custom;

  String get code => switch (this) {
    ProductUnit.kilogram => 'kg',
    ProductUnit.gram => 'g',
    ProductUnit.liter => 'l',
    ProductUnit.milliliter => 'ml',
    ProductUnit.piece => 'pcs',
    ProductUnit.custom => 'custom',
  };

  String get arabicLabel => switch (this) {
    ProductUnit.kilogram => 'كيلوغرام',
    ProductUnit.gram => 'غرام',
    ProductUnit.liter => 'لتر',
    ProductUnit.milliliter => 'مليلتر',
    ProductUnit.piece => 'قطعة',
    ProductUnit.custom => 'وحدة مخصصة',
  };

  String get symbol => switch (this) {
    ProductUnit.kilogram => 'كجم',
    ProductUnit.gram => 'جم',
    ProductUnit.liter => 'لتر',
    ProductUnit.milliliter => 'مل',
    ProductUnit.piece => 'قطعة',
    ProductUnit.custom => arabicLabel,
  };

  static const measurable = [
    ProductUnit.milliliter,
    ProductUnit.liter,
    ProductUnit.gram,
    ProductUnit.kilogram,
    ProductUnit.piece,
  ];

  static ProductUnit fromCode(String code) {
    final n = code.trim().toLowerCase().replaceAll('ـ', '');
    if (n.isEmpty) return ProductUnit.piece;
    switch (n) {
      case 'kg':
      case 'kgs':
      case 'كيلو':
      case 'كيلوغرام':
      case 'كجم':
      case 'كغ':
      case 'كيلو جرام':
      case 'kilogram':
      case 'kilograms':
        return ProductUnit.kilogram;
      case 'g':
      case 'gm':
      case 'جم':
      case 'غرام':
      case 'جرام':
      case 'gram':
      case 'grams':
        return ProductUnit.gram;
      case 'l':
      case 'ltr':
      case 'liter':
      case 'litre':
      case 'liters':
      case 'litres':
      case 'لتر':
      case 'لترا':
      case 'لترات':
        return ProductUnit.liter;
      case 'ml':
      case 'مل':
      case 'ملل':
      case 'مليلتر':
      case 'ميللتر':
      case 'milliliter':
      case 'millilitre':
        return ProductUnit.milliliter;
      case 'pcs':
      case 'pc':
      case 'piece':
      case 'pieces':
      case 'قطعة':
      case 'قطع':
      case 'حبة':
        return ProductUnit.piece;
      default:
        return ProductUnit.custom;
    }
  }
}

abstract final class PackageTypes {
  static const bottle = 'عبوة';
  static const sack = 'شكارة';
  static const bag = 'كيس';
  static const tin = 'صفيحة';
  static const carton = 'كرتونة';
  static const jerry = 'جالون';
  static const piece = 'قطعة';

  static const all = [bottle, sack, bag, tin, carton, jerry, piece];
}
