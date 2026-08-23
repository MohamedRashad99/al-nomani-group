import 'package:al_nomani_shared/al_nomani_shared.dart';

class SheetColumn {
  const SheetColumn(this.headerAr, this.headerEn);

  final String headerAr;
  final String headerEn;
}

class StructuredSheet {
  const StructuredSheet({
    required this.tab,
    required this.sql,
    required this.columns,
  });

  final String tab;
  final String sql;
  final List<SheetColumn> columns;
}

Object? sheetCell(Object? value) => SheetArabic.cell(value);

List<List<Object?>> buildSheetValues({
  required List<SheetColumn> columns,
  required List<List<Object?>> rows,
}) {
  return [
    [for (final column in columns) column.headerAr],
    for (final row in rows)
      [
        for (var index = 0; index < columns.length; index++)
          sheetCell(index < row.length ? row[index] : null),
      ],
  ];
}

const structuredSheets = <StructuredSheet>[
  StructuredSheet(
    tab: SheetArabic.categories,
    sql: '''
      SELECT id, name, description,
             CASE WHEN is_active THEN 'نعم' ELSE 'لا' END,
             created_at, updated_at
      FROM product_categories
      WHERE NOT is_deleted
      ORDER BY name
    ''',
    columns: [
      SheetColumn('المعرف', 'id'),
      SheetColumn('الاسم', 'name'),
      SheetColumn('الوصف', 'description'),
      SheetColumn('نشط', 'active'),
      SheetColumn('تاريخ الإنشاء', 'created_at'),
      SheetColumn('تاريخ التحديث', 'updated_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.products,
    sql: '''
      SELECT p.id, p.name, p.sku, c.name, p.brand, p.purchase_price, p.selling_price,
             p.current_stock, p.minimum_stock, p.unit, p.custom_unit_label,
             CASE WHEN p.is_active THEN 'نعم' ELSE 'لا' END,
             p.created_at, p.updated_at
      FROM products p
      LEFT JOIN product_categories c ON c.id = p.category_id
      WHERE NOT p.is_deleted
      ORDER BY p.name
    ''',
    columns: [
      SheetColumn('المعرف', 'id'),
      SheetColumn('الاسم', 'name'),
      SheetColumn('الرمز', 'sku'),
      SheetColumn('التصنيف', 'category'),
      SheetColumn('العلامة', 'brand'),
      SheetColumn('سعر الشراء', 'purchase_price'),
      SheetColumn('سعر البيع', 'selling_price'),
      SheetColumn('المخزون الحالي', 'current_stock'),
      SheetColumn('الحد الأدنى', 'minimum_stock'),
      SheetColumn('الوحدة', 'unit'),
      SheetColumn('وحدة مخصصة', 'custom_unit'),
      SheetColumn('نشط', 'active'),
      SheetColumn('تاريخ الإنشاء', 'created_at'),
      SheetColumn('تاريخ التحديث', 'updated_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.customers,
    sql: '''
      SELECT cu.id, cu.name, cu.phone, cu.address, cu.area, cu.notes,
             COALESCE(a.cached_balance, 0),
             CASE WHEN cu.is_active THEN 'نعم' ELSE 'لا' END,
             cu.created_at, cu.updated_at
      FROM customers cu
      LEFT JOIN customer_accounts a ON a.customer_id = cu.id
      WHERE NOT cu.is_deleted
      ORDER BY cu.name
    ''',
    columns: [
      SheetColumn('المعرف', 'id'),
      SheetColumn('الاسم', 'name'),
      SheetColumn('الهاتف', 'phone'),
      SheetColumn('العنوان', 'address'),
      SheetColumn('المنطقة', 'area'),
      SheetColumn('ملاحظات', 'notes'),
      SheetColumn('الرصيد الآجل', 'balance'),
      SheetColumn('نشط', 'active'),
      SheetColumn('تاريخ الإنشاء', 'created_at'),
      SheetColumn('تاريخ التحديث', 'updated_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.outstanding,
    sql: '''
      SELECT a.id, c.name, a.cached_balance, a.created_at, a.updated_at
      FROM customer_accounts a
      JOIN customers c ON c.id = a.customer_id
      ORDER BY c.name
    ''',
    columns: [
      SheetColumn('المعرف', 'id'),
      SheetColumn('العميل', 'customer'),
      SheetColumn('الرصيد', 'balance'),
      SheetColumn('تاريخ الإنشاء', 'created_at'),
      SheetColumn('تاريخ التحديث', 'updated_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.sales,
    sql: '''
      SELECT s.sale_number, c.name, s.status, s.subtotal, s.paid_amount, s.remaining_amount,
             CASE
               WHEN s.paid_amount <= 0 THEN 'آجل'
               WHEN s.remaining_amount <= 0 THEN 'نقدي'
               ELSE 'دفعة جزئية'
             END,
             s.notes, s.sold_at, u.display_name, s.cancel_reason, s.created_at
      FROM sales s
      JOIN customers c ON c.id = s.customer_id
      JOIN users u ON u.id = s.created_by
      WHERE NOT s.is_deleted
      ORDER BY s.sold_at DESC
    ''',
    columns: [
      SheetColumn('رقم الفاتورة', 'sale_number'),
      SheetColumn('العميل', 'customer'),
      SheetColumn('الحالة', 'status'),
      SheetColumn('الإجمالي', 'subtotal'),
      SheetColumn('المدفوع', 'paid'),
      SheetColumn('المتبقي', 'remaining'),
      SheetColumn('نوع الدفع', 'payment_type'),
      SheetColumn('ملاحظات', 'notes'),
      SheetColumn('تاريخ البيع', 'sold_at'),
      SheetColumn('البائع', 'sold_by'),
      SheetColumn('سبب الإلغاء', 'cancel_reason'),
      SheetColumn('تاريخ الإنشاء', 'created_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.saleItems,
    sql: '''
      SELECT s.sale_number, p.name, p.sku, si.quantity, si.unit, si.unit_price, si.line_total, si.created_at
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products p ON p.id = si.product_id
      ORDER BY s.sold_at DESC, si.created_at
    ''',
    columns: [
      SheetColumn('رقم الفاتورة', 'sale_number'),
      SheetColumn('المنتج', 'product'),
      SheetColumn('الرمز', 'sku'),
      SheetColumn('الكمية', 'quantity'),
      SheetColumn('الوحدة', 'unit'),
      SheetColumn('سعر الوحدة', 'unit_price'),
      SheetColumn('الإجمالي', 'line_total'),
      SheetColumn('تاريخ الإنشاء', 'created_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.collections,
    sql: '''
      SELECT c.name, col.amount, col.payment_method, col.collected_at, col.notes,
             u.display_name, col.status
      FROM collections col
      JOIN customers c ON c.id = col.customer_id
      JOIN users u ON u.id = col.created_by
      WHERE NOT col.is_deleted
      ORDER BY col.collected_at DESC
    ''',
    columns: [
      SheetColumn('العميل', 'customer'),
      SheetColumn('المبلغ', 'amount'),
      SheetColumn('طريقة الدفع', 'payment_method'),
      SheetColumn('تاريخ التحصيل', 'collected_at'),
      SheetColumn('ملاحظات', 'notes'),
      SheetColumn('المحصّل', 'collected_by'),
      SheetColumn('الحالة', 'status'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.accountTransactions,
    sql: '''
      SELECT t.created_at, c.name, t.type, t.amount, t.running_balance,
             t.reference_type, t.reference_id, t.notes
      FROM customer_account_transactions t
      JOIN customers c ON c.id = t.customer_id
      ORDER BY t.created_at DESC
    ''',
    columns: [
      SheetColumn('التاريخ', 'created_at'),
      SheetColumn('العميل', 'customer'),
      SheetColumn('النوع', 'type'),
      SheetColumn('المبلغ', 'amount'),
      SheetColumn('الرصيد بعد الحركة', 'running_balance'),
      SheetColumn('مرجع', 'reference_type'),
      SheetColumn('رقم المرجع', 'reference_id'),
      SheetColumn('ملاحظات', 'notes'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.inventory,
    sql: '''
      SELECT m.created_at, p.name, p.sku, m.type, m.quantity, m.unit,
             m.previous_stock, m.new_stock, m.reference_type, m.notes
      FROM inventory_movements m
      JOIN products p ON p.id = m.product_id
      ORDER BY m.created_at DESC
    ''',
    columns: [
      SheetColumn('التاريخ', 'created_at'),
      SheetColumn('المنتج', 'product'),
      SheetColumn('الرمز', 'sku'),
      SheetColumn('النوع', 'type'),
      SheetColumn('الكمية', 'quantity'),
      SheetColumn('الوحدة', 'unit'),
      SheetColumn('المخزون السابق', 'previous_stock'),
      SheetColumn('المخزون الجديد', 'new_stock'),
      SheetColumn('مرجع', 'reference_type'),
      SheetColumn('ملاحظات', 'notes'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.users,
    sql: '''
      SELECT u.username, u.display_name, r.display_name_ar,
             CASE WHEN u.is_active THEN 'نعم' ELSE 'لا' END, u.created_at
      FROM users u
      JOIN roles r ON r.id = u.role_id
      WHERE NOT u.is_deleted
      ORDER BY u.username
    ''',
    columns: [
      SheetColumn('اسم المستخدم', 'username'),
      SheetColumn('الاسم', 'display_name'),
      SheetColumn('الدور', 'role'),
      SheetColumn('نشط', 'active'),
      SheetColumn('تاريخ الإنشاء', 'created_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.settings,
    sql: '''
      SELECT key, value, updated_at
      FROM settings
      ORDER BY key
    ''',
    columns: [
      SheetColumn('المفتاح', 'key'),
      SheetColumn('القيمة', 'value'),
      SheetColumn('تاريخ التحديث', 'updated_at'),
    ],
  ),
  StructuredSheet(
    tab: SheetArabic.auditLogs,
    sql: '''
      SELECT created_at, action, entity_type, entity_id, user_id
      FROM audit_logs
      ORDER BY created_at DESC
    ''',
    columns: [
      SheetColumn('التاريخ', 'created_at'),
      SheetColumn('الإجراء', 'action'),
      SheetColumn('النوع', 'entity_type'),
      SheetColumn('المعرف', 'entity_id'),
      SheetColumn('المستخدم', 'user_id'),
    ],
  ),
];
