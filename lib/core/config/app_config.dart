import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppConfig {
  final String environment;
  final String apiBaseUrl;
  final int syncIntervalDays;
  final SyncMode syncMode;
  final bool allowSeed;
  final String googleLiveSpreadsheetId;
  final String appVersion;
  final int databaseVersion;
  final int syncProtocolVersion;

  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.syncIntervalDays,
    required this.syncMode,
    required this.allowSeed,
    required this.googleLiveSpreadsheetId,
    required this.appVersion,
    required this.databaseVersion,
    required this.syncProtocolVersion,
  });

  bool get isDevelopment => environment != 'production';

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final modeRaw = json['sync_mode'] as String? ?? 'scheduled';
    return AppConfig(
      environment: json['environment'] as String? ?? 'development',
      apiBaseUrl: json['api_base_url'] as String? ?? 'http://localhost:8080',
      syncIntervalDays:
          json['sync_interval_days'] as int? ??
          SyncDefaults.productionIntervalDays,
      syncMode: modeRaw == 'near_realtime'
          ? SyncMode.nearRealtime
          : SyncMode.scheduled,
      allowSeed: json['allow_seed'] as bool? ?? false,
      googleLiveSpreadsheetId:
          json['google_live_spreadsheet_id'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? AppVersions.appVersion,
      databaseVersion:
          json['database_version'] as int? ?? AppVersions.databaseVersion,
      syncProtocolVersion:
          json['sync_protocol_version'] as int? ??
          AppVersions.syncProtocolVersion,
    );
  }

  static Future<AppConfig> load() async {
    try {
      final raw = await rootBundle.loadString('assets/config/app_config.json');
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('تعذر تحميل الإعدادات، سيتم استخدام القيم الافتراضية الآمنة.');
      return const AppConfig(
        environment: 'development',
        apiBaseUrl: 'http://localhost:8080',
        syncIntervalDays: SyncDefaults.productionIntervalDays,
        syncMode: SyncMode.nearRealtime,
        allowSeed: true,
        googleLiveSpreadsheetId: '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I',
        appVersion: AppVersions.appVersion,
        databaseVersion: AppVersions.databaseVersion,
        syncProtocolVersion: AppVersions.syncProtocolVersion,
      );
    }
  }
}
