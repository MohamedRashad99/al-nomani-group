import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../../data/remote/auth_interceptor.dart';
import '../../data/remote/auth_token_store.dart';
import '../../data/sync/arabic_workbook_builder.dart';
import '../../data/sync/google_sheets_live_sync.dart';
import '../../data/sync/sync_baseline_service.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_queue_repository.dart';
import '../../domain/services/account_service.dart';
import '../../domain/services/audit_service.dart';
import '../../domain/services/auth_service.dart';
import '../../domain/services/backup_export_service.dart';
import '../../domain/services/catalog_service.dart';
import '../../domain/services/collection_service.dart';
import '../../domain/services/conflict_resolution_service.dart';
import '../../domain/services/dashboard_service.dart';
import '../../domain/services/inventory_service.dart';
import '../../domain/services/report_export_service.dart';
import '../../domain/services/sale_service.dart';
import '../../domain/services/seed_service.dart';
import '../../domain/services/import_service.dart';
import '../../domain/services/outstanding_service.dart';
import '../../domain/services/user_admin_service.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../features/backup/backup_cubit.dart';
import '../config/app_config.dart';

final sl = GetIt.instance;

Future<void> configureDependencies({
  required AppConfig config,
  AppDatabase? database,
}) async {
  if (sl.isRegistered<AppConfig>()) {
    await sl.reset();
  }

  sl.registerSingleton<AppConfig>(config);
  sl.registerSingleton<AppDatabase>(database ?? AppDatabase());
  sl.registerLazySingleton(AuthTokenStore.new);
  sl.registerLazySingleton<Dio>(() {
    final options = BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
    );
    final client = Dio(options);
    final refreshClient = Dio(options);
    client.interceptors.add(
      AuthInterceptor(
        tokens: sl(),
        config: config,
        refreshClient: refreshClient,
      ),
    );
    return client;
  });
  sl.registerLazySingleton(() => MetadataStore(sl()));
  sl.registerLazySingleton(() => SyncQueueRepository(sl()));
  sl.registerLazySingleton(() => SyncBaselineService(sl(), sl(), sl()));
  sl.registerLazySingleton(() => AuditService(sl(), sl()));
  sl.registerLazySingleton(() => ConflictResolutionService(sl(), sl(), sl()));
  sl.registerLazySingleton(() => AccountService(sl(), sl()));
  sl.registerLazySingleton(
    () => InventoryService(db: sl(), metadata: sl(), queue: sl(), audit: sl()),
  );
  sl.registerLazySingleton(
    () => SaleService(
      db: sl(),
      metadata: sl(),
      queue: sl(),
      audit: sl(),
      inventory: sl(),
      accounts: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => CollectionService(
      db: sl(),
      metadata: sl(),
      queue: sl(),
      audit: sl(),
      accounts: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => CatalogService(db: sl(), metadata: sl(), queue: sl(), audit: sl()),
  );
  sl.registerLazySingleton(() => ImportService(sl(), sl(), sl()));
  sl.registerLazySingleton(() => DashboardService(sl()));
  sl.registerLazySingleton(() => BackupExportService(sl()));
  sl.registerLazySingleton(() => ReportExportService(sl()));
  sl.registerLazySingleton(
    () => UserAdminService(
      db: sl(),
      metadata: sl(),
      queue: sl(),
      audit: sl(),
      dio: sl(),
      config: sl(),
    ),
  );
  sl.registerLazySingleton(() => SeedService(sl(), sl(), sl()));
  sl.registerLazySingleton(
    () => AuthService(
      db: sl(),
      metadata: sl(),
      config: sl(),
      dio: sl(),
      tokens: sl(),
    ),
  );
  sl.registerLazySingleton(() => ArabicWorkbookBuilder(sl()));
  sl.registerLazySingleton(() => GoogleSheetsLiveSync(sl(), sl(), sl()));
  sl.registerLazySingleton(
    () => SyncEngine(
      db: sl(),
      metadata: sl(),
      queue: sl(),
      baseline: sl(),
      config: sl(),
      dio: sl(),
      sheets: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => OutstandingService(
      db: sl(),
      metadata: sl(),
      accounts: sl(),
      audit: sl(),
      sync: sl(),
      collections: sl(),
    ),
  );
  sl.registerLazySingleton(AppBusyCubit.new);
  sl.registerLazySingleton(() => AuthCubit(sl(), sl()));
  sl.registerFactory(() => BackupCubit(sl(), sl(), sl()));
}
