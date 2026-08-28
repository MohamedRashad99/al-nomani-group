import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_colors.dart';
import 'app_alert_cubit.dart';

class AppAlertHost extends StatefulWidget {
  const AppAlertHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppAlertHost> createState() => _AppAlertHostState();
}

class _AppAlertHostState extends State<AppAlertHost> {
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  Color _color(AppAlertKind kind) => switch (kind) {
    AppAlertKind.success => AppColors.green,
    AppAlertKind.error => AppColors.danger,
    AppAlertKind.warning => AppColors.orange,
    AppAlertKind.info => AppColors.darkGreen,
  };

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppAlertCubit, AppAlert?>(
      listener: (context, alert) {
        _hide?.cancel();
        if (alert == null) return;
        _hide = Timer(const Duration(seconds: 4), () {
          if (mounted) context.read<AppAlertCubit>().clear();
        });
      },
      child: BlocBuilder<AppAlertCubit, AppAlert?>(
        builder: (context, alert) {
          return Stack(
            children: [
              widget.child,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  offset: alert == null ? const Offset(0, -1.2) : Offset.zero,
                  child: SafeArea(
                    bottom: false,
                    child: alert == null
                        ? const SizedBox.shrink()
                        : Material(
                            color: _color(alert.kind),
                            elevation: 6,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                alert.message,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
