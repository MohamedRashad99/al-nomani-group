import 'package:al_nomani_group/shared/widgets/searchable_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('searchable select accepts typing and list selection', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableSelectField<String>(
            label: 'العميل',
            value: selected,
            options: const [
              SearchableOption(value: 'a', label: 'أحمد'),
              SearchableOption(value: 'b', label: 'فاطمة'),
            ],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'فاط');
    await tester.pumpAndSettle();
    await tester.tap(find.text('فاطمة').last);
    await tester.pumpAndSettle();
    expect(selected, 'b');
  });

  testWidgets('searchable select keeps typed text when no option matches', (
    tester,
  ) async {
    String? selected;
    var custom = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableSelectField<String>(
            label: 'العميل',
            allowCustom: true,
            value: selected,
            options: const [SearchableOption(value: 'a', label: 'أحمد')],
            onChanged: (value) => selected = value,
            onCustomText: (value) => custom = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'عميل جديد');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(custom, 'عميل جديد');
    expect(find.text('عميل جديد'), findsOneWidget);
  });
}
