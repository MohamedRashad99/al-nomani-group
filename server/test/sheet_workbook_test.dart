import 'package:al_nomani_server/services/sheet_workbook.dart';
import 'package:test/test.dart';

void main() {
  test('structured workbook has bilingual headers and every business tab', () {
    final tabs = structuredSheets.map((sheet) => sheet.tab).toSet();
    expect(
      tabs,
      containsAll([
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
      ]),
    );

    final values = buildSheetValues(
      columns: const [
        SheetColumn('الاسم', 'name'),
        SheetColumn('الرصيد', 'balance'),
      ],
      rows: [
        ['أحمد', 12.5],
        [null, true],
      ],
    );

    expect(values[0], ['الاسم', 'الرصيد']);
    expect(values[1], ['name', 'balance']);
    expect(values[2], ['أحمد', 12.5]);
    expect(values[3], ['', 'نعم']);
  });
}
