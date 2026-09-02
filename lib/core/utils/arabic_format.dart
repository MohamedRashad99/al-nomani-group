import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:intl/intl.dart';

abstract final class ArabicFormat {
  static final _date = DateFormat('d MMMM y', 'ar');
  static final _dateTime = DateFormat('d MMM، h:mm a', 'ar');
  static final _day = DateFormat('E', 'ar');
  static final _number = NumberFormat.decimalPattern('ar');

  static String date(DateTime value) => _date.format(EgyptTime.toCairo(value));

  static String dateTime(DateTime value) =>
      _dateTime.format(EgyptTime.toCairo(value));

  static String day(DateTime value) => _day.format(EgyptTime.toCairo(value));

  /// Transaction date in Cairo: `01/09/2026`.
  static String transactionDate(DateTime value) => EgyptTime.formatDate(value);

  /// Transaction time in Cairo: `03:45 PM`.
  static String transactionTime(DateTime value) => EgyptTime.formatTime(value);

  /// Single-line Cairo stamp: `01/09/2026 - 03:45 PM`.
  static String transactionDateTime(DateTime value) =>
      EgyptTime.formatDateTime(value);

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
    'sale_cancel' => 'إلغاء بيع',
    'purchase' => 'شراء',
    'purchase_cancel' => 'إلغاء شراء',
    'return' => 'مرتجع',
    'sale_return' => 'مرتجع بيع',
    'stock_in' => 'إدخال مخزون',
    'stock_out' => 'إخراج مخزون',
    'adjustment' => 'تسوية مخزون',
    _ => 'حركة مخزون',
  };
}
