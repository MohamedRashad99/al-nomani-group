import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_queue_repository.dart';

class AuditService {
  AuditService(this._db, this._queue);
  final AppDatabase _db;
  final SyncQueueRepository _queue;

  Future<void> write({
    required String? userId,
    required String deviceId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
  }) async {
    final id = newId();
    final createdAt = DateTime.now().toUtc();
    await _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            id: id,
            userId: Value(userId),
            deviceId: Value(deviceId),
            action: action,
            entityType: entityType,
            entityId: Value(entityId),
            oldValue: Value(oldValue == null ? null : jsonEncode(oldValue)),
            newValue: Value(newValue == null ? null : jsonEncode(newValue)),
            createdAt: createdAt,
          ),
        );
    await _queue.enqueue(
      entityType: SyncEntityType.auditLog,
      entityId: id,
      operation: SyncOperationType.create,
      payload: {
        'id': id,
        'user_id': userId,
        'device_id': deviceId,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'old_value': oldValue,
        'new_value': newValue,
        'created_at': createdAt.toIso8601String(),
        'version': 1,
      },
      operationId: id,
    );
  }
}
