import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../data/local/app_database.dart';
import '../../data/local/metadata_store.dart';
import '../session.dart';
import 'audit_service.dart';

class ConflictResolutionService {
  ConflictResolutionService(this._db, this._metadata, this._audit);

  final AppDatabase _db;
  final MetadataStore _metadata;
  final AuditService _audit;

  Future<List<Conflict>> openConflicts() {
    return _openConflictsQuery().get();
  }

  Stream<List<Conflict>> watchOpenConflicts() {
    return _openConflictsQuery().watch();
  }

  SimpleSelectStatement<$ConflictsTable, Conflict> _openConflictsQuery() {
    return (_db.select(_db.conflicts)
      ..where((row) => row.status.equals('open'))
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]));
  }

  Future<void> acceptServer(AppSession session, String conflictId) async {
    await _resolve(session, conflictId, keepLocal: false);
  }

  Future<void> keepLocal(AppSession session, String conflictId) async {
    await _resolve(session, conflictId, keepLocal: true);
  }

  Future<void> _resolve(
    AppSession session,
    String conflictId, {
    required bool keepLocal,
  }) async {
    final conflict = await (_db.select(
      _db.conflicts,
    )..where((row) => row.id.equals(conflictId))).getSingleOrNull();
    if (conflict == null || conflict.status != 'open') {
      throw const ValidationException('التعارض غير متاح.');
    }
    final server = Map<String, dynamic>.from(
      jsonDecode(conflict.serverPayload) as Map,
    );
    final local = Map<String, dynamic>.from(
      jsonDecode(conflict.localPayload) as Map,
    );
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      if (keepLocal) {
        final nextVersion = ((server['version'] as num?)?.toInt() ?? 1) + 1;
        local['version'] = nextVersion;
        await (_db.update(_db.syncQueue)..where(
              (row) =>
                  row.entityType.equals(conflict.entityType) &
                  row.entityId.equals(conflict.entityId) &
                  row.lastError.equals('تعارض في الإصدار'),
            ))
            .write(
              SyncQueueCompanion(
                payload: Value(jsonEncode(local)),
                status: const Value('pending'),
                lastError: const Value(null),
              ),
            );
        await _setLocalVersion(
          conflict.entityType,
          conflict.entityId,
          nextVersion,
        );
      } else {
        await _applyServer(conflict.entityType, conflict.entityId, server);
        await (_db.update(_db.syncQueue)..where(
              (row) =>
                  row.entityType.equals(conflict.entityType) &
                  row.entityId.equals(conflict.entityId) &
                  row.lastError.equals('تعارض في الإصدار'),
            ))
            .write(
              SyncQueueCompanion(
                status: const Value('synced'),
                syncedAt: Value(now),
                lastError: const Value(null),
              ),
            );
      }
      await (_db.update(
        _db.conflicts,
      )..where((row) => row.id.equals(conflict.id))).write(
        ConflictsCompanion(
          status: const Value('resolved'),
          resolvedAt: Value(now),
          resolvedBy: Value(session.userId),
          resolution: Value(keepLocal ? 'keep_local' : 'accept_server'),
        ),
      );
      await _audit.write(
        userId: session.userId,
        deviceId: await _metadata.deviceId(),
        action: 'sync.conflict.resolve',
        entityType: conflict.entityType,
        entityId: conflict.entityId,
        oldValue: {'conflict_id': conflict.id},
        newValue: {'resolution': keepLocal ? 'keep_local' : 'accept_server'},
      );
    });
  }

  Future<void> _setLocalVersion(String type, String id, int version) async {
    switch (type) {
      case 'product':
        await (_db.update(_db.products)..where((row) => row.id.equals(id)))
            .write(ProductsCompanion(version: Value(version)));
        return;
      case 'customer':
        await (_db.update(_db.customers)..where((row) => row.id.equals(id)))
            .write(CustomersCompanion(version: Value(version)));
        return;
      case 'category':
        await (_db.update(_db.productCategories)
              ..where((row) => row.id.equals(id)))
            .write(ProductCategoriesCompanion(version: Value(version)));
        return;
      default:
        return;
    }
  }

  Future<void> _applyServer(
    String type,
    String id,
    Map<String, dynamic> server,
  ) async {
    final updatedAt =
        DateTime.tryParse(server['updated_at']?.toString() ?? '') ??
        DateTime.now().toUtc();
    switch (type) {
      case 'product':
        await (_db.update(
          _db.products,
        )..where((row) => row.id.equals(id))).write(
          ProductsCompanion(
            name: Value(server['name'] as String),
            sku: Value(server['sku'] as String),
            categoryId: Value(server['category_id'] as String?),
            brand: Value(server['brand'] as String?),
            description: Value(server['description'] as String?),
            purchasePrice: Value(server['purchase_price'].toString()),
            sellingPrice: Value(server['selling_price'].toString()),
            currentStock: Value(server['current_stock'].toString()),
            minimumStock: Value(server['minimum_stock'].toString()),
            unit: Value(server['unit'] as String),
            customUnitLabel: Value(server['custom_unit_label'] as String?),
            isActive: Value(server['is_active'] as bool? ?? true),
            version: Value((server['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(updatedAt),
          ),
        );
        return;
      case 'customer':
        await (_db.update(
          _db.customers,
        )..where((row) => row.id.equals(id))).write(
          CustomersCompanion(
            name: Value(server['name'] as String),
            phone: Value(server['phone'] as String?),
            address: Value(server['address'] as String?),
            area: Value(server['area'] as String?),
            notes: Value(server['notes'] as String?),
            isActive: Value(server['is_active'] as bool? ?? true),
            version: Value((server['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(updatedAt),
          ),
        );
        return;
      case 'category':
        await (_db.update(
          _db.productCategories,
        )..where((row) => row.id.equals(id))).write(
          ProductCategoriesCompanion(
            name: Value(server['name'] as String),
            description: Value(server['description'] as String?),
            isActive: Value(server['is_active'] as bool? ?? true),
            version: Value((server['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(updatedAt),
          ),
        );
        return;
      default:
        throw const ValidationException(
          'هذا النوع من التعارض يحتاج معالجة يدوية.',
        );
    }
  }
}
