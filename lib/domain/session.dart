class AppSession {
  final String userId;
  final String username;
  final String displayName;
  final String roleName;
  final Set<String> permissions;
  final DateTime expiresAt;
  final bool isOfflineVerified;

  const AppSession({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.roleName,
    required this.permissions,
    required this.expiresAt,
    required this.isOfflineVerified,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool can(String permission) => permissions.contains(permission);

  AppSession copyWith({Set<String>? permissions}) {
    return AppSession(
      userId: userId,
      username: username,
      displayName: displayName,
      roleName: roleName,
      permissions: permissions ?? this.permissions,
      expiresAt: expiresAt,
      isOfflineVerified: isOfflineVerified,
    );
  }
}
