import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';
import 'bootstrap.dart';
import 'core/di/injector.dart';
import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_reload.dart';
import 'data/sync/sync_engine.dart';
import 'features/app/app_alert_cubit.dart';
import 'features/app/app_alert_host.dart';
import 'features/app/app_busy_cubit.dart';
import 'features/app/startup_splash.dart';
import 'features/app/mobile_update_host.dart';
import 'features/app/update_banner.dart';
import 'features/auth/auth_cubit.dart';

class AlNomaniApp extends StatefulWidget {
  const AlNomaniApp({super.key});

  @override
  State<AlNomaniApp> createState() => _AlNomaniAppState();
}

class _AlNomaniAppState extends State<AlNomaniApp> with WidgetsBindingObserver {
  GoRouter? _router;
  var _booting = true;
  Object? _bootError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => hideHtmlBootSplash());
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    final alreadyReady = sl.isRegistered<AuthCubit>();
    try {
      if (!alreadyReady) {
        await bootstrap();
      }
      final router = createRouter(sl<AuthCubit>());
      final elapsed = DateTime.now().difference(started);
      final remaining = StartupSplashView.displayDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (!mounted) return;
      hideHtmlBootSplash();
      setState(() {
        _router = router;
        _booting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _bootError = error;
        _booting = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && sl.isRegistered<SyncEngine>()) {
      unawaited(sl<SyncEngine>().maybeRunScheduled());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: AppTheme.rtl(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/al_nomani_logo.png',
                          width: 96,
                          height: 96,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'تعذر بدء النظام بأمان',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${S.migrationFailed}\n\n$_bootError',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_booting || _router == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: AppTheme.rtl(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: StartupSplashView(),
        ),
      );
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<AuthCubit>()),
        BlocProvider.value(value: sl<AppBusyCubit>()),
        BlocProvider.value(value: sl<AppAlertCubit>()),
      ],
      child: MaterialApp.router(
        title: S.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.rtl(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AppAlertHost(
              child: MobileUpdateHost(
                child: Column(
                  children: [
                    const UpdateBanner(),
                    Expanded(child: child ?? const SizedBox.shrink()),
                  ],
                ),
              ),
            ),
          );
        },
        routerConfig: _router!,
      ),
    );
  }
}
