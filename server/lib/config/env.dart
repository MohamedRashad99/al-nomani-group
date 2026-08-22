import 'dart:io';

class Env {
  final String jwtSecret;
  final String databaseUrl;
  final String googleLiveSpreadsheetId;
  final String googleFullSpreadsheetId;
  final String? googleServiceAccountJson;
  final int syncIntervalDays;
  final bool allowSeed;
  final String? bootstrapAdminUsername;
  final String? bootstrapAdminPassword;
  final bool databaseSsl;

  const Env({
    required this.jwtSecret,
    required this.databaseUrl,
    required this.googleLiveSpreadsheetId,
    required this.googleFullSpreadsheetId,
    required this.googleServiceAccountJson,
    required this.syncIntervalDays,
    required this.allowSeed,
    required this.bootstrapAdminUsername,
    required this.bootstrapAdminPassword,
    required this.databaseSsl,
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
          '',
      googleServiceAccountJson:
          Platform.environment['GOOGLE_SERVICE_ACCOUNT_JSON'],
      syncIntervalDays:
          int.tryParse(Platform.environment['SYNC_INTERVAL_DAYS'] ?? '') ?? 5,
      allowSeed: (Platform.environment['ALLOW_SEED'] ?? 'true') == 'true',
      bootstrapAdminUsername:
          Platform.environment['BOOTSTRAP_ADMIN_USERNAME'],
      bootstrapAdminPassword:
          Platform.environment['BOOTSTRAP_ADMIN_PASSWORD'],
      databaseSsl:
          (Platform.environment['DATABASE_SSL'] ?? 'false') == 'true',
    );
  }
}
