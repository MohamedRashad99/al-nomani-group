class AndroidRemoteValues {
  const AndroidRemoteValues({
    required this.latestVersion,
    required this.latestBuild,
    required this.apkUrl,
    required this.minimumSupportedBuild,
    required this.forceUpdate,
    required this.title,
    required this.message,
    this.sha256 = '',
  });

  final String latestVersion;
  final int latestBuild;
  final String apkUrl;
  final int minimumSupportedBuild;
  final bool forceUpdate;
  final String title;
  final String message;
  final String sha256;

  /// Reads the requested Remote Config names first, then the older android_* keys.
  factory AndroidRemoteValues.fromKeys(String Function(String key) text) {
    bool flag(String key) {
      final raw = text(key).trim().toLowerCase();
      return raw == 'true' || raw == '1';
    }

    int number(String key) => int.tryParse(text(key).trim()) ?? 0;

    final latestVersion = _firstNonEmpty(text, const [
      'latest_version',
      'android_latest_version_name',
    ]);
    final apkUrl = _firstNonEmpty(text, const [
      'apk_url',
      'android_update_url',
    ]);
    final title = _firstNonEmpty(text, const ['update_title']);
    final message = _firstNonEmpty(text, const [
      'update_message',
      'android_update_notes',
    ]);
    return AndroidRemoteValues(
      latestVersion: latestVersion,
      latestBuild: _firstPositive(number, const [
        'latest_build',
        'android_latest_version_code',
      ]),
      apkUrl: apkUrl,
      minimumSupportedBuild: number('minimum_supported_build'),
      forceUpdate: flag('force_update') || flag('android_force_update'),
      title: title,
      message: message,
      sha256: text('apk_sha256').trim(),
    );
  }

  static String _firstNonEmpty(
    String Function(String key) text,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = text(key).trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static int _firstPositive(int Function(String key) number, List<String> keys) {
    for (final key in keys) {
      final value = number(key);
      if (value > 0) return value;
    }
    return 0;
  }
}

class AndroidUpdateOffer {
  const AndroidUpdateOffer({
    required this.latestVersion,
    required this.latestBuild,
    required this.currentVersion,
    required this.currentBuild,
    required this.apkUrl,
    required this.forceUpdate,
    required this.title,
    required this.message,
    this.sha256 = '',
  });

  final String latestVersion;
  final int latestBuild;
  final String currentVersion;
  final int currentBuild;
  final String apkUrl;
  final bool forceUpdate;
  final String title;
  final String message;
  final String sha256;

  String get currentLabel => _label(currentVersion, currentBuild);
  String get latestLabel => _label(latestVersion, latestBuild);

  static String _label(String version, int build) {
    if (version.isEmpty) return build > 0 ? '$build' : '';
    return build > 0 ? '$version ($build)' : version;
  }
}

abstract final class AndroidUpdatePolicy {
  static const defaultTitle = 'تحديث جديد متاح';
  static const defaultMessage = 'يوجد إصدار جديد من التطبيق.';

  static bool isHttpsApkUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static bool checksumMatches(String expected, String actual) {
    final want = expected.trim().toLowerCase();
    if (want.isEmpty) return true;
    return want == actual.trim().toLowerCase();
  }

  /// Compares dotted versions such as `1.0.4` and `1.6.0`.
  static int compareVersions(String left, String right) {
    List<int> parts(String raw) {
      final core = raw.trim().split(RegExp(r'[-+]')).first;
      if (core.isEmpty) return const [0];
      return [
        for (final piece in core.split('.')) int.tryParse(piece) ?? 0,
      ];
    }

    final a = parts(left);
    final b = parts(right);
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  /// Returns null when there is no newer compatible update (including downgrades).
  static AndroidUpdateOffer? evaluate({
    required int installedBuild,
    required String installedVersion,
    required AndroidRemoteValues remote,
  }) {
    if (!isHttpsApkUrl(remote.apkUrl)) return null;
    if (remote.latestBuild > 0 && remote.latestBuild < installedBuild) {
      return null;
    }
    final buildNewer = remote.latestBuild > installedBuild;
    final versionNewer =
        remote.latestVersion.isNotEmpty &&
        compareVersions(remote.latestVersion, installedVersion) > 0;
    if (!buildNewer && !versionNewer) return null;
    if (!buildNewer &&
        versionNewer &&
        remote.latestBuild > 0 &&
        remote.latestBuild == installedBuild) {
      return null;
    }
    final force =
        remote.forceUpdate ||
        (remote.minimumSupportedBuild > 0 &&
            installedBuild < remote.minimumSupportedBuild);
    return AndroidUpdateOffer(
      latestVersion: remote.latestVersion.isEmpty
          ? installedVersion
          : remote.latestVersion,
      latestBuild: remote.latestBuild,
      currentVersion: installedVersion,
      currentBuild: installedBuild,
      apkUrl: remote.apkUrl.trim(),
      forceUpdate: force,
      title: remote.title.isEmpty ? defaultTitle : remote.title,
      message: remote.message.isEmpty ? defaultMessage : remote.message,
      sha256: remote.sha256,
    );
  }
}
