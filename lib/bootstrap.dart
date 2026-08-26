import 'dart:async';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/widgets.dart';

import 'core/config/app_config.dart';
import 'core/di/injector.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'data/remote/device_id_store.dart';
import 'data/remote/erp_store.dart';
import 'data/remote/firestore_erp_store.dart';
import 'data/sync/sync_engine.dart';
import 'domain/services/seed_service.dart';
import 'features/auth/auth_cubit.dart';

Future<void> bootstrap({ErpStore? store}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  await configureDependencies(config: config, store: store);

  final devices = sl<DeviceIdStore>();
  await devices.setPref('app_version', AppVersions.appVersion);
  await devices.setPref('database_version', '${AppVersions.databaseVersion}');
  await devices.setPref(
    'sync_protocol_version',
    '${AppVersions.syncProtocolVersion}',
  );
  await sl<SeedService>().ensureDemoAdminIdentity();
  await sl<AuthCubit>().restore();
  unawaited(_attachFirebase());
  unawaited(sl<SyncEngine>().maybeRunScheduled());
}

Future<void> _attachFirebase() async {
  if (!await FirebaseBootstrap.ensure()) return;
  final store = sl<ErpStore>();
  if (store is FirestoreErpStore) {
    await store.ensureReady();
  }
  await sl<SeedService>().ensureDemoAdminIdentity();
}
