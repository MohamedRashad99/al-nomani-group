import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../data/remote/auth_interceptor.dart';
import '../../data/remote/auth_token_store.dart';
import '../../data/remote/device_id_store.dart';
import '../../data/remote/erp_store.dart';
import '../../data/remote/firestore_erp_store.dart';
import '../../data/sync/arabic_workbook_builder.dart';
import '../../data/sync/firebase_sync_service.dart';
import '../../data/sync/google_sheets_live_sync.dart';
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
import '../../domain/services/entity_link_inspector.dart';
import '../../domain/services/import_service.dart';
import '../../domain/services/inventory_service.dart';
import '../../domain/services/outstanding_service.dart';
import '../../domain/services/purchase_service.dart';
import '../../domain/services/report_export_service.dart';
import '../../domain/services/sale_service.dart';
import '../../domain/services/seed_service.dart';
import '../../domain/services/supplier_account_service.dart';
import '../../domain/services/supplier_service.dart';
import '../../domain/services/user_admin_service.dart';
import '../../domain/services/product_ai_service.dart';
import '../../domain/services/product_image_service.dart';
import '../../features/app/app_alert_cubit.dart';
import '../../features/app/app_busy_cubit.dart';
import '../../features/auth/auth_cubit.dart';
import '../../features/backup/backup_cubit.dart';
import '../config/app_config.dart';

final sl = GetIt.instance;

Future<void> configureDependencies({
  required AppConfig config,
  ErpStore? store,
}) async {
  if (sl.isRegistered<AppConfig>()) {
    await sl.reset();
  }

  sl.registerSingleton<AppConfig>(config);
  sl.registerSingleton<ErpStore>(store ?? FirestoreErpStore());
  sl.registerLazySingleton(
    () => const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      webOptions: WebOptions(),
    ),
  );
  sl.registerLazySingleton(() => DeviceIdStore(sl()));
  sl.registerLazySingleton(() => AuthTokenStore(sl()));
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
  sl.registerLazySingleton(() => AuditService(sl()));
  sl.registerLazySingleton(() => ConflictResolutionService());
  sl.registerLazySingleton(() => AccountService(sl()));
  sl.registerLazySingleton(() => SupplierAccountService(sl()));
  sl.registerLazySingleton(
    () => InventoryService(store: sl(), devices: sl(), audit: sl()),
  );
  sl.registerLazySingleton(() => EntityLinkInspector(sl()));
  sl.registerLazySingleton(
    () => CatalogService(
      store: sl(),
      devices: sl(),
      audit: sl(),
      inspector: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => SaleService(
      store: sl(),
      devices: sl(),
      audit: sl(),
      inventory: sl(),
      accounts: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => CollectionService(
      store: sl(),
      devices: sl(),
      audit: sl(),
      accounts: sl(),
    ),
  );
  sl.registerLazySingleton(() => ImportService(sl(), sl()));
  sl.registerLazySingleton(() => DashboardService(sl()));
  sl.registerLazySingleton(() => BackupExportService(sl()));
  sl.registerLazySingleton(() => ArabicWorkbookBuilder(sl()));
  sl.registerLazySingleton(() => ReportExportService(sl()));
  sl.registerLazySingleton(
    () => UserAdminService(
      store: sl(),
      devices: sl(),
      audit: sl(),
      dio: sl(),
      config: sl(),
    ),
  );
  sl.registerLazySingleton(() => SeedService(sl(), sl()));
  sl.registerLazySingleton(
    () => AuthService(
      store: sl(),
      devices: sl(),
      config: sl(),
      dio: sl(),
      tokens: sl(),
      storage: sl(),
    ),
  );
  sl.registerLazySingleton(() => GoogleSheetsLiveSync(sl(), sl(), sl()));
  sl.registerLazySingleton(FirebaseSyncService.new);
  sl.registerLazySingleton(
    () => SyncEngine(
      store: sl(),
      devices: sl(),
      config: sl(),
      firebase: sl(),
      sheets: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => OutstandingService(
      store: sl(),
      devices: sl(),
      accounts: sl(),
      audit: sl(),
      sync: sl(),
      collections: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => PurchaseService(
      store: sl(),
      devices: sl(),
      audit: sl(),
      inventory: sl(),
      accounts: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => SupplierService(
      store: sl(),
      devices: sl(),
      audit: sl(),
      accounts: sl(),
      sync: sl(),
    ),
  );
  sl.registerLazySingleton(SyncQueueRepository.new);
  sl.registerLazySingleton(AppBusyCubit.new);
  sl.registerLazySingleton(AppAlertCubit.new);
  sl.registerLazySingleton(ProductImageService.new);
  sl.registerLazySingleton(ProductAiService.new);
  sl.registerLazySingleton(() => AuthCubit(sl(), sl()));
  sl.registerFactory(() => BackupCubit(sl(), sl(), sl()));
}
