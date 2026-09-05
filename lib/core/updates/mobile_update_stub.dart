class MobileUpdateInfo {
  const MobileUpdateInfo({
    required this.latestVersionName,
    required this.latestVersionCode,
    required this.updateUrl,
    required this.notes,
    required this.forceUpdate,
  });

  final String latestVersionName;
  final int latestVersionCode;
  final String updateUrl;
  final String notes;
  final bool forceUpdate;
}

Future<MobileUpdateInfo?> checkMobileUpdate() async => null;
