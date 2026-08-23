enum SyncStatus {
  pending,
  processing,
  synced,
  failed;

  static SyncStatus parse(String raw) => SyncStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => SyncStatus.pending,
  );
}

enum SyncOperationType {
  create,
  update,
  delete,
  cancel;

  static SyncOperationType parse(String raw) => SyncOperationType.values
      .firstWhere((s) => s.name == raw, orElse: () => SyncOperationType.create);
}

enum SyncEntityType {
  product,
  category,
  customer,
  sale,
  saleItem,
  customerAccount,
  customerAccountTransaction,
  collection,
  inventoryMovement,
  user,
  role,
  auditLog,
  setting;

  static SyncEntityType parse(String raw) => SyncEntityType.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => SyncEntityType.setting,
  );
}

enum SyncMode { scheduled, nearRealtime }

abstract final class SyncConfigKeys {
  static const syncIntervalDays = 'sync_interval_days';
  static const syncMode = 'sync_mode';
  static const lastSuccessfulSyncAt = 'last_successful_sync_at';
  static const nextScheduledSyncAt = 'next_scheduled_sync_at';
  static const lastFullBackupAt = 'last_full_backup_at';
  static const lastSyncError = 'last_sync_error';
  static const deviceId = 'device_id';
  static const allowSeed = 'allow_seed';
}

abstract final class SyncDefaults {
  static const int productionIntervalDays = 5;
  static const SyncMode productionMode = SyncMode.scheduled;
  static const SyncMode developmentMode = SyncMode.nearRealtime;
}
