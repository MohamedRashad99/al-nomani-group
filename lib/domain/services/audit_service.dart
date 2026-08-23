import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';

class AuditService {
  AuditService(this._db);
  final AppDatabase _db;

  Future<void> write({
    required String? userId,
    required String deviceId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
  }) {
    return _db
        .into(_db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            id: newId(),
            userId: Value(userId),
            deviceId: Value(deviceId),
            action: action,
            entityType: entityType,
            entityId: Value(entityId),
            oldValue: Value(oldValue == null ? null : jsonEncode(oldValue)),
            newValue: Value(newValue == null ? null : jsonEncode(newValue)),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }
}
