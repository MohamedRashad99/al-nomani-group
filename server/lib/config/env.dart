import 'dart:io';
import 'dart:convert';

typedef EnvironmentFileReader = String Function(String path);

class Env {
  final String jwtSecret;
  final String databaseUrl;
  final String googleLiveSpreadsheetId;
  final String googleFullSpreadsheetId;
  final String? googleServiceAccountJson;
  final String? googleServiceAccountFile;
  final String? googleServiceAccountError;
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
    this.googleServiceAccountFile,
    this.googleServiceAccountError,
    required this.syncIntervalDays,
    required this.allowSeed,
    required this.bootstrapAdminUsername,
    required this.bootstrapAdminPassword,
    required this.databaseSsl,
  });

  factory Env.load() => Env.loadFrom(Platform.environment);

  factory Env.loadFrom(
    Map<String, String> environment, {
    EnvironmentFileReader readFile = _readFile,
  }) {
    final allowSeed = (environment['ALLOW_SEED'] ?? 'true') == 'true';
    final jwtSecret = environment['JWT_SECRET'] ?? 'dev-only-change-me';
    if (!allowSeed &&
        (jwtSecret == 'dev-only-change-me' || jwtSecret.length < 32)) {
      throw StateError(
        'JWT_SECRET must be an explicit random value of at least 32 characters in production.',
      );
    }
    final credentials = _loadGoogleCredentials(environment, readFile);
    return Env(
      jwtSecret: jwtSecret,
      databaseUrl:
          environment['DATABASE_URL'] ??
          'postgres://postgres:postgres@localhost:5432/al_nomani',
      googleLiveSpreadsheetId:
          environment['GOOGLE_LIVE_SPREADSHEET_ID'] ??
          '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I',
      googleFullSpreadsheetId: () {
        final full = environment['GOOGLE_FULL_SPREADSHEET_ID']?.trim() ?? '';
        if (full.isNotEmpty) return full;
        return environment['GOOGLE_LIVE_SPREADSHEET_ID'] ??
            '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I';
      }(),
      googleServiceAccountJson: credentials.json,
      googleServiceAccountFile: credentials.file,
      googleServiceAccountError: credentials.error,
      syncIntervalDays:
          int.tryParse(environment['SYNC_INTERVAL_DAYS'] ?? '') ?? 5,
      allowSeed: allowSeed,
      bootstrapAdminUsername: environment['BOOTSTRAP_ADMIN_USERNAME'],
      bootstrapAdminPassword: environment['BOOTSTRAP_ADMIN_PASSWORD'],
      databaseSsl: (environment['DATABASE_SSL'] ?? 'false') == 'true',
    );
  }

  static String _readFile(String path) => File(path).readAsStringSync();

  static ({String? json, String? file, String? error}) _loadGoogleCredentials(
    Map<String, String> environment,
    EnvironmentFileReader readFile,
  ) {
    final file = environment['GOOGLE_SERVICE_ACCOUNT_FILE']?.trim();
    final inlineJson = environment['GOOGLE_SERVICE_ACCOUNT_JSON']?.trim();
    String? raw;

    if (file != null && file.isNotEmpty) {
      try {
        raw = readFile(file).trim();
      } on FileSystemException {
        return (
          json: null,
          file: file,
          error:
              'تعذر قراءة ملف بيانات اعتماد Google. تحقق من وجود الملف وصلاحية القراءة.',
        );
      } catch (_) {
        return (
          json: null,
          file: file,
          error: 'تعذر تحميل ملف بيانات اعتماد Google.',
        );
      }
    } else if (inlineJson != null && inlineJson.isNotEmpty) {
      raw = inlineJson;
    }

    if (raw == null || raw.isEmpty) {
      return (json: null, file: file, error: null);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['type'] != 'service_account' ||
          decoded['client_email'] is! String ||
          decoded['private_key'] is! String) {
        return (
          json: null,
          file: file,
          error: 'بيانات اعتماد Google ليست ملف Service Account صالحاً.',
        );
      }
      return (json: raw, file: file, error: null);
    } on FormatException {
      return (
        json: null,
        file: file,
        error: 'بيانات اعتماد Google ليست JSON صالحاً.',
      );
    }
  }
}
