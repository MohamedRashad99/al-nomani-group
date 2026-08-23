class FirebaseActor {
  final String userId;
  final String username;
  final String displayName;
  final String roleId;

  const FirebaseActor({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.roleId,
  });

  static const empty = FirebaseActor(
    userId: '',
    username: '',
    displayName: '',
    roleId: '',
  );

  bool get isKnown => userId.isNotEmpty;

  Map<String, dynamic> toFields() => {
    'erpUserId': userId,
    'erpUsername': username,
    'erpDisplayName': displayName,
    'erpRole': roleId,
  };
}
