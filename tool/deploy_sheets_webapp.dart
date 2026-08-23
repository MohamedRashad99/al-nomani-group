import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dio/dio.dart';

/// Creates or updates the Apps Script web app that writes the live spreadsheet.
Future<void> main() async {
  final saFile = File('assets/config/google_sheets_sa.json');
  if (!saFile.existsSync()) {
    stderr.writeln('Missing assets/config/google_sheets_sa.json');
    exitCode = 1;
    return;
  }
  final sa = jsonDecode(saFile.readAsStringSync()) as Map<String, dynamic>;
  final email = sa['client_email'] as String? ?? '';
  final privateKey = sa['private_key'] as String? ?? '';
  final projectId = sa['project_id'] as String? ?? '';
  final source = File('tool/sheets_webapp.gs').readAsStringSync();
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<String> token(String scope) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT({
      'iss': email,
      'scope': scope,
      'aud': 'https://oauth2.googleapis.com/token',
      'iat': now,
      'exp': now + 3500,
    });
    final assertion = jwt.sign(
      RSAPrivateKey(privateKey),
      algorithm: JWTAlgorithm.RS256,
    );
    final response = await dio.post<Map<String, dynamic>>(
      'https://oauth2.googleapis.com/token',
      data: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return response.data?['access_token'] as String? ?? '';
  }

  final access = await token(
    [
      'https://www.googleapis.com/auth/script.projects',
      'https://www.googleapis.com/auth/script.deployments',
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive',
      'https://www.googleapis.com/auth/cloud-platform',
    ].join(' '),
  );
  if (access.isEmpty) {
    stderr.writeln('Failed to mint service-account token');
    exitCode = 1;
    return;
  }
  final headers = {'Authorization': 'Bearer $access'};

  if (projectId.isNotEmpty) {
    final enabled = await dio.post<Map<String, dynamic>>(
      'https://serviceusage.googleapis.com/v1/projects/$projectId/services/script.googleapis.com:enable',
      options: Options(
        headers: headers,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    stdout.writeln('Enable Apps Script API: ${enabled.statusCode}');
  }

  final created = await dio.post<Map<String, dynamic>>(
    'https://script.googleapis.com/v1/projects',
    data: {
      'title': 'al-nomani-sheets-writer',
      'parentId': '1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I',
    },
    options: Options(
      headers: headers,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  stdout.writeln('Create project: ${created.statusCode} ${created.data}');
  var scriptId = created.data?['scriptId'] as String? ?? '';
  if (scriptId.isEmpty) {
    final standalone = await dio.post<Map<String, dynamic>>(
      'https://script.googleapis.com/v1/projects',
      data: {'title': 'al-nomani-sheets-writer'},
      options: Options(
        headers: headers,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    stdout.writeln(
      'Create standalone: ${standalone.statusCode} ${standalone.data}',
    );
    scriptId = standalone.data?['scriptId'] as String? ?? '';
  }
  if (scriptId.isEmpty) {
    exitCode = 1;
    return;
  }

  final content = await dio.put<Map<String, dynamic>>(
    'https://script.googleapis.com/v1/projects/$scriptId/content',
    data: {
      'files': [
        {
          'name': 'appsscript',
          'type': 'JSON',
          'source': jsonEncode({
            'timeZone': 'Africa/Cairo',
            'exceptionLogging': 'STACKDRIVER',
            'runtimeVersion': 'V8',
            'webapp': {
              'executeAs': 'USER_DEPLOYING',
              'access': 'ANYONE_ANONYMOUS',
            },
            'oauthScopes': [
              'https://www.googleapis.com/auth/spreadsheets',
              'https://www.googleapis.com/auth/script.external_request',
            ],
          }),
        },
        {'name': 'Code', 'type': 'SERVER_JS', 'source': source},
      ],
    },
    options: Options(
      headers: headers,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  stdout.writeln('Update content: ${content.statusCode}');

  final version = await dio.post<Map<String, dynamic>>(
    'https://script.googleapis.com/v1/projects/$scriptId/versions',
    data: {'description': 'Live Arabic sheet writer'},
    options: Options(
      headers: headers,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  stdout.writeln('Create version: ${version.statusCode} ${version.data}');
  final versionNumber = version.data?['versionNumber'] as int? ?? 1;

  final deployment = await dio.post<Map<String, dynamic>>(
    'https://script.googleapis.com/v1/projects/$scriptId/deployments',
    data: {
      'versionNumber': versionNumber,
      'description': 'Anyone can POST workbook JSON',
      'manifestFileName': 'appsscript',
    },
    options: Options(
      headers: headers,
      validateStatus: (status) => status != null && status < 500,
    ),
  );
  stdout.writeln(
    'Create deployment: ${deployment.statusCode} ${jsonEncode(deployment.data)}',
  );
}
