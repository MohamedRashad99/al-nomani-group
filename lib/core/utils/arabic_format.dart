import 'package:intl/intl.dart';

abstract final class ArabicFormat {
  static final _date = DateFormat('d MMMM y', 'ar');
  static final _dateTime = DateFormat('d MMM، h:mm a', 'ar');
  static final _day = DateFormat('E', 'ar');
  static final _number = NumberFormat.decimalPattern('ar');

  static String date(DateTime value) => _date.format(value.toLocal());

  static String dateTime(DateTime value) => _dateTime.format(value.toLocal());

  static String day(DateTime value) => _day.format(value.toLocal());

  static String number(num value) => _number.format(value);

  static String paymentMethod(String code) => switch (code) {
    'cash' => 'نقداً',
    'transfer' => 'تحويل بنكي',
    'credit' => 'آجل',
    'partial' => 'دفعة جزئية',
    _ => 'غير محدد',
  };

  static String status(String code) => switch (code) {
    'completed' => 'مكتملة',
    'cancelled' => 'ملغاة',
    'pending' => 'معلّقة',
    'failed' => 'فشلت',
    'synced' => 'متزامنة',
    _ => 'غير محدد',
  };

  static String movementType(String code) => switch (code) {
    'sale' => 'بيع',
    'sale_reversal' => 'عكس بيع',
    'stock_in' => 'إدخال مخزون',
    'stock_out' => 'إخراج مخزون',
    'adjustment' => 'تسوية مخزون',
    _ => 'حركة مخزون',
  };
}
