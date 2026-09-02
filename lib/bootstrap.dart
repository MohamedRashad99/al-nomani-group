import 'dart:async';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/widgets.dart';

import 'core/config/app_config.dart';
import 'core/di/injector.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/utils/app_reload.dart';
import 'core/utils/egypt_time.dart';
import 'data/remote/device_id_store.dart';
import 'data/remote/erp_store.dart';
import 'data/remote/firestore_erp_store.dart';
import 'data/sync/sync_engine.dart';
import 'domain/services/seed_service.dart';
import 'features/auth/auth_cubit.dart';

Future<void> bootstrap({ErpStore? store}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await EgyptTime.initialize();
  final config = await AppConfig.load();
  await configureDependencies(config: config, store: store);

  final devices = sl<DeviceIdStore>();
  await devices.setPref('app_version', AppVersions.appVersion);
  await devices.setPref('database_version', '${AppVersions.databaseVersion}');
  await devices.setPref(
    'sync_protocol_version',
    '${AppVersions.syncProtocolVersion}',
  );
  await sl<AuthCubit>().restore();
  unawaited(_warmBackend(config.buildLabel));
}

Future<void> _warmBackend(String buildLabel) async {
  try {
    await _attachFirebase();
    await sl<SeedService>().ensureDemoAdminIdentity();
    unawaited(sl<SyncEngine>().maybeRunScheduled());
  } catch (_) {}
  unawaited(ensureCurrentWebBuild(buildLabel));
}

Future<void> _attachFirebase() async {
  if (!await FirebaseBootstrap.ensure()) return;
  final store = sl<ErpStore>();
  if (store is FirestoreErpStore) {
    await store.ensureReady();
  }
}
