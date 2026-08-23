import 'dart:convert';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/services.dart';

class AppConfig {
  final String environment;
  final String apiBaseUrl;
  final int syncIntervalDays;
  final SyncMode syncMode;
  final bool allowSeed;
  final String googleLiveSpreadsheetId;
  final String googleSheetsWebappUrl;
  final String googleSheetsWriteToken;
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
    this.googleSheetsWebappUrl = '',
    this.googleSheetsWriteToken = '',
    required this.appVersion,
    required this.databaseVersion,
    required this.syncProtocolVersion,
  });

  bool get isDevelopment => environment != 'production';

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final environment = json['environment'] as String? ?? 'development';
    final apiBaseUrl =
        json['api_base_url'] as String? ?? 'http://localhost:8080';
    final allowSeed = json['allow_seed'] as bool? ?? false;
    if (environment == 'production' &&
        (allowSeed ||
            apiBaseUrl.contains('localhost') ||
            apiBaseUrl.contains('example.com'))) {
      throw const FormatException(
        'إعدادات الإنتاج غير آمنة: اضبط عنوان API وأوقف البيانات التجريبية.',
      );
    }
    final modeRaw = json['sync_mode'] as String? ?? 'scheduled';
    return AppConfig(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      syncIntervalDays:
          json['sync_interval_days'] as int? ??
          SyncDefaults.productionIntervalDays,
      syncMode: modeRaw == 'near_realtime'
          ? SyncMode.nearRealtime
          : SyncMode.scheduled,
      allowSeed: allowSeed,
      googleLiveSpreadsheetId:
          json['google_live_spreadsheet_id'] as String? ?? '',
      googleSheetsWebappUrl:
          json['google_sheets_webapp_url'] as String? ?? '',
      googleSheetsWriteToken:
          json['google_sheets_write_token'] as String? ?? '',
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
      throw StateError(
        'تعذر تحميل إعدادات التشغيل. تم إيقاف البدء لتجنب الاتصال ببيئة خاطئة: $e',
      );
    }
  }
}
