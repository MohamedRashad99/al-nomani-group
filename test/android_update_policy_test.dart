import 'package:al_nomani_group/core/updates/android_update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AndroidRemoteValues values({
    String latestVersion = '1.0.5',
    int latestBuild = 6,
    String apkUrl = 'https://example.com/app.apk',
    int minimumSupportedBuild = 0,
    bool forceUpdate = false,
    String title = '',
    String message = '',
    String sha256 = '',
  }) {
    return AndroidRemoteValues(
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      apkUrl: apkUrl,
      minimumSupportedBuild: minimumSupportedBuild,
      forceUpdate: forceUpdate,
      title: title,
      message: message,
      sha256: sha256,
    );
  }

  test('newer build offers an optional update', () {
    final offer = AndroidUpdatePolicy.evaluate(
      installedBuild: 5,
      installedVersion: '1.0.4',
      remote: values(),
    );
    expect(offer, isNotNull);
    expect(offer!.forceUpdate, isFalse);
    expect(offer.latestVersion, '1.0.5');
    expect(offer.currentVersion, '1.0.4');
    expect(offer.apkUrl, 'https://example.com/app.apk');
  });

  test('same or older remote build is never offered', () {
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 6,
        installedVersion: '1.0.5',
        remote: values(latestBuild: 6),
      ),
      isNull,
    );
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 7,
        installedVersion: '1.0.6',
        remote: values(latestBuild: 6),
      ),
      isNull,
    );
  });

  test('http urls are rejected', () {
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 5,
        installedVersion: '1.0.4',
        remote: values(apkUrl: 'http://example.com/app.apk'),
      ),
      isNull,
    );
  });

  test('newer latest_version is enough when latest_build is omitted', () {
    final offer = AndroidUpdatePolicy.evaluate(
      installedBuild: 5,
      installedVersion: '1.0.4',
      remote: values(latestVersion: '1.6.0', latestBuild: 0),
    );
    expect(offer, isNotNull);
    expect(offer!.latestVersion, '1.6.0');
    expect(offer.latestLabel, '1.6.0');
    expect(offer.currentLabel, '1.0.4 (5)');
  });

  test('same version name without a newer build is not offered', () {
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 5,
        installedVersion: '1.0.4',
        remote: values(latestVersion: '1.0.4', latestBuild: 0),
      ),
      isNull,
    );
  });

  test('older remote build is never offered even if version name is higher', () {
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 7,
        installedVersion: '1.0.4',
        remote: values(latestVersion: '1.6.0', latestBuild: 6),
      ),
      isNull,
    );
  });

  test('compareVersions orders dotted releases', () {
    expect(AndroidUpdatePolicy.compareVersions('1.6.0', '1.0.4'), greaterThan(0));
    expect(AndroidUpdatePolicy.compareVersions('1.0.4', '1.0.4'), 0);
    expect(AndroidUpdatePolicy.compareVersions('1.0.3', '1.0.4'), lessThan(0));
  });

  test('force_update or min build makes the update mandatory', () {
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 5,
        installedVersion: '1.0.4',
        remote: values(forceUpdate: true),
      )!.forceUpdate,
      isTrue,
    );
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 4,
        installedVersion: '1.0.3',
        remote: values(minimumSupportedBuild: 5),
      )!.forceUpdate,
      isTrue,
    );
    expect(
      AndroidUpdatePolicy.evaluate(
        installedBuild: 5,
        installedVersion: '1.0.4',
        remote: values(minimumSupportedBuild: 5),
      )!.forceUpdate,
      isFalse,
    );
  });

  test('legacy android_* remote keys still map', () {
    final remote = AndroidRemoteValues.fromKeys((key) {
      return switch (key) {
        'android_latest_version_name' => '1.0.5',
        'android_latest_version_code' => '8',
        'android_update_url' => 'https://cdn.example/app.apk',
        'android_update_notes' => 'إصلاحات',
        'android_force_update' => 'true',
        _ => '',
      };
    });
    final offer = AndroidUpdatePolicy.evaluate(
      installedBuild: 5,
      installedVersion: '1.0.4',
      remote: remote,
    );
    expect(offer, isNotNull);
    expect(offer!.latestBuild, 8);
    expect(offer.forceUpdate, isTrue);
    expect(offer.message, 'إصلاحات');
  });

  test('preferred remote keys win over legacy names', () {
    final remote = AndroidRemoteValues.fromKeys((key) {
      return switch (key) {
        'latest_version' => '1.6.0',
        'latest_build' => '16',
        'apk_url' => 'https://firebasestorage.googleapis.com/v0/b/app/o/a.apk',
        'minimum_supported_build' => '15',
        'force_update' => 'false',
        'update_title' => 'تحديث جديد متاح',
        'update_message' => 'يوجد إصدار جديد من التطبيق.',
        'android_latest_version_code' => '1',
        'android_update_url' => 'http://legacy.example/old.apk',
        _ => '',
      };
    });
    final offer = AndroidUpdatePolicy.evaluate(
      installedBuild: 15,
      installedVersion: '1.5.0',
      remote: remote,
    );
    expect(offer, isNotNull);
    expect(offer!.latestVersion, '1.6.0');
    expect(offer.latestBuild, 16);
    expect(offer.forceUpdate, isFalse);
    expect(offer.apkUrl.contains('firebasestorage'), isTrue);
  });

  test('checksum is optional and case-insensitive', () {
    expect(AndroidUpdatePolicy.checksumMatches('', 'abc'), isTrue);
    expect(AndroidUpdatePolicy.checksumMatches('AbC', 'abc'), isTrue);
    expect(AndroidUpdatePolicy.checksumMatches('abc', 'def'), isFalse);
  });
}
