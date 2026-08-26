import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';

import '../entities/erp_models.dart';
import '../../data/remote/erp_store.dart';

class AuditService {
  AuditService(this._store);
  final ErpStore _store;

  Future<void> write({
    required String? userId,
    required String deviceId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
  }) {
    return _store.putAudit(
      AuditLog(
        id: newId(),
        userId: userId,
        deviceId: deviceId,
        action: action,
        entityType: entityType,
        entityId: entityId,
        oldValue: oldValue == null ? null : jsonEncode(oldValue),
        newValue: newValue == null ? null : jsonEncode(newValue),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }
}
