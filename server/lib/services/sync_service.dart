import 'dart:async';
import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';

import '../database/postgres_db.dart';
import 'auth_service.dart';
import 'google_sheets_backup.dart';

class SyncService {
  SyncService(this.db, this.backup);

  final PostgresDb db;
  final GoogleSheetsBackup backup;

  static const supportedEntities = {
    'category',
    'product',
    'customer',
    'customerAccount',
    'sale',
    'saleItem',
    'collection',
    'customerAccountTransaction',
    'inventoryMovement',
    'auditLog',
    'setting',
    'user',
  };

  Future<Map<String, dynamic>> push(
    Map<String, dynamic> body,
    AuthUser authenticatedUser,
  ) async {
    final deviceId = body['device_id'] as String? ?? '';
    final operations = (body['operations'] as List?) ?? const [];
    final results = <Map<String, dynamic>>[];

    for (final raw in operations) {
      final operation = Map<String, dynamic>.from(raw as Map);
      results.add(
        await _applyOne(
          deviceId: deviceId,
          operation: operation,
          authenticatedUser: authenticatedUser,
        ),
      );
    }
    unawaited(() async {
      await backup.processPending();
      await backup.writeFullBackup();
    }());
    return {'results': results, 'backup': await backup.health()};
  }

  Future<Map<String, dynamic>> _applyOne({
    required String deviceId,
    required Map<String, dynamic> operation,
    required AuthUser authenticatedUser,
  }) async {
    final operationId = operation['operation_id'] as String? ?? '';
    final entityType = operation['entity_type'] as String? ?? '';
    final entityId = operation['entity_id'] as String? ?? '';
    final payload = Map<String, dynamic>.from(
      operation['payload'] as Map? ?? const {},
    );
    final version =
        (operation['version'] as num?)?.toInt() ??
        (payload['version'] as num?)?.toInt() ??
        1;

    if (operationId.isEmpty || entityId.isEmpty) {
      return _rejected(operationId, 'بيانات عملية المزامنة غير مكتملة.');
    }
    if (!supportedEntities.contains(entityType)) {
      return _rejected(
        operationId,
        'نوع العملية غير مدعوم ولا يمكن اعتباره متزامناً.',
      );
    }

    final existing = await db.query(
      'SELECT status, result FROM sync_operations WHERE operation_id = @id',
      params: {'id': operationId},
    );
    if (existing.isNotEmpty) {
      return {
        'operation_id': operationId,
        'status': 'duplicate',
        'result': existing.first[1],
      };
    }

    final serverVersion = await _serverVersion(entityType, entityId);
    if (serverVersion != null && serverVersion > version) {
      final serverPayload = await _serverPayload(entityType, entityId);
      await db.query(
        '''
        INSERT INTO conflicts
          (id, entity_type, entity_id, local_payload, server_payload)
        VALUES
          (@id, @type, @entity, @local, @server)
        ON CONFLICT (id) DO UPDATE SET
          local_payload = EXCLUDED.local_payload,
          server_payload = EXCLUDED.server_payload,
          created_at = NOW()
        ''',
        params: {
          'id': operationId,
          'type': entityType,
          'entity': entityId,
          'local': jsonEncode(payload),
          'server': jsonEncode(serverPayload),
        },
      );
      return {
        'operation_id': operationId,
        'status': 'conflict',
        'server': serverPayload,
      };
    }

    try {
      await db.transaction((tx) async {
        await _upsertEntity(
          tx: tx,
          entityType: entityType,
          payload: payload,
          operation: operation['operation'] as String? ?? 'create',
          authenticatedUser: authenticatedUser,
          deviceId: deviceId,
        );
        await tx.execute(
          Sql.named('''
            INSERT INTO sync_operations
              (operation_id, device_id, entity_type, entity_id, operation,
               payload, version, status, result, created_at, processed_at)
            VALUES
              (@id, @device, @type, @entity, @operation, @payload, @version,
               'accepted', @result, @created::timestamptz, NOW())
          '''),
          parameters: {
            'id': operationId,
            'device': deviceId,
            'type': entityType,
            'entity': entityId,
            'operation': operation['operation'] ?? 'create',
            'payload': jsonEncode(payload),
            'version': version,
            'result': jsonEncode({'status': 'accepted'}),
            'created':
                operation['created_at'] ??
                DateTime.now().toUtc().toIso8601String(),
          },
        );
        await tx.execute(
          Sql.named('''
            INSERT INTO backup_outbox
              (id, operation_id, entity_type, entity_id, payload, status,
               retry_count, created_at)
            VALUES
              (@id, @operation, @type, @entity, @payload, 'pending', 0, NOW())
            ON CONFLICT (operation_id) DO NOTHING
          '''),
          parameters: {
            'id': 'backup-$operationId',
            'operation': operationId,
            'type': entityType,
            'entity': entityId,
            'payload': jsonEncode(payload),
          },
        );
      });
      return {'operation_id': operationId, 'status': 'accepted'};
    } catch (error) {
      return _rejected(
        operationId,
        'تعذر حفظ العملية على الخادم.',
        technical: error.toString(),
      );
    }
  }

