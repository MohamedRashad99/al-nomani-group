part of 'app_database.dart';

mixin Versioned on Table {
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

mixin SoftDelete on Table {
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get deletedBy => text().nullable()();
}

class Roles extends Table with Versioned, SoftDelete {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get displayNameAr => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Permissions extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RolePermissionLinks extends Table {
  TextColumn get roleId => text()();
  TextColumn get permissionId => text()();

  @override
  Set<Column<Object>> get primaryKey => {roleId, permissionId};
}

class Users extends Table with Versioned, SoftDelete {
  TextColumn get id => text()();
  TextColumn get username => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get passwordHash => text()();
  TextColumn get roleId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProductCategories extends Table with Versioned, SoftDelete {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Products extends Table with Versioned, SoftDelete {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get sku => text().unique()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get brand => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get purchasePrice => text()();
  TextColumn get sellingPrice => text()();
  TextColumn get currentStock => text()();
  TextColumn get minimumStock => text()();
  TextColumn get unit => text()();
  TextColumn get customUnitLabel => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Customers extends Table with Versioned, SoftDelete {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get area => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomerAccounts extends Table with Versioned {
  TextColumn get id => text()();
  TextColumn get customerId => text().unique()();
  TextColumn get cachedBalance => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Sales extends Table with Versioned, SoftDelete {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get saleNumber => text().unique()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get subtotal => text()();
  TextColumn get paidAmount => text()();
  TextColumn get remainingAmount => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get soldAt => dateTime()();
  TextColumn get createdBy => text()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get cancelledBy => text().nullable()();
  TextColumn get cancelReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get productId => text()();
  TextColumn get quantity => text()();
  TextColumn get unit => text()();
  TextColumn get unitPrice => text()();
  TextColumn get lineTotal => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Collections extends Table with Versioned, SoftDelete {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get amount => text()();
  TextColumn get paymentMethod => text()();
  DateTimeColumn get collectedAt => dateTime()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get cancelledBy => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CustomerAccountTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get customerId => text()();
  TextColumn get type => text()();
  TextColumn get amount => text()();
  TextColumn get runningBalance => text()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class InventoryMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get type => text()();
  TextColumn get quantity => text()();
  TextColumn get unit => text()();
  TextColumn get previousStock => text()();
  TextColumn get newStock => text()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get operationId => text().unique()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get status => text()();
  IntColumn get pendingCount => integer().withDefault(const Constant(0))();
  IntColumn get acceptedCount => integer().withDefault(const Constant(0))();
  IntColumn get failedCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get appVersion => text().nullable()();
  IntColumn get syncProtocolVersion => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Conflicts extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get localPayload => text()();
  TextColumn get serverPayload => text()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get resolvedBy => text().nullable()();
  TextColumn get resolution => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
