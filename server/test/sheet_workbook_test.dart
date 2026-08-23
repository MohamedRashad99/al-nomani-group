import 'package:al_nomani_server/services/sheet_workbook.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:test/test.dart';

void main() {
  test('structured workbook uses Arabic tabs and Arabic-only headers', () {
    final tabs = structuredSheets.map((sheet) => sheet.tab).toSet();
    expect(
      tabs,
      containsAll([
        SheetArabic.products,
        SheetArabic.categories,
        SheetArabic.customers,
        SheetArabic.sales,
        SheetArabic.saleItems,
        SheetArabic.collections,
        SheetArabic.outstanding,
        SheetArabic.accountTransactions,
        SheetArabic.inventory,
        SheetArabic.users,
      ]),
    );

    final values = buildSheetValues(
      columns: const [
        SheetColumn('الاسم', 'name'),
        SheetColumn('الرصيد', 'balance'),
        SheetColumn('الحالة', 'status'),
      ],
      rows: [
        ['أحمد', 12.5, 'completed'],
        [null, true, 'cash'],
      ],
    );

    expect(values.length, 3);
    expect(values[0], ['الاسم', 'الرصيد', 'الحالة']);
    expect(values[1], ['أحمد', 12.5, 'مكتملة']);
    expect(values[2], ['', 'نعم', 'نقداً']);
  });
}
