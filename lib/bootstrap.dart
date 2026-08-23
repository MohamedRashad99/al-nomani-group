import 'dart:async';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/widgets.dart';

import 'core/config/app_config.dart';
import 'core/di/injector.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'data/local/app_database.dart';
import 'data/local/metadata_store.dart';
import 'data/sync/sync_engine.dart';
import 'domain/services/seed_service.dart';
import 'features/auth/auth_cubit.dart';

Future<void> bootstrap({AppDatabase? database}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  await configureDependencies(config: config, database: database);

  final db = sl<AppDatabase>();
  try {
    await db.customSelect('SELECT COUNT(*) AS c FROM sync_queue').get();
  } catch (e) {
    throw StateError(
      'تعذر ترقية قاعدة البيانات المحلية. لم يتم تغيير بياناتك. يرجى تصدير نسخة احتياطية والتواصل مع المسؤول. $e',
    );
  }

  final meta = sl<MetadataStore>();
  await meta.set('app_version', AppVersions.appVersion);
  await meta.set('database_version', '${AppVersions.databaseVersion}');
  await meta.set('sync_protocol_version', '${AppVersions.syncProtocolVersion}');
  await sl<SeedService>().seedIfEmpty();
  await FirebaseBootstrap.ensure();
  await sl<AuthCubit>().restore();
  unawaited(sl<SyncEngine>().maybeRunScheduled());
}
