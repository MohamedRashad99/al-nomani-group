import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../database/postgres_db.dart';
import 'google_sheets_backup.dart';

class SyncService {
  SyncService(this.db, this.sheets);
  final PostgresDb db;
  final GoogleSheetsBackup sheets;

  Future<Map<String, dynamic>> push(Map<String, dynamic> body) async {
    final deviceId = body['device_id'] as String? ?? '';
    final operations = (body['operations'] as List?) ?? const [];
    final results = <Map<String, dynamic>>[];

    for (final raw in operations) {
      final op = raw as Map<String, dynamic>;
      final operationId = op['operation_id'] as String;
      results.add(await _applyOne(deviceId, operationId, op));
    }

    try {
      await sheets.appendLive(operations.cast<Map<String, dynamic>>());
    } catch (_) {
      // Google failure must not roll back accepted PostgreSQL writes.
    }
    return {'results': results};
  }

  Future<Map<String, dynamic>> _applyOne(
    String deviceId,
    String operationId,
    Map<String, dynamic> op,
  ) async {
    final existing = await db.query(
      'SELECT status FROM sync_operations WHERE operation_id = @id',
      params: {'id': operationId},
    );
    if (existing.isNotEmpty) {
      return {'operation_id': operationId, 'status': 'duplicate'};
    }

    try {
      await db.transaction((tx) async {
        await tx.execute(
          Sql.named('''
            INSERT INTO sync_operations
            (operation_id, device_id, entity_type, entity_id, operation, payload, version, status, created_at, processed_at)
            VALUES (@id, @device, @type, @eid, @op, @payload, @ver, 'accepted', NOW(), NOW())
            '''),
          parameters: {
            'id': operationId,
            'device': deviceId,
            'type': op['entity_type'],
            'eid': op['entity_id'],
            'op': op['operation'],
            'payload': jsonEncode(op['payload']),
            'ver': op['version'] ?? 1,
          },
        );
        await _upsertEntity(tx, op);
      });
      return {'operation_id': operationId, 'status': 'accepted'};
    } catch (e) {
      return {
        'operation_id': operationId,
        'status': 'rejected',
        'error': 'تعذر حفظ العملية على الخادم.',
      };
    }
  }

  Future<void> _upsertEntity(TxSession tx, Map<String, dynamic> op) async {
    final type = op['entity_type'] as String;
    final payload = op['payload'] as Map<String, dynamic>;
    switch (type) {
      case 'sale':
        await tx.execute(
          Sql.named('''
            INSERT INTO sales (id, customer_id, sale_number, status, subtotal, paid_amount, remaining_amount, notes, sold_at, created_by, device_id, created_at, updated_at)
            VALUES (@id, @customer, @number, 'completed', @sub::numeric, @paid::numeric, @rem::numeric, @notes, @sold::timestamptz, @by, @device, NOW(), NOW())
            ON CONFLICT (id) DO NOTHING
            '''),
          parameters: {
            'id': payload['id'],
            'customer': payload['customer_id'],
            'number': payload['sale_number'],
            'sub': payload['subtotal'],
            'paid': payload['paid_amount'],
            'rem': payload['remaining_amount'],
            'notes': payload['notes'],
            'sold': payload['sold_at'],
            'by': payload['created_by'],
            'device': payload['device_id'],
          },
        );
        break;
      case 'collection':
        await tx.execute(
          Sql.named('''
            INSERT INTO collections (id, customer_id, amount, payment_method, collected_at, notes, created_by, device_id, created_at, updated_at)
            VALUES (@id, @customer, @amount::numeric, @method, @at::timestamptz, @notes, @by, @device, NOW(), NOW())
            ON CONFLICT (id) DO NOTHING
            '''),
          parameters: {
            'id': payload['id'],
            'customer': payload['customer_id'],
            'amount': payload['amount'],
            'method': payload['payment_method'],
            'at': payload['collected_at'],
            'notes': payload['notes'],
            'by': payload['created_by'],
            'device': payload['device_id'],
          },
        );
        break;
      case 'product':
        await tx.execute(
          Sql.named('''
            INSERT INTO products (id, name, sku, category_id, brand, description, purchase_price, selling_price, current_stock, minimum_stock, unit, custom_unit_label, is_active, version, device_id, created_at, updated_at)
            VALUES (@id, @name, @sku, @cat, @brand, @desc, @purchase::numeric, @sell::numeric, @stock::numeric, @min::numeric, @unit, @custom, @active, @ver, @device, NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              selling_price = EXCLUDED.selling_price,
              version = EXCLUDED.version,
              updated_at = NOW()
              WHERE products.version <= EXCLUDED.version
            '''),
          parameters: {
            'id': payload['id'],
            'name': payload['name'],
            'sku': payload['sku'],
            'cat': payload['category_id'],
            'brand': payload['brand'],
            'desc': payload['description'],
            'purchase': payload['purchase_price'],
            'sell': payload['selling_price'],
            'stock': payload['current_stock'] ?? '0',
            'min': payload['minimum_stock'] ?? '0',
            'unit': payload['unit'],
            'custom': payload['custom_unit_label'],
            'active': payload['is_active'] ?? true,
            'ver': payload['version'] ?? 1,
            'device': payload['device_id'],
          },
        );
        break;
      case 'customer':
        await tx.execute(
          Sql.named('''
            INSERT INTO customers (id, name, phone, address, area, notes, is_active, version, device_id, created_at, updated_at)
            VALUES (@id, @name, @phone, @address, @area, @notes, @active, @ver, @device, NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, phone = EXCLUDED.phone, version = EXCLUDED.version, updated_at = NOW()
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
            'ver': payload['version'] ?? 1,
            'device': payload['device_id'],
          },
        );
        break;
      default:
        break;
    }
  }
}