  Future<void> _upsertEntity({
    required TxSession tx,
    required String entityType,
    required Map<String, dynamic> payload,
    required String operation,
    required AuthUser authenticatedUser,
    required String deviceId,
  }) async {
    switch (entityType) {
      case 'category':
        await tx.execute(
          Sql.named('''
            INSERT INTO product_categories
              (id, name, description, is_active, version, device_id,
               created_at, updated_at)
            VALUES
              (@id, @name, @description, @active, @version, @device,
               @created::timestamptz, @updated::timestamptz)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              description = EXCLUDED.description,
              is_active = EXCLUDED.is_active,
              version = EXCLUDED.version,
              device_id = EXCLUDED.device_id,
              updated_at = EXCLUDED.updated_at
            WHERE product_categories.version <= EXCLUDED.version
          '''),
          parameters: {
            'id': payload['id'],
            'name': payload['name'],
            'description': payload['description'],
            'active': payload['is_active'] ?? true,
            'version': payload['version'] ?? 1,
            'device': payload['device_id'] ?? deviceId,
            'created': _timestamp(payload['created_at']),
            'updated': _timestamp(payload['updated_at']),
          },
        );
        return;
      case 'product':
        await tx.execute(
          Sql.named('''
            INSERT INTO products
              (id, name, sku, category_id, brand, description, purchase_price,
               selling_price, current_stock, minimum_stock, unit,
               custom_unit_label, is_active, version, device_id,
               created_at, updated_at)
            VALUES
              (@id, @name, @sku, @category, @brand, @description,
               @purchase::numeric, @selling::numeric, @stock::numeric,
               @minimum::numeric, @unit, @custom, @active, @version, @device,
               @created::timestamptz, @updated::timestamptz)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name, sku = EXCLUDED.sku,
              category_id = EXCLUDED.category_id, brand = EXCLUDED.brand,
              description = EXCLUDED.description,
              purchase_price = EXCLUDED.purchase_price,
              selling_price = EXCLUDED.selling_price,
              current_stock = EXCLUDED.current_stock,
              minimum_stock = EXCLUDED.minimum_stock, unit = EXCLUDED.unit,
              custom_unit_label = EXCLUDED.custom_unit_label,
              is_active = EXCLUDED.is_active, version = EXCLUDED.version,
              device_id = EXCLUDED.device_id, updated_at = EXCLUDED.updated_at
            WHERE products.version <= EXCLUDED.version
          '''),
          parameters: {
            'id': payload['id'],
            'name': payload['name'],
            'sku': payload['sku'],
            'category': payload['category_id'],
            'brand': payload['brand'],
            'description': payload['description'],
            'purchase': payload['purchase_price'] ?? '0.000',
            'selling': payload['selling_price'] ?? '0.000',
            'stock': payload['current_stock'] ?? '0.000',
            'minimum': payload['minimum_stock'] ?? '0.000',
            'unit': payload['unit'] ?? 'piece',
            'custom': payload['custom_unit_label'],
            'active': payload['is_active'] ?? true,
            'version': payload['version'] ?? 1,
            'device': payload['device_id'] ?? deviceId,
            'created': _timestamp(payload['created_at']),
            'updated': _timestamp(payload['updated_at']),
          },
        );
        return;
      case 'customer':
        await tx.execute(
          Sql.named('''
            INSERT INTO customers
              (id, name, phone, address, area, notes, is_active, version,
               device_id, created_at, updated_at)
            VALUES
              (@id, @name, @phone, @address, @area, @notes, @active, @version,
               @device, @created::timestamptz, @updated::timestamptz)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name, phone = EXCLUDED.phone,
              address = EXCLUDED.address, area = EXCLUDED.area,
              notes = EXCLUDED.notes, is_active = EXCLUDED.is_active,
              version = EXCLUDED.version, device_id = EXCLUDED.device_id,
              updated_at = EXCLUDED.updated_at
            WHERE customers.version <= EXCLUDED.version
          '''),
          parameters: {
            'id': payload['id'],
            'name': payload['name'],
            'phone': payload['phone'],
            'address': payload['address'],
            'area': payload['area'],
            'notes': payload['notes'],
            'active': payload['is_active'] ?? true,
            'version': payload['version'] ?? 1,
            'device': payload['device_id'] ?? deviceId,
            'created': _timestamp(payload['created_at']),
            'updated': _timestamp(payload['updated_at']),
          },
        );
        return;
      case 'customerAccount':
        await tx.execute(
          Sql.named('''
            INSERT INTO customer_accounts
              (id, customer_id, cached_balance, version, device_id,
               created_at, updated_at)
            VALUES
              (@id, @customer, @balance::numeric, @version, @device,
               @created::timestamptz, @updated::timestamptz)
            ON CONFLICT (id) DO UPDATE SET
              cached_balance = EXCLUDED.cached_balance,
              version = EXCLUDED.version, device_id = EXCLUDED.device_id,
              updated_at = EXCLUDED.updated_at
            WHERE customer_accounts.version <= EXCLUDED.version
          '''),
          parameters: {
            'id': payload['id'],
            'customer': payload['customer_id'],
            'balance': payload['cached_balance'] ?? '0.000',
            'version': payload['version'] ?? 1,
            'device': payload['device_id'] ?? deviceId,
            'created': _timestamp(payload['created_at']),
            'updated': _timestamp(payload['updated_at']),
          },
        );
        return;
      case 'sale':
        if (operation == 'cancel') {
          await tx.execute(
            Sql.named('''
              UPDATE sales SET
                status = 'cancelled', cancelled_at = NOW(),
                cancelled_by = @user, cancel_reason = @reason,
                version = @version, updated_at = NOW()
              WHERE id = @id AND version <= @version
            '''),
            parameters: {
              'id': payload['id'],
              'user': authenticatedUser.id,
              'reason': payload['reason'],
              'version': payload['version'] ?? 1,
            },
          );
          return;
        }
        await tx.execute(
          Sql.named('''
            INSERT INTO sales
              (id, customer_id, sale_number, status, subtotal, paid_amount,
               remaining_amount, notes, sold_at, created_by, device_id,
               version, created_at, updated_at)
            VALUES
              (@id, @customer, @number, @status, @subtotal::numeric,
               @paid::numeric, @remaining::numeric, @notes,
               @sold::timestamptz, @user, @device, @version,
               @created::timestamptz, @updated::timestamptz)
            ON CONFLICT (id) DO UPDATE SET
              status = EXCLUDED.status, paid_amount = EXCLUDED.paid_amount,
              remaining_amount = EXCLUDED.remaining_amount,
              notes = EXCLUDED.notes, version = EXCLUDED.version,
              updated_at = EXCLUDED.updated_at
            WHERE sales.version <= EXCLUDED.version
          '''),
          parameters: {
            'id': payload['id'],
            'customer': payload['customer_id'],
            'number': payload['sale_number'],
            'status': payload['status'] ?? 'completed',
            'subtotal': payload['subtotal'],
            'paid': payload['paid_amount'],
            'remaining': payload['remaining_amount'],
            'notes': payload['notes'],
            'sold': _timestamp(payload['sold_at']),
            'user': authenticatedUser.id,
            'device': payload['device_id'] ?? deviceId,
            'version': payload['version'] ?? 1,
            'created': _timestamp(payload['created_at'] ?? payload['sold_at']),
            'updated': _timestamp(payload['updated_at']),
          },
        );
        for (final rawItem in (payload['items'] as List?) ?? const []) {
          await _upsertSaleItem(
            tx,
            Map<String, dynamic>.from(rawItem as Map),
            deviceId,
          );
        }
        return;
      case 'saleItem':
        await _upsertSaleItem(tx, payload, deviceId);
        return;
      case 'collection':
        await tx.execute(
          Sql.named('''
            INSERT INTO collections
              (id, customer_id, amount, payment_method, collected_at, notes,
               created_by, status, version, device_id, created_at, updated_at)
            VALUES
              (@id, @customer, @amount::numeric, @method,
               @collected::timestamptz, @notes, @user, @status, @version,
               @device, @created::timestamptz, @updated::timestamptz)
            ON CONFLICT (id) DO UPDATE SET
              status = EXCLUDED.status, notes = EXCLUDED.notes,
              version = EXCLUDED.version, updated_at = EXCLUDED.updated_at
            WHERE collections.version <= EXCLUDED.version
          '''),
          parameters: {
            'id': payload['id'],
            'customer': payload['customer_id'],
            'amount': payload['amount'],
            'method': payload['payment_method'] ?? 'cash',
            'collected': _timestamp(payload['collected_at']),
            'notes': payload['notes'],
            'user': authenticatedUser.id,
            'status': payload['status'] ?? 'completed',
            'version': payload['version'] ?? 1,
            'device': payload['device_id'] ?? deviceId,
            'created': _timestamp(payload['created_at']),
            'updated': _timestamp(payload['updated_at']),
          },
        );
        return;
      case 'customerAccountTransaction':
        await tx.execute(
          Sql.named('''
            INSERT INTO customer_account_transactions
              (id, account_id, customer_id, type, amount, running_balance,
               reference_type, reference_id, notes, created_by, device_id,
               created_at)
            VALUES
              (@id, @account, @customer, @type, @amount::numeric,
               @balance::numeric, @reference_type, @reference_id, @notes,
               @user, @device, @created::timestamptz)
            ON CONFLICT (id) DO NOTHING
          '''),
          parameters: {
            'id': payload['id'],
            'account': payload['account_id'],
            'customer': payload['customer_id'],
            'type': payload['type'],
            'amount': payload['amount'],
            'balance': payload['running_balance'],
            'reference_type': payload['reference_type'],
            'reference_id': payload['reference_id'],
            'notes': payload['notes'],
            'user': authenticatedUser.id,
            'device': payload['device_id'] ?? deviceId,
            'created': _timestamp(payload['created_at']),
          },
        );
        await tx.execute(
          Sql.named('''
            UPDATE customer_accounts SET
              cached_balance = @balance::numeric,
              version = version + 1,
              updated_at = NOW()
            WHERE id = @account
          '''),
          parameters: {
            'account': payload['account_id'],
            'balance': payload['running_balance'],
          },
        );
        return;
      case 'inventoryMovement':
        await tx.execute(
          Sql.named('''
            INSERT INTO inventory_movements
              (id, product_id, type, quantity, unit, previous_stock, new_stock,
               reference_type, reference_id, notes, created_by, device_id,
               created_at)
            VALUES
              (@id, @product, @type, @quantity::numeric, @unit,
               @previous::numeric, @new::numeric, @reference_type,
               @reference_id, @notes, @user, @device, @created::timestamptz)
            ON CONFLICT (id) DO NOTHING
          '''),
          parameters: {
            'id': payload['id'],
            'product': payload['product_id'],
            'type': payload['type'],
            'quantity': payload['quantity'],
            'unit': payload['unit'],
            'previous': payload['previous_stock'],
            'new': payload['new_stock'],
            'reference_type': payload['reference_type'],
            'reference_id': payload['reference_id'],
            'notes': payload['notes'],
            'user': authenticatedUser.id,
            'device': payload['device_id'] ?? deviceId,
            'created': _timestamp(payload['created_at']),
          },
        );
        await tx.execute(
          Sql.named('''
            UPDATE products SET
              current_stock = @stock::numeric,
              updated_at = NOW()
            WHERE id = @product
          '''),
          parameters: {
            'product': payload['product_id'],
            'stock': payload['new_stock'],
          },
        );
        return;
      case 'auditLog':
        await tx.execute(
          Sql.named('''
            INSERT INTO audit_logs
              (id, user_id, device_id, action, entity_type, entity_id,
               old_value, new_value, created_at)
            VALUES
              (@id, @user, @device, @action, @type, @entity, @old, @new,
               @created::timestamptz)
            ON CONFLICT (id) DO NOTHING
          '''),
          parameters: {
            'id': payload['id'],
            'user': authenticatedUser.id,
            'device': payload['device_id'] ?? deviceId,
            'action': payload['action'],
            'type': payload['entity_type'],
            'entity': payload['entity_id'],
            'old': _jsonValue(payload['old_value']),
            'new': _jsonValue(payload['new_value']),
            'created': _timestamp(payload['created_at']),
          },
        );
        return;
      case 'setting':
        await tx.execute(
          Sql.named('''
            INSERT INTO settings (key, value, updated_at)
            VALUES (@key, @value, @updated::timestamptz)
            ON CONFLICT (key) DO UPDATE SET
              value = EXCLUDED.value, updated_at = EXCLUDED.updated_at
          '''),
          parameters: {
            'key': payload['key'] ?? payload['id'],
            'value': payload['value']?.toString() ?? '',
            'updated': _timestamp(payload['updated_at']),
          },
        );
        return;
      case 'user':
        if (authenticatedUser.role != 'admin') {
          throw StateError('admin permission required');
        }
        await tx.execute(
          Sql.named('''
            INSERT INTO users
              (id, username, display_name, password_hash, role_id, is_active,
               version, device_id, created_at, updated_at)
            VALUES
              (@id, @username, @display, @locked_hash, @role, FALSE,
               @version, @device, NOW(), NOW())
            ON CONFLICT (username) DO UPDATE SET
              display_name = EXCLUDED.display_name,
              role_id = EXCLUDED.role_id,
              is_active = @active,
              version = EXCLUDED.version,
              updated_at = NOW()
          '''),
          parameters: {
            'id': payload['id'],
            'username': payload['username'],
            'display': payload['display_name'],
            'role': payload['role_id'],
            'active': payload['is_active'] ?? true,
            'version': payload['version'] ?? 1,
            'device': deviceId,
            'locked_hash': BCrypt.hashpw(
              'offline-account-${payload['id']}',
              BCrypt.gensalt(),
            ),
          },
        );
        return;
    }
  }

