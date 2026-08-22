import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../local/app_database.dart';

class SyncQueueRepository {
  SyncQueueRepository(this._db);
  final AppDatabase _db;

  Future<void> enqueue({
    required SyncEntityType entityType,
    required String entityId,
    required SyncOperationType operation,
    required Map<String, dynamic> payload,
    required String operationId,
  }) async {
    await _db
        .into(_db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            id: newId(),
            operationId: operationId,
            entityType: entityType.name,
            entityId: entityId,
            operation: operation.name,
            payload: jsonEncode(payload),
            createdAt: DateTime.now().toUtc(),
            status: SyncStatus.pending.name,
          ),
        );
  }

  Future<List<SyncQueueData>> pending() {
    return (_db.select(_db.syncQueue)
          ..where(
            (t) => t.status.isIn([
              SyncStatus.pending.name,
              SyncStatus.failed.name,
            ]),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<int> countByStatus(SyncStatus status) async {
    final query = _db.selectOnly(_db.syncQueue)
      ..addColumns([_db.syncQueue.id.count()])
      ..where(_db.syncQueue.status.equals(status.name));
    final row = await query.getSingle();
    return row.read(_db.syncQueue.id.count()) ?? 0;
  }

  Future<void> markProcessing(String id) async {
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncStatus.processing.name),
        lastAttemptAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> markSynced(String id) async {
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncStatus.synced.name),
        syncedAt: Value(DateTime.now().toUtc()),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> markFailed(String id, String error) async {
    final current = await (_db.select(
      _db.syncQueue,
    )..where((t) => t.id.equals(id))).getSingle();
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncStatus.failed.name),
        retryCount: Value(current.retryCount + 1),
        lastAttemptAt: Value(DateTime.now().toUtc()),
        lastError: Value(error),
      ),
    );
  }

  Future<void> retryFailed() async {
    await (_db.update(_db.syncQueue)
          ..where((t) => t.status.equals(SyncStatus.failed.name)))
        .write(const SyncQueueCompanion(status: Value('pending')));
  }
}
