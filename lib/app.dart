import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';
import 'core/di/injector.dart';
import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/app/app_busy_cubit.dart';
import 'features/app/update_banner.dart';
import 'features/auth/auth_cubit.dart';

class AlNomaniApp extends StatefulWidget {
  const AlNomaniApp({super.key});

  @override
  State<AlNomaniApp> createState() => _AlNomaniAppState();
}

class _AlNomaniAppState extends State<AlNomaniApp> {
  late final GoRouter _router = createRouter(sl<AuthCubit>());

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<AuthCubit>()),
        BlocProvider.value(value: sl<AppBusyCubit>()),
      ],
      child: MaterialApp.router(
        title: S.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.rtl(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              children: [
                const UpdateBanner(),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          );
        },
        routerConfig: _router,
      ),
    );
  }
}