  Future<void> _upsertSaleItem(
    TxSession tx,
    Map<String, dynamic> payload,
    String deviceId,
  ) async {
    await tx.execute(
      Sql.named('''
        INSERT INTO sale_items
          (id, sale_id, product_id, quantity, unit, unit_price, line_total,
           version, device_id, created_at)
        VALUES
          (@id, @sale, @product, @quantity::numeric, @unit,
           @price::numeric, @total::numeric, @version, @device,
           @created::timestamptz)
        ON CONFLICT (id) DO NOTHING
      '''),
      parameters: {
        'id': payload['id'],
        'sale': payload['sale_id'],
        'product': payload['product_id'],
        'quantity': payload['quantity'],
        'unit': payload['unit'],
        'price': payload['unit_price'],
        'total': payload['line_total'],
        'version': payload['version'] ?? 1,
        'device': payload['device_id'] ?? deviceId,
        'created': _timestamp(payload['created_at']),
      },
    );
  }

  Future<int?> _serverVersion(String entityType, String entityId) async {
    final table = switch (entityType) {
      'category' => 'product_categories',
      'product' => 'products',
      'customer' => 'customers',
      'customerAccount' => 'customer_accounts',
      'sale' => 'sales',
      'collection' => 'collections',
      _ => null,
    };
    if (table == null) return null;
    final result = await db.query(
      'SELECT version FROM $table WHERE id = @id',
      params: {'id': entityId},
    );
    return result.isEmpty ? null : result.first[0] as int;
  }

  Future<Map<String, dynamic>> _serverPayload(
    String entityType,
    String entityId,
  ) async {
    final table = switch (entityType) {
      'category' => 'product_categories',
      'product' => 'products',
      'customer' => 'customers',
      'customerAccount' => 'customer_accounts',
      'sale' => 'sales',
      'collection' => 'collections',
      _ => null,
    };
    if (table == null) return const {};
    final result = await db.query(
      'SELECT row_to_json(t)::text FROM $table t WHERE id = @id',
      params: {'id': entityId},
    );
    if (result.isEmpty) return const {};
    return Map<String, dynamic>.from(
      jsonDecode(result.first[0] as String) as Map,
    );
  }

  Map<String, dynamic> _rejected(
    String operationId,
    String message, {
    String? technical,
  }) {
    return {
      'operation_id': operationId,
      'status': 'rejected',
      'error': message,
      if (technical != null) 'error_code': 'server_write_failed',
    };
  }

  String _timestamp(dynamic value) {
    if (value is String && DateTime.tryParse(value) != null) return value;
    return DateTime.now().toUtc().toIso8601String();
  }

  String? _jsonValue(dynamic value) {
    if (value == null) return null;
    return value is String ? value : jsonEncode(value);
  }
}
