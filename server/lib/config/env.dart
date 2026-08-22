import 'dart:io';

class Env {
  final String jwtSecret;
  final String databaseUrl;
  final String googleLiveSpreadsheetId;
  final String googleFullSpreadsheetId;
  final String? googleServiceAccountJson;
  final int syncIntervalDays;
  final bool allowSeed;

  const Env({
    required this.jwtSecret,
    required this.databaseUrl,
    required this.googleLiveSpreadsheetId,
    required this.googleFullSpreadsheetId,
    required this.googleServiceAccountJson,
    required this.syncIntervalDays,
    required this.allowSeed,
  });

  factory Env.load() {
    return Env(
      jwtSecret: Platform.environment['JWT_SECRET'] ?? 'dev-only-change-me',
      databaseUrl:
          Platform.environment['DATABASE_URL'] ??
          'postgres://postgres:postgres@localhost:5432/al_nomani',
      googleLiveSpreadsheetId:
          Platform.environment['GOOGLE_LIVE_SPREADSHEET_ID'] ??
          '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I',
      googleFullSpreadsheetId:
          Platform.environment['GOOGLE_FULL_SPREADSHEET_ID'] ??
          Platform.environment['GOOGLE_LIVE_SPREADSHEET_ID'] ??
          '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I',
      googleServiceAccountJson:
          Platform.environment['GOOGLE_SERVICE_ACCOUNT_JSON'],
      syncIntervalDays:
          int.tryParse(Platform.environment['SYNC_INTERVAL_DAYS'] ?? '') ?? 5,
      allowSeed: (Platform.environment['ALLOW_SEED'] ?? 'true') == 'true',
    );
  }
}
