import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import 'arabic_workbook_builder.dart';

class GoogleSheetsLiveSync {
  GoogleSheetsLiveSync(this._workbook, this._config, this._dio);

  final ArabicWorkbookBuilder _workbook;
  final AppConfig _config;
  final Dio _dio;

  static const _bridgeUrl = 'http://127.0.0.1:8765/sheets/write';

  Future<({bool ok, String message})> pushAll() async {
    final spreadsheetId = _config.googleLiveSpreadsheetId;
    if (spreadsheetId.isEmpty) {
      return (ok: false, message: 'معرّف Google Sheet غير مضبوط.');
    }
    final sections = await _workbook.build();
    final payload = {
      'spreadsheetId': spreadsheetId,
      'sections': {
        for (final entry in sections.entries)
          entry.key: [
            for (final row in entry.value)
              [for (final value in row) value?.toString() ?? ''],
          ],
      },
    };
    try {
      await _writeDirect(spreadsheetId, payload['sections'] as Map<String, dynamic>);
      return (ok: true, message: 'تم تحديث Google Sheets مباشرة.');
    } catch (directError) {
      debugPrint('Direct Sheets write failed: $directError');
      try {
        await _dio.post<Map<String, dynamic>>(
          _bridgeUrl,
          data: payload,
          options: Options(
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(minutes: 2),
          ),
        );
        return (ok: true, message: 'تم تحديث Google Sheets مباشرة.');
      } catch (bridgeError) {
        return (
          ok: false,
          message:
              'تعذر تحديث Google Sheets. $directError',
        );
      }
    }
  }

  Future<void> _writeDirect(
    String spreadsheetId,
    Map<String, dynamic> sections,
  ) async {
    final accessToken = await _accessToken();
    final headers = {'Authorization': 'Bearer $accessToken'};
    final base =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId';
    final meta = await _dio.get<Map<String, dynamic>>(
      base,
      options: Options(headers: headers),
    );
    final existing = <String>{
      for (final sheet in (meta.data?['sheets'] as List?) ?? const [])
        if (sheet is Map && sheet['properties'] is Map)
          '${(sheet['properties'] as Map)['title']}',
    };
    final add = [
      for (final tab in sections.keys)
        if (!existing.contains(tab))
          {
            'addSheet': {
              'properties': {'title': tab},
            },
          },
    ];
    if (add.isNotEmpty) {
      await _dio.post<Map<String, dynamic>>(
        '$base:batchUpdate',
        data: {'requests': add},
        options: Options(headers: headers),
      );
    }
    for (final entry in sections.entries) {
      final range = "'${entry.key}'!A:ZZ";
      await _dio.post<Map<String, dynamic>>(
        '$base/values/${Uri.encodeComponent(range)}:clear',
        data: const {},
        options: Options(headers: headers),
      );
      await _dio.put<Map<String, dynamic>>(
        '$base/values/${Uri.encodeComponent(range)}',
        queryParameters: {'valueInputOption': 'RAW'},
        data: {'values': entry.value},
        options: Options(headers: headers),
      );
    }
  }

  Future<String> _accessToken() async {
    final raw = await _serviceAccountJson();
    final email = raw['client_email'] as String? ?? '';
    final privateKey = raw['private_key'] as String? ?? '';
    if (email.isEmpty || privateKey.isEmpty) {
      throw StateError('ملف حساب خدمة Google Sheets غير مكتمل.');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT({
      'iss': email,
      'scope': 'https://www.googleapis.com/auth/spreadsheets',
      'aud': 'https://oauth2.googleapis.com/token',
      'iat': now,
      'exp': now + 3500,
    });
    final assertion = jwt.sign(
      RSAPrivateKey(privateKey),
      algorithm: JWTAlgorithm.RS256,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      'https://oauth2.googleapis.com/token',
      data: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final token = response.data?['access_token'] as String? ?? '';
    if (token.isEmpty) {
      throw StateError('رفضت Google رمز الكتابة إلى Sheets.');
    }
    return token;
  }

  Future<Map<String, dynamic>> _serviceAccountJson() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/config/google_sheets_sa.json',
      );
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw StateError(
        'أضف ملف حساب الخدمة إلى assets/config/google_sheets_sa.json',
      );
    }
  }
}
