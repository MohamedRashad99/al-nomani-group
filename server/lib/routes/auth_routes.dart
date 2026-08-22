import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/auth_service.dart';

class AuthRoutes {
  AuthRoutes(this.auth);
  final AuthService auth;

  Router get router => Router()
    ..post('/login', (Request request) async {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      try {
        final result = await auth.login(
          body['username'] as String? ?? '',
          body['password'] as String? ?? '',
        );
        return Response.ok(
          jsonEncode(result),
          headers: {'content-type': 'application/json'},
        );
      } catch (_) {
        return Response(
          401,
          body: jsonEncode({'error': 'اسم المستخدم أو كلمة المرور غير صحيحة.'}),
          headers: {'content-type': 'application/json'},
        );
      }
    });
}
