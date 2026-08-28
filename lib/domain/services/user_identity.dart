import '../entities/erp_models.dart';

abstract final class UserIdentity {
  static String normalizeUsername(String username) =>
      username.trim().toLowerCase();

  static bool sameUsername(String a, String b) =>
      normalizeUsername(a) == normalizeUsername(b) &&
      normalizeUsername(a).isNotEmpty;

  static int compareCanonical(AppUser a, AppUser b) {
    final aHasPassword = a.passwordHash.isNotEmpty;
    final bHasPassword = b.passwordHash.isNotEmpty;
    if (aHasPassword != bHasPassword) return aHasPassword ? -1 : 1;
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.id.compareTo(b.id);
  }

  static AppUser? pickByUsername(
    Iterable<AppUser> users,
    String username, {
    bool includeDeleted = false,
  }) {
    final matches = matchesByUsername(
      users,
      username,
      includeDeleted: includeDeleted,
    );
    if (matches.isEmpty) return null;
    matches.sort(compareCanonical);
    return matches.first;
  }

  static List<AppUser> matchesByUsername(
    Iterable<AppUser> users,
    String username, {
    bool includeDeleted = false,
  }) {
    final needle = normalizeUsername(username);
    if (needle.isEmpty) return const [];
    return [
      for (final user in users)
        if ((includeDeleted || !user.isDeleted) &&
            normalizeUsername(user.username) == needle)
          user,
    ];
  }

  static List<AppUser> collapseVisible(List<AppUser> users) {
    final grouped = <String, AppUser>{};
    final ordered = [...users]..sort(compareCanonical);
    for (final user in ordered) {
      final key = normalizeUsername(user.username);
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => user);
    }
    return grouped.values.toList();
  }
}
