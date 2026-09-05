import 'dart:io';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../firebase/firebase_bootstrap.dart';

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

Future<MobileUpdateInfo?> checkMobileUpdate() async {
  if (!Platform.isAndroid) return null;
  if (!await FirebaseBootstrap.ensure()) return null;
  final remote = FirebaseRemoteConfig.instance;
  await remote.setConfigSettings(
    RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 8),
      minimumFetchInterval: const Duration(hours: 1),
    ),
  );
  await remote.setDefaults(const {
    'android_latest_version_code': 0,
    'android_latest_version_name': '',
    'android_update_url': '',
    'android_update_notes': '',
    'android_force_update': false,
  });
  try {
    await remote.fetchAndActivate();
  } catch (_) {
    return null;
  }
  final latestCode = remote.getInt('android_latest_version_code');
  final latestName = remote.getString('android_latest_version_name');
  final url = remote.getString('android_update_url');
  if (latestCode <= 0 || url.isEmpty) return null;
  final installed = await PackageInfo.fromPlatform();
  final currentCode = int.tryParse(installed.buildNumber) ?? 0;
  if (currentCode >= latestCode) return null;
  return MobileUpdateInfo(
    latestVersionName: latestName.isEmpty ? installed.version : latestName,
    latestVersionCode: latestCode,
    updateUrl: url,
    notes: remote.getString('android_update_notes'),
    forceUpdate: remote.getBool('android_force_update'),
  );
}
