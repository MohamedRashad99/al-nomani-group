import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/l10n/app_strings.dart';
import 'android_update_cubit.dart';

class MobileUpdateHost extends StatefulWidget {
  const MobileUpdateHost({super.key, required this.child});

  final Widget child;

  @override
  State<MobileUpdateHost> createState() => _MobileUpdateHostState();
}

class _MobileUpdateHostState extends State<MobileUpdateHost>
    with WidgetsBindingObserver {
  var _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !sl.isRegistered<AndroidUpdateCubit>()) return;
    WidgetsBinding.instance.addObserver(this);
    sl<AndroidUpdateCubit>().startLiveUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sl<AndroidUpdateCubit>().check(forceFetch: true);
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb || state != AppLifecycleState.resumed) return;
    if (!sl.isRegistered<AndroidUpdateCubit>()) return;
    sl<AndroidUpdateCubit>().check(forceFetch: true);
  }

  Future<void> _present(AndroidUpdateState state) async {
    if (!mounted || _dialogOpen || state.offer == null) return;
    if (state.phase != AndroidUpdatePhase.available &&
        state.phase != AndroidUpdatePhase.downloading &&
        state.phase != AndroidUpdatePhase.ready &&
        state.phase != AndroidUpdatePhase.failed) {
      return;
    }
    _dialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: state.offer?.forceUpdate != true,
      builder: (ctx) => BlocProvider.value(
        value: sl<AndroidUpdateCubit>(),
        child: const _AndroidUpdateDialog(),
      ),
    );
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !sl.isRegistered<AndroidUpdateCubit>()) {
      return widget.child;
    }
    return BlocListener<AndroidUpdateCubit, AndroidUpdateState>(
      bloc: sl<AndroidUpdateCubit>(),
      listenWhen: (previous, current) =>
          previous.phase != current.phase &&
          current.offer != null &&
          !_dialogOpen,
      listener: (context, state) => _present(state),
      child: widget.child,
    );
  }
}

class _AndroidUpdateDialog extends StatelessWidget {
  const _AndroidUpdateDialog();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AndroidUpdateCubit, AndroidUpdateState>(
      builder: (context, state) {
        final offer = state.offer;
        final force = offer?.forceUpdate == true;
        return PopScope(
          canPop: !force && state.phase != AndroidUpdatePhase.downloading,
          child: AlertDialog(
            title: Text(offer?.title ?? S.apkUpdateTitle),
            content: SizedBox(
              width: 360,
              child: _DialogBody(state: state),
            ),
            actions: _actions(context, state, force),
          ),
        );
      },
    );
  }

  List<Widget> _actions(
    BuildContext context,
    AndroidUpdateState state,
    bool force,
  ) {
    final cubit = context.read<AndroidUpdateCubit>();
    if (state.phase == AndroidUpdatePhase.downloading) {
      return const [];
    }
    return [
      if (!force)
        TextButton(
          onPressed: () {
            cubit.dismiss();
            Navigator.pop(context);
          },
          child: const Text(S.apkUpdateLater),
        ),
      if (state.phase == AndroidUpdatePhase.failed)
        FilledButton(
          onPressed: cubit.startDownload,
          child: const Text(S.apkUpdateRetry),
        )
      else if (state.phase == AndroidUpdatePhase.ready)
        FilledButton(
          onPressed: cubit.install,
          child: Text(
            state.needsInstallPermission ? S.apkUpdateInstall : S.apkUpdateNow,
          ),
        )
      else
        FilledButton(
          onPressed: cubit.startDownload,
          child: const Text(S.apkUpdateNow),
        ),
    ];
  }
}

class _DialogBody extends StatelessWidget {
  const _DialogBody({required this.state});

  final AndroidUpdateState state;

  @override
  Widget build(BuildContext context) {
    final offer = state.offer;
    if (state.phase == AndroidUpdatePhase.downloading) {
      final percent = (state.fraction * 100).floor();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(S.apkUpdateDownloading),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: state.total > 0 ? state.fraction : null,
          ),
          const SizedBox(height: 8),
          Text(
            state.total > 0
                ? '$percent%\n${_mb(state.received)} / ${_mb(state.total)}'
                : S.apkUpdateConnecting,
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(offer?.message ?? S.apkUpdateMessage),
        if (offer != null) ...[
          const SizedBox(height: 12),
          Text('${S.apkCurrentVersion}: ${offer.currentLabel}'),
          Text('${S.apkNewVersion}: ${offer.latestLabel}'),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  static String _mb(int bytes) {
    if (bytes <= 0) return '0 م.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }
}
