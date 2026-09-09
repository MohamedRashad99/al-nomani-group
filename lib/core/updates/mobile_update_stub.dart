import 'android_update_policy.dart';

export 'android_update_policy.dart';

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

Future<MobileUpdateInfo?> checkMobileUpdate({bool forceFetch = false}) async =>
    null;

class AndroidDownloadProgress {
  const AndroidDownloadProgress({required this.received, required this.total});

  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
}

enum AndroidInstallOutcome { started, needsPermission }

class AndroidUpdateService {
  Future<AndroidUpdateOffer?> check({bool forceFetch = false}) async => null;

  Stream<AndroidDownloadProgress> download(AndroidUpdateOffer offer) {
    return const Stream.empty();
  }

  Future<String?> preparedApkPath() async => null;

  Future<AndroidInstallOutcome> install(String path) async {
    return AndroidInstallOutcome.started;
  }

  void cancelDownload() {}
}
