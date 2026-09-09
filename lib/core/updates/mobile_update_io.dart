import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../firebase/firebase_bootstrap.dart';
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

Future<MobileUpdateInfo?> checkMobileUpdate({bool forceFetch = false}) async {
  final offer = await AndroidUpdateService().check(forceFetch: forceFetch);
  if (offer == null) return null;
  return MobileUpdateInfo(
    latestVersionName: offer.latestVersion,
    latestVersionCode: offer.latestBuild,
    updateUrl: offer.apkUrl,
    notes: offer.message,
    forceUpdate: offer.forceUpdate,
  );
}

class AndroidDownloadProgress {
  const AndroidDownloadProgress({required this.received, required this.total});

  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
}

enum AndroidInstallOutcome { started, needsPermission }

class AndroidUpdateService {
  AndroidUpdateService({
    Dio? downloader,
    DateTime Function()? clock,
  }) : _downloader =
           downloader ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(minutes: 10),
               followRedirects: true,
               headers: const {'Accept': '*/*'},
             ),
           ),
       _clock = clock ?? DateTime.now;

  static const _channel = MethodChannel('al_nomani_group/apk_install');
  static const _autoCooldown = Duration(seconds: 20);

  final Dio _downloader;
  final DateTime Function() _clock;
  DateTime? _lastAutoCheckAt;
  CancelToken? _cancel;
  var _downloading = false;
  String? _readyPath;
  StreamSubscription<RemoteConfigUpdate>? _liveSub;

  void listenForLiveUpdates(void Function() onChanged) {
    if (!Platform.isAndroid || _liveSub != null) return;
    unawaited(_startLiveUpdates(onChanged));
  }

  Future<void> _startLiveUpdates(void Function() onChanged) async {
    if (!await FirebaseBootstrap.ensure()) return;
    _liveSub ??= FirebaseRemoteConfig.instance.onConfigUpdated.listen((_) async {
      try {
        await FirebaseRemoteConfig.instance.activate();
      } catch (_) {}
      onChanged();
    });
  }

  Future<AndroidUpdateOffer?> check({bool forceFetch = false}) async {
    if (!Platform.isAndroid) return null;
    final skipNetwork =
        !forceFetch &&
        _lastAutoCheckAt != null &&
        _clock().difference(_lastAutoCheckAt!) < _autoCooldown;
    if (!skipNetwork) _lastAutoCheckAt = _clock();
    return _readOffer(fetch: !skipNetwork);
  }

  Future<AndroidUpdateOffer?> _readOffer({
    required bool fetch,
  }) async {
    if (!await FirebaseBootstrap.ensure()) return null;
    final remote = FirebaseRemoteConfig.instance;
    await remote.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: Duration.zero,
      ),
    );
    await remote.setDefaults(const {
      'latest_version': '',
      'latest_build': 0,
      'apk_url': '',
      'minimum_supported_build': 0,
      'force_update': false,
      'update_title': '',
      'update_message': '',
      'apk_sha256': '',
      'android_latest_version_code': 0,
      'android_latest_version_name': '',
      'android_update_url': '',
      'android_update_notes': '',
      'android_force_update': false,
    });
    try {
      await remote.activate();
    } catch (_) {}
    if (fetch) {
      try {
        await remote.fetchAndActivate();
      } catch (_) {
        // Keep the last activated template. Offline must not block the app.
      }
    }
    PackageInfo installed;
    try {
      installed = await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
    final currentBuild = int.tryParse(installed.buildNumber) ?? 0;
    return AndroidUpdatePolicy.evaluate(
      installedBuild: currentBuild,
      installedVersion: installed.version,
      remote: AndroidRemoteValues.fromKeys(
        (key) => _remoteText(remote, key),
      ),
    );
  }

  static String _remoteText(FirebaseRemoteConfig remote, String key) {
    final text = remote.getString(key).trim();
    if (text.isNotEmpty) return text;
    final number = remote.getInt(key);
    if (number != 0) return '$number';
    if (remote.getBool(key)) return 'true';
    return '';
  }

  Stream<AndroidDownloadProgress> download(AndroidUpdateOffer offer) {
    final controller = StreamController<AndroidDownloadProgress>();
    unawaited(_runDownload(offer, controller));
    return controller.stream;
  }

  Future<void> _runDownload(
    AndroidUpdateOffer offer,
    StreamController<AndroidDownloadProgress> controller,
  ) async {
    if (!Platform.isAndroid) {
      await controller.close();
      return;
    }
    if (_downloading) {
      controller.addError(StateError('يتم تنزيل التحديث بالفعل.'));
      await controller.close();
      return;
    }
    if (!AndroidUpdatePolicy.isHttpsApkUrl(offer.apkUrl)) {
      controller.addError(const FormatException('رابط التحديث غير آمن.'));
      await controller.close();
      return;
    }
    _downloading = true;
    _cancel = CancelToken();
    _readyPath = null;
    try {
      final dir = await _updateDir();
      await _deleteIncomplete(dir);
      final part = File(p.join(dir.path, 'update.apk.part'));
      final target = File(p.join(dir.path, 'update.apk'));
      if (await target.exists()) {
        await target.delete();
      }
      controller.add(const AndroidDownloadProgress(received: 0, total: 0));
      await _downloader.download(
        offer.apkUrl,
        part.path,
        cancelToken: _cancel,
        onReceiveProgress: (received, total) {
          if (!controller.isClosed) {
            controller.add(
              AndroidDownloadProgress(received: received, total: total),
            );
          }
        },
      );
      if (!await part.exists() || await part.length() < 1024) {
        throw const FormatException('ملف التحديث غير مكتمل.');
      }
      final header = await part.openRead(0, 2).first;
      if (header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
        await part.delete();
        throw const FormatException('ملف التحديث تالف.');
      }
      if (offer.sha256.isNotEmpty) {
        final digest = (await sha256.bind(part.openRead()).single).toString();
        if (!AndroidUpdatePolicy.checksumMatches(offer.sha256, digest)) {
          await part.delete();
          throw const FormatException('فشل التحقق من ملف التحديث.');
        }
      }
      await part.rename(target.path);
      _readyPath = target.path;
      final size = await target.length();
      if (!controller.isClosed) {
        controller.add(AndroidDownloadProgress(received: size, total: size));
      }
    } catch (error, stack) {
      if (!controller.isClosed) {
        controller.addError(error, stack);
      }
    } finally {
      _downloading = false;
      _cancel = null;
      await controller.close();
    }
  }

  Future<String?> preparedApkPath() async => _readyPath;

  Future<AndroidInstallOutcome> install(String path) async {
    if (!Platform.isAndroid) return AndroidInstallOutcome.started;
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('ملف التحديث غير موجود.');
    }
    final canInstall =
        await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!canInstall) {
      await _channel.invokeMethod<void>('openInstallSettings');
      return AndroidInstallOutcome.needsPermission;
    }
    await _channel.invokeMethod<void>('install', {'path': path});
    return AndroidInstallOutcome.started;
  }

  void cancelDownload() {
    _cancel?.cancel('cancelled');
  }

  Future<Directory> _updateDir() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, 'updates'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _deleteIncomplete(Directory dir) async {
    final part = File(p.join(dir.path, 'update.apk.part'));
    if (await part.exists()) {
      await part.delete();
    }
  }
}
