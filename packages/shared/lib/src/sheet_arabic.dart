/// Arabic tab names, headers, and coded values for Sheets / Excel.
abstract final class SheetArabic {
  static const overview = 'نظرة عامة';
  static const categories = 'التصنيفات';
  static const products = 'المنتجات';
  static const customers = 'العملاء';
  static const outstanding = 'المبالغ الآجلة';
  static const accountTransactions = 'حركات الآجل';
  static const sales = 'المبيعات';
  static const saleItems = 'بنود المبيعات';
  static const collections = 'التحصيلات';
  static const inventory = 'المخزون';
  static const users = 'المستخدمون';
  static const settings = 'الإعدادات';
  static const auditLogs = 'سجل العمليات';
  static const syncLogs = 'سجل المزامنة';

  static const tabsByEntity = <String, String>{
    'product': products,
    'category': categories,
    'customer': customers,
    'sale': sales,
    'saleItem': saleItems,
    'customerAccount': outstanding,
    'customerAccountTransaction': accountTransactions,
    'collection': collections,
    'inventoryMovement': inventory,
    'user': users,
    'auditLog': auditLogs,
    'setting': settings,
    'role': 'الأدوار',
  };

  static const retiredEnglishTabs = <String>{
    'Overview',
    'Products',
    'Categories',
    'Customers',
    'Sales',
    'Sale Items',
    'Collections',
    'Customer Accounts',
    'Customer Account Transactions',
    'Inventory Movements',
    'Users',
    'Settings',
    'Audit Logs',
    'Sync Logs',
  };

  static const _codes = <String, String>{
    'yes': 'نعم',
    'no': 'لا',
    'true': 'نعم',
    'false': 'لا',
    'completed': 'مكتملة',
    'cancelled': 'ملغاة',
    'pending': 'معلّقة',
    'failed': 'فشلت',
    'synced': 'متزامنة',
    'processing': 'قيد التنفيذ',
    'accepted': 'مقبولة',
    'running': 'قيد التشغيل',
    'success': 'نجاح',
    'partial': 'دفعة جزئية',
    'cash': 'نقداً',
    'transfer': 'تحويل بنكي',
    'credit': 'آجل',
    'sale': 'بيع',
    'payment': 'دفعة',
    'sale_cancel': 'إلغاء بيع',
    'payment_cancel': 'إلغاء دفعة',
    'purchase': 'شراء',
    'purchase_cancel': 'إلغاء شراء',
    'purchase_payment': 'دفعة شراء',
    'opening_balance': 'رصيد افتتاحي',
    'manual_debit': 'خصم يدوي',
    'manual_credit': 'إضافة يدوية',
    'stock_in': 'إدخال مخزون',
    'stock_out': 'إخراج مخزون',
    'manual_increase': 'زيادة يدوية',
    'manual_decrease': 'تخفيض يدوي',
    'adjustment': 'تسوية مخزون',
    'return': 'مرتجع',
    'sale_reversal': 'عكس بيع',
    'create': 'إنشاء',
    'update': 'تحديث',
    'cancel': 'إلغاء',
    'delete': 'حذف',
    'admin': 'مدير النظام',
    'manager': 'مدير',
    'cashier': 'أمين صندوق',
    'viewer': 'عرض فقط',
    'kg': 'كيلوغرام',
    'g': 'غرام',
    'l': 'لتر',
    'ml': 'مليلتر',
    'pcs': 'قطعة',
    'piece': 'قطعة',
    'custom': 'وحدة مخصصة',
    'customer': 'عميل',
    'product': 'منتج',
    'category': 'تصنيف',
    'inventory_movement': 'حركة مخزون',
    'inventoryMovement': 'حركة مخزون',
    'collection': 'تحصيل',
    'user': 'مستخدم',
    'setting': 'إعداد',
    'auditLog': 'سجل',
    'customerAccount': 'حساب آجل',
    'customerAccountTransaction': 'حركة آجل',
    'saleItem': 'بند بيع',
    'role': 'دور',
    'nearRealtime': 'فوري',
    'scheduled': 'مجدول',
    'sync_mode': 'وضع المزامنة',
    'sync_interval_days': 'فترة المزامنة بالأيام',
  };

  static Object? cell(Object? value) {
    if (value == null) return '';
    if (value is bool) return value ? 'نعم' : 'لا';
    if (value is DateTime) return _formatDate(value);
    final text = value.toString();
    if (text.isEmpty) return '';
    final direct = _codes[text] ?? _codes[text.toLowerCase()];
    if (direct != null) return direct;
    if (text.contains('.')) {
      final parts = text.split('.');
      if (parts.length == 2 &&
          (_codes.containsKey(parts[0]) || _codes.containsKey(parts[1]))) {
        return '${cell(parts[0])} — ${cell(parts[1])}';
      }
    }
    return value;
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $h:$min';
  }
}
