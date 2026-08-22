import 'package:al_nomani_server/config/env.dart';
import 'package:test/test.dart';

void main() {
  test('loads service account from file before inline json', () {
    final env = Env.loadFrom(
      {
        'GOOGLE_SERVICE_ACCOUNT_FILE': '/tmp/google.json',
        'GOOGLE_SERVICE_ACCOUNT_JSON': '{"type":"not-used"}',
      },
      readFile: (_) => '''
{
  "type": "service_account",
  "client_email": "backup@example.iam.gserviceaccount.com",
  "private_key": "-----BEGIN PRIVATE KEY-----\\ntest\\n-----END PRIVATE KEY-----\\n"
}
''',
    );

    expect(env.googleServiceAccountFile, '/tmp/google.json');
    expect(env.googleServiceAccountJson, contains('backup@example'));
    expect(env.googleServiceAccountError, isNull);
  });

  test('uses the live spreadsheet for a full dump when no second file is set', () {
    final env = Env.loadFrom({
      'GOOGLE_LIVE_SPREADSHEET_ID':
          '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I',
    });

    expect(env.googleFullSpreadsheetId, env.googleLiveSpreadsheetId);
    expect(
      env.googleFullSpreadsheetId,
      '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I',
    );
  });

  test('reports a readable Arabic error for invalid credentials', () {
    final env = Env.loadFrom({
      'GOOGLE_SERVICE_ACCOUNT_JSON': '{"type":"user"}',
    });

    expect(env.googleServiceAccountJson, isNull);
    expect(env.googleServiceAccountError, contains('Service Account'));
  });
}
