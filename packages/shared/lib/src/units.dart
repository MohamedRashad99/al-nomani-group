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

  static ProductUnit fromCode(String code) {
    return ProductUnit.values.firstWhere(
      (u) => u.code == code,
      orElse: () => ProductUnit.custom,
    );
  }
}
