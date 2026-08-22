import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/config/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import 'app_busy_cubit.dart';

class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final response = await sl<Dio>().get<Map<String, dynamic>>(
        'version.json',
      );
      final remote = response.data?['app_version'] as String?;
      if (remote != null && remote != sl<AppConfig>().appVersion && mounted) {
        setState(() => _available = true);
      }
    } catch (_) {
      // Offline: keep current cached version. Do not force reload.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final busy = context.watch<AppBusyCubit>().isBusy;
    return Material(
      color: Colors.orange.shade100,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          dense: true,
          title: const Text(S.updateAvailable),
          trailing: TextButton(
            onPressed: busy ? null : () {},
            child: Text(busy ? S.updateLater : S.updateNow),
          ),
        ),
      ),
    );
  }
}
