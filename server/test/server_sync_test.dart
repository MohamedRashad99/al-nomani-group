import 'package:al_nomani_server/config/env.dart';
import 'package:al_nomani_server/database/postgres_db.dart';
import 'package:al_nomani_server/database/server_seeder.dart';
import 'package:al_nomani_server/services/auth_service.dart';
import 'package:al_nomani_server/services/google_sheets_backup.dart';
import 'package:al_nomani_server/services/sync_service.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:test/test.dart';

void main() {
  late PostgresDb db;
  late AuthService auth;
  late SyncService sync;
  late AuthUser user;

  const env = Env(
    jwtSecret: 'test-secret-that-is-long-and-not-for-production',
    databaseUrl: 'postgres://postgres:postgres@localhost:5432/al_nomani_test',
    googleLiveSpreadsheetId: '',
    googleFullSpreadsheetId: '',
    googleServiceAccountJson: null,
    syncIntervalDays: 5,
    allowSeed: true,
    bootstrapAdminUsername: 'integration-admin',
    bootstrapAdminPassword: 'safe-test-password',
    databaseSsl: false,
  );

  setUpAll(() async {
    db = PostgresDb(env);
    await db.open();
    await db.migrate();
    await db.query('''
      TRUNCATE TABLE
        roles, permissions, role_permissions, users, product_categories,
        products, customers, customer_accounts, sales, sale_items,
        collections, customer_account_transactions, inventory_movements,
        audit_logs, sync_operations, sync_logs, conflicts, settings,
        backup_outbox, backup_runs
      CASCADE
    ''');
    await ServerSeeder(db, env).seedBootstrapAdmin();
    auth = AuthService(db, env);
    final login = await auth.login('integration-admin', 'safe-test-password');
    user = auth.verify(login['access_token'] as String);
    sync = SyncService(db, GoogleSheetsBackup(env, db));
  });

  tearDownAll(() async {
    await db.connection.close();
  });

  test(
    'authenticated sync handles all transactional entities in FK order',
    () async {
      final result = await sync.push({
        'device_id': 'integration-device',
        'operations': [
          _operation(
            id: 'op-category',
            type: 'category',
            entityId: 'category-test',
            payload: {
              'id': 'category-test',
              'name': 'تصنيف اختبار',
              'version': 1,
            },
          ),
          _operation(
            id: 'op-customer',
            type: 'customer',
            entityId: 'customer-test',
            payload: {
              'id': 'customer-test',
              'name': 'عميل اختبار',
              'version': 1,
            },
          ),
          _operation(
            id: 'op-account',
            type: 'customerAccount',
            entityId: 'account-test',
            payload: {
              'id': 'account-test',
              'customer_id': 'customer-test',
              'cached_balance': '8.000',
              'version': 1,
            },
          ),
          _operation(
            id: 'op-product',
            type: 'product',
            entityId: 'product-test',
            payload: {
              'id': 'product-test',
              'name': 'منتج اختبار',
              'sku': 'TEST-SKU-001',
              'category_id': 'category-test',
              'purchase_price': '3.000',
              'selling_price': '10.000',
              'current_stock': '9.000',
              'minimum_stock': '2.000',
              'unit': 'kg',
              'version': 1,
            },
          ),
          _operation(
            id: 'op-sale',
            type: 'sale',
            entityId: 'sale-test',
            payload: {
              'id': 'sale-test',
              'customer_id': 'customer-test',
              'sale_number': 'S-TEST-001',
              'subtotal': '10.000',
              'paid_amount': '2.000',
              'remaining_amount': '8.000',
              'sold_at': DateTime.now().toUtc().toIso8601String(),
              'version': 1,
              'items': [
                {
                  'id': 'sale-item-test',
                  'sale_id': 'sale-test',
                  'product_id': 'product-test',
                  'quantity': '1.000',
                  'unit': 'kg',
                  'unit_price': '10.000',
                  'line_total': '10.000',
                },
              ],
            },
          ),
          _operation(
            id: 'op-movement',
            type: 'inventoryMovement',
            entityId: 'movement-test',
            payload: {
              'id': 'movement-test',
              'product_id': 'product-test',
              'type': 'sale',
              'quantity': '-1.000',
              'unit': 'kg',
              'previous_stock': '10.000',
              'new_stock': '9.000',
            },
          ),
          _operation(
            id: 'op-account-transaction',
            type: 'customerAccountTransaction',
            entityId: 'account-transaction-test',
            payload: {
              'id': 'account-transaction-test',
              'account_id': 'account-test',
              'customer_id': 'customer-test',
              'type': 'sale',
              'amount': '8.000',
              'running_balance': '8.000',
            },
          ),
          _operation(
            id: 'op-collection',
            type: 'collection',
            entityId: 'collection-test',
            payload: {
              'id': 'collection-test',
              'customer_id': 'customer-test',
              'amount': '2.000',
              'payment_method': 'cash',
              'collected_at': DateTime.now().toUtc().toIso8601String(),
              'version': 1,
            },
          ),
          _operation(
            id: 'op-audit',
            type: 'auditLog',
            entityId: 'audit-test',
            payload: {
              'id': 'audit-test',
              'action': 'sale.create',
              'entity_type': 'sale',
              'entity_id': 'sale-test',
            },
          ),
        ],
      }, user);

      final statuses = (result['results'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['status'])
          .toList();
      expect(statuses, everyElement('accepted'));
      expect((result['backup'] as Map)['status'], 'not_configured');
      expect(
        (await db.query(
          'SELECT COUNT(*) FROM backup_outbox WHERE status = \'pending\'',
        )).first[0],
        greaterThanOrEqualTo(9),
      );
    },
  );

  test(
    'same operation id is idempotent and unsupported types are rejected',
    () async {
      final duplicate = await sync.push({
        'device_id': 'integration-device',
        'operations': [
          _operation(
            id: 'op-product',
            type: 'product',
            entityId: 'product-test',
            payload: {'id': 'product-test', 'name': 'لن يكرر', 'version': 1},
          ),
          _operation(
            id: 'op-unsupported',
            type: 'unknown',
            entityId: 'unknown-test',
            payload: {'id': 'unknown-test'},
          ),
        ],
      }, user);
      final results = (duplicate['results'] as List)
          .cast<Map<String, dynamic>>();
      expect(results.first['status'], 'duplicate');
      expect(results.last['status'], 'rejected');
    },
  );

  test('newer server version produces explicit conflict', () async {
    await db.query(
      'UPDATE products SET version = 5 WHERE id = @id',
      params: {'id': 'product-test'},
    );
    final response = await sync.push({
      'device_id': 'other-device',
      'operations': [
        _operation(
          id: 'op-product-conflict',
          type: 'product',
          entityId: 'product-test',
          version: 2,
          payload: {'id': 'product-test', 'name': 'نسخة قديمة', 'version': 2},
        ),
      ],
    }, user);
    final result = (response['results'] as List).first as Map;
    expect(result['status'], 'conflict');
    expect((result['server'] as Map)['version'], 5);
  });

  test('sale cancellation is versioned and never deletes the sale', () async {
    final response = await sync.push({
      'device_id': 'integration-device',
      'operations': [
        _operation(
          id: 'op-sale-cancel',
          type: 'sale',
          entityId: 'sale-test',
          operation: 'cancel',
          version: 2,
          payload: {'id': 'sale-test', 'reason': 'اختبار', 'version': 2},
        ),
      ],
    }, user);
    expect(((response['results'] as List).first as Map)['status'], 'accepted');
    final sale = await db.query(
      'SELECT status, is_deleted FROM sales WHERE id = @id',
      params: {'id': 'sale-test'},
    );
    expect(sale.first[0], 'cancelled');
    expect(sale.first[1], isFalse);
  });

  test('refresh token rotates into a valid authenticated session', () async {
    final login = await auth.login('integration-admin', 'safe-test-password');
    final refreshed = await auth.refresh(login['refresh_token'] as String);
    final refreshedUser = auth.verify(refreshed['access_token'] as String);
    expect(refreshedUser.id, user.id);
    expect(refreshedUser.can(AppPermission.backupView), isTrue);
  });

  test(
    'missing Google credentials are reported without consuming outbox',
    () async {
      final backup = GoogleSheetsBackup(env, db);
      final before = (await db.query(
        'SELECT COUNT(*) FROM backup_outbox WHERE status = \'pending\'',
      )).first[0];
      final live = await backup.processPending();
      final full = await backup.writeFullBackup();
      final after = (await db.query(
        'SELECT COUNT(*) FROM backup_outbox WHERE status = \'pending\'',
      )).first[0];

      expect(live.configured, isFalse);
      expect(full.configured, isFalse);
      expect(after, before);
    },
  );
}

Map<String, dynamic> _operation({
  required String id,
  required String type,
  required String entityId,
  required Map<String, dynamic> payload,
  String operation = 'create',
  int version = 1,
}) {
  return {
    'operation_id': id,
    'entity_type': type,
    'entity_id': entityId,
    'operation': operation,
    'payload': payload,
    'version': version,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
}
