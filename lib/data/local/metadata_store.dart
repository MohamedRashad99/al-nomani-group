import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:drift/drift.dart';

import 'app_database.dart';

class MetadataStore {
  MetadataStore(this._db);
  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(
      _db.appMetadata,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) async {
    await _db
        .into(_db.appMetadata)
        .insertOnConflictUpdate(
          AppMetadataCompanion(
            key: Value(key),
            value: Value(value),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<String> deviceId() async {
    final existing = await get(SyncConfigKeys.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = newId();
    await set(SyncConfigKeys.deviceId, id);
    return id;
  }
}
