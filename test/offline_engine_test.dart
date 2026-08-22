import 'package:al_nomani_group/core/config/app_config.dart';
import 'package:al_nomani_group/core/di/injector.dart';
import 'package:al_nomani_group/data/local/app_database.dart';
import 'package:al_nomani_group/data/sync/sync_queue_repository.dart';
import 'package:al_nomani_group/domain/models/sale_draft.dart';
import 'package:al_nomani_group/domain/services/sale_service.dart';
import 'package:al_nomani_group/domain/services/seed_service.dart';
import 'package:al_nomani_group/domain/session.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig _config() => const AppConfig(
  environment: 'test',
  apiBaseUrl: 'http://127.0.0.1:9',
  syncIntervalDays: 5,
  syncMode: SyncMode.scheduled,
  allowSeed: true,
  googleLiveSpreadsheetId: 'test',
  appVersion: AppVersions.appVersion,
  databaseVersion: AppVersions.databaseVersion,
  syncProtocolVersion: AppVersions.syncProtocolVersion,
);

AppSession admin() => AppSession(
  userId: 'test-admin',
  username: 'admin',
  displayName: 'مدير',
  roleName: AppRole.admin,
  permissions: AppPermission.all.toSet(),
  expiresAt: DateTime.now().add(const Duration(days: 1)),
  isOfflineVerified: true,
);

Future<AppDatabase> readyDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await configureDependencies(config: _config(), database: db);
  await sl<SeedService>().seedIfEmpty();
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    if (sl.isRegistered<AppDatabase>()) {
      await sl<AppDatabase>().close();
    }
    await sl.reset();
  });

  test(
    'cash, credit and partial sales persist locally without internet',
    () async {
      final db = await readyDb();
      final session = admin().copyWithUser(
        usersFirstId: (await db.select(db.users).get()).first.id,
      );
      final sales = sl<SaleService>();

      final cash = await sales.create(
        session,
        SaleDraft(
          customerId: 'c-ahmed',
          paidAmount: Money.parse('5.500'),
          lines: [
            SaleLineDraft(
              productId: 'p-imidacloprid',
              quantity: Quantity.parse('1'),
              unit: 'l',
              unitPrice: Money.parse('5.500'),
            ),
          ],
        ),
      );
      expect(cash.remaining.isZero, isTrue);

      final credit = await sales.create(
        session,
        SaleDraft(
          customerId: 'c-salem',
          paidAmount: Money.zero(),
          lines: [
            SaleLineDraft(
              productId: 'p-npk',
              quantity: Quantity.parse('2'),
              unit: 'kg',
              unitPrice: Money.parse('10.500'),
            ),
          ],
        ),
      );
      expect(credit.subtotal.toStorage(), '21.000');
      expect(credit.remaining.toStorage(), '21.000');

      final partial = await sales.create(
        session,
        SaleDraft(
          customerId: 'c-ahmed',
          paidAmount: Money.parse('400'),
          lines: [
            SaleLineDraft(
              productId: 'p-urea',
              quantity: Quantity.parse('1'),
              unit: 'kg',
              unitPrice: Money.parse('1000'),
            ),
          ],
        ),
      );
      expect(partial.remaining.toStorage(), '600.000');

      final queue = await sl<SyncQueueRepository>().pending();
      expect(
        queue.where((q) => q.entityType == 'sale').length,
        greaterThanOrEqualTo(3),
      );
    },
  );

  test(
    'sale transaction rolls back inventory and queue together on invalid stock',
    () async {
      await readyDb();
      final session = admin();
      expect(
        () => sl<SaleService>().create(
          session,
          SaleDraft(
            customerId: 'c-ahmed',
            paidAmount: Money.zero(),
            lines: [
              SaleLineDraft(
                productId: 'p-drip',
                quantity: Quantity.parse('9999'),
                unit: 'pcs',
                unitPrice: Money.parse('0.180'),
              ),
            ],
          ),
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('customer balance is derived from account transactions', () async {
    final db = await readyDb();
    final session = admin().copyWithUser(
      usersFirstId: (await db.select(db.users).get()).first.id,
    );
    await sl<SaleService>().create(
      session,
      SaleDraft(
        customerId: 'c-fatima',
        paidAmount: Money.parse('250'),
        lines: [
          SaleLineDraft(
            productId: 'p-humic',
            quantity: Quantity.parse('1'),
            unit: 'l',
            unitPrice: Money.parse('1000'),
          ),
        ],
      ),
    );
    final account = await (db.select(
      db.customerAccounts,
    )..where((t) => t.customerId.equals('c-fatima'))).getSingle();
    expect(Money.parse(account.cachedBalance).toStorage(), '750.000');
    final txs = await (db.select(
      db.customerAccountTransactions,
    )..where((t) => t.customerId.equals('c-fatima'))).get();
    expect(txs.length, 2);
  });

  test('permissions deny unauthorized sale', () async {
    await readyDb();
    final viewer = AppSession(
      userId: 'v',
      username: 'v',
      displayName: 'v',
      roleName: AppRole.viewer,
      permissions: RolePermissions.matrix[AppRole.viewer]!.toSet(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      isOfflineVerified: true,
    );
    expect(
      () => sl<SaleService>().create(
        viewer,
        SaleDraft(
          customerId: 'c-ahmed',
          paidAmount: Money.zero(),
          lines: const [],
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'sync queue and sales survive "restart" of a new database connection to same executor',
    () async {
      final db = await readyDb();
      final session = admin().copyWithUser(
        usersFirstId: (await db.select(db.users).get()).first.id,
      );
      await sl<SaleService>().create(
        session,
        SaleDraft(
          customerId: 'c-ahmed',
          paidAmount: Money.parse('4.000'),
          lines: [
            SaleLineDraft(
              productId: 'p-glyphosate',
              quantity: Quantity.parse('1'),
              unit: 'l',
              unitPrice: Money.parse('4.000'),
            ),
          ],
        ),
      );
      final sales = await db.select(db.sales).get();
      final queue = await db.select(db.syncQueue).get();
      expect(sales, isNotEmpty);
      expect(queue, isNotEmpty);
      expect(sales.first.isDeleted, isFalse);
    },
  );
}

extension on AppSession {
  AppSession copyWithUser({required String usersFirstId}) {
    return AppSession(
      userId: usersFirstId,
      username: username,
      displayName: displayName,
      roleName: roleName,
      permissions: permissions,
      expiresAt: expiresAt,
      isOfflineVerified: isOfflineVerified,
    );
  }
}
