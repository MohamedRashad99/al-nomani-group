import 'package:al_nomani_group/features/app/app_alert_cubit.dart';
import 'package:al_nomani_group/features/app/app_alert_host.dart';
import 'package:al_nomani_group/shared/widgets/report_busy_barrier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('alert overlay shows a top message', (tester) async {
    final cubit = AppAlertCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const AppAlertHost(
            child: Scaffold(body: Text('المحتوى')),
          ),
        ),
      ),
    );
    cubit.success('تم الحفظ');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('تم الحفظ'), findsOneWidget);
    expect(find.text('المحتوى'), findsOneWidget);
  });

  testWidgets('report preview barrier appears while busy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReportBusyBarrier(
          busy: true,
          child: Text('معاينة'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('معاينة'), findsOneWidget);
  });
}
