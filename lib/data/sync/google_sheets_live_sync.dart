import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import 'arabic_workbook_builder.dart';
import 'firebase_sync_service.dart';

class GoogleSheetsLiveSync {
  GoogleSheetsLiveSync(this._workbook, this._config, Dio _);

  final ArabicWorkbookBuilder _workbook;
  final AppConfig _config;
  final Dio _plainDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 2),
      followRedirects: true,
      maxRedirects: 8,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  static const _bridgeUrl = 'http://127.0.0.1:8765/sheets/write';

  Future<({bool ok, String message})> pushAll() async {
    final spreadsheetId = _config.googleLiveSpreadsheetId;
    if (spreadsheetId.isEmpty) {
      return (ok: false, message: 'معرّف Google Sheet غير مضبوط.');
    }
    final sections = await _workbook.build();
    final payload = {
      'spreadsheetId': spreadsheetId,
      'token': _config.googleSheetsWriteToken,
      'sections': {
        for (final entry in sections.entries)
          entry.key: [
            for (final row in entry.value)
              [for (final value in row) value?.toString() ?? ''],
          ],
      },
    };
    final errors = <String>[];

    if (_config.googleSheetsWebappUrl.isNotEmpty) {
      try {
        await _writeWebapp(payload);
        return (ok: true, message: 'تم تحديث Google Sheets مباشرة.');
      } catch (error) {
        debugPrint('Sheets webapp write failed: $error');
        errors.add('$error');
      }
    }

    try {
      await _queueFirestoreTabs(payload['sections'] as Map<String, dynamic>);
      return (ok: true, message: 'تم إرسال البيانات لتحديث Google Sheets.');
    } catch (error) {
      debugPrint('Sheets Firestore queue failed: $error');
      errors.add('$error');
    }

    if (!kIsWeb) {
      try {
        await _writeDirect(
          spreadsheetId,
          payload['sections'] as Map<String, dynamic>,
        );
        return (ok: true, message: 'تم تحديث Google Sheets مباشرة.');
      } catch (directError) {
        debugPrint('Direct Sheets write failed: $directError');
        errors.add('$directError');
      }

      try {
        await _plainDio.post<Map<String, dynamic>>(
          _bridgeUrl,
          data: payload,
          options: Options(
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(minutes: 2),
          ),
        );
        return (ok: true, message: 'تم تحديث Google Sheets مباشرة.');
      } catch (bridgeError) {
        debugPrint('Sheets bridge write failed: $bridgeError');
        errors.add('$bridgeError');
      }
    }

    return (
      ok: false,
      message: 'تعذر تحديث Google Sheets. أعد المحاولة بعد اتصال الإنترنت.',
    );
  }

  Future<void> _queueFirestoreTabs(Map<String, dynamic> sections) async {
    if (!await FirebaseBootstrap.ensure()) {
      throw StateError(
        FirebaseBootstrap.lastError ?? 'Firebase غير جاهز لورقة Google.',
      );
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('لا يوجد مستخدم Firebase لكتابة الورقة.');
    }
    final tabs = FirebaseFirestore.instance
        .collection('companies')
        .doc(FirebaseSyncService.companyId)
        .collection('sheet_tabs');
    var batch = FirebaseFirestore.instance.batch();
    var pending = 0;
    for (final entry in sections.entries) {
      final slug = _tabSlug(entry.key);
      batch.set(tabs.doc(slug), {
        'operationId': 'sheet-tab-$slug',
        'operation': 'update',
        'version': 1,
        'deviceId': 'sheet-export',
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
        'tab': entry.key,
        'valuesJson': jsonEncode(entry.value),
      });
      pending++;
      if (pending >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        pending = 0;
      }
    }
    if (pending > 0) {
      await batch.commit();
    }
  }

  static String _tabSlug(String title) {
    const slugs = {
      'نظرة عامة': 'overview',
      'التصنيفات': 'categories',
      'المنتجات': 'products',
      'العملاء': 'customers',
      'المبالغ الآجلة': 'outstanding',
      'حركات الآجل': 'account_transactions',
      'المبيعات': 'sales',
      'بنود المبيعات': 'sale_items',
      'التحصيلات': 'collections',
      'المخزون': 'inventory',
      'المستخدمون': 'users',
      'الإعدادات': 'settings',
      'سجل العمليات': 'audit_logs',
      'سجل المزامنة': 'sync_logs',
      'الأدوار': 'roles',
    };
    return slugs[title] ?? 'tab-${title.hashCode.abs()}';
  }

  Future<void> _writeWebapp(Map<String, dynamic> payload) async {
    final response = await _plainDio.post<dynamic>(
      _config.googleSheetsWebappUrl,
      data: jsonEncode(payload),
      options: Options(
        contentType: 'text/plain;charset=utf-8',
        responseType: ResponseType.plain,
        headers: const <String, dynamic>{},
      ),
    );
    final body = response.data?.toString() ?? '';
    if (body.contains('"ok":false') || body.contains('"ok": false')) {
      throw StateError('رفضت خدمة Google Sheets الكتابة.');
    }
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw StateError('تعذر الوصول لخدمة Google Sheets ($status).');
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
    final meta = await _plainDio.get<Map<String, dynamic>>(
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
      await _plainDio.post<Map<String, dynamic>>(
        '$base:batchUpdate',
        data: {'requests': add},
        options: Options(headers: headers),
      );
    }
    for (final entry in sections.entries) {
      final range = "'${entry.key}'!A:ZZ";
      await _plainDio.post<Map<String, dynamic>>(
        '$base/values/${Uri.encodeComponent(range)}:clear',
        data: const {},
        options: Options(headers: headers),
      );
      await _plainDio.put<Map<String, dynamic>>(
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
    final response = await _plainDio.post<Map<String, dynamic>>(
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
