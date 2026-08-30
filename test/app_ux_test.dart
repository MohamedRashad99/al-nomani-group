import 'package:al_nomani_group/core/theme/app_colors.dart';
import 'package:al_nomani_group/core/utils/egypt_phone.dart';
import 'package:al_nomani_group/features/app/app_alert_cubit.dart';
import 'package:al_nomani_group/features/app/app_alert_host.dart';
import 'package:al_nomani_group/features/app/startup_splash.dart';
import 'package:al_nomani_group/shared/widgets/customer_contact_actions.dart';
import 'package:al_nomani_group/shared/widgets/product_thumb.dart';
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

  testWidgets('animated splash uses dark green and drifting seeds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StartupSplashView()),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.darkGreen);
    expect(StartupSplashView.displayDuration, const Duration(seconds: 2));
    expect(find.byKey(const Key('splash-seeds')), findsOneWidget);
    expect(find.text('مجموعة النعماني'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StartupSplashView), findsOneWidget);
    await tester.pump(StartupSplashView.displayDuration);
    expect(find.byType(StartupSplashView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('product image view renders data urls in memory', (tester) async {
    const pixel =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 44,
          height: 44,
          child: ProductImageView(url: pixel, size: 44),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('customer contact actions hide when phone is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomerContactActions(phone: ''))),
    );
    expect(find.byTooltip('اتصال'), findsNothing);
    expect(find.byTooltip('واتساب'), findsNothing);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CustomerContactActions(phone: '777123456')),
      ),
    );
    expect(find.byTooltip('اتصال'), findsOneWidget);
    expect(find.byTooltip('واتساب'), findsOneWidget);
  });

  test('egyptian phones normalize to +20 for call and whatsapp', () {
    expect(EgyptPhone.e164Digits('01234567890'), '201234567890');
    expect(EgyptPhone.e164Digits('1234567890'), '201234567890');
    expect(EgyptPhone.e164Digits('+201234567890'), '201234567890');
    expect(EgyptPhone.telUri('01234567890'), 'tel:+201234567890');
    expect(EgyptPhone.whatsAppMe('01234567890'), 'https://wa.me/201234567890');
    expect(
      EgyptPhone.whatsAppApi('01234567890'),
      'https://api.whatsapp.com/send?phone=201234567890',
    );
    expect(EgyptPhone.e164Digits(''), isNull);
    expect(EgyptPhone.telUri(null), isNull);
  });
}
