class AppException implements Exception {
  final String messageAr;
  final String code;
  final Object? cause;

  const AppException(this.messageAr, {this.code = 'app_error', this.cause});

  @override
  String toString() => messageAr;
}

class ValidationException extends AppException {
  const ValidationException(super.messageAr, {super.code = 'validation'});
}

class PermissionException extends AppException {
  const PermissionException()
      : super('ليست لديك صلاحية لتنفيذ هذه العملية.', code: 'permission_denied');
}

class MigrationException extends AppException {
  const MigrationException(super.messageAr, {super.cause}) : super(code: 'migration_failed');
}

class SyncException extends AppException {
  const SyncException(super.messageAr, {super.cause}) : super(code: 'sync_error');
}
