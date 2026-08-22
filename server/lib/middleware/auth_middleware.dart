import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../services/auth_service.dart';

Middleware authMiddleware(AuthService auth) {
  return (Handler inner) {
    return (Request request) async {
      final header = request.headers['authorization'];
      if (header == null || !header.startsWith('Bearer ')) {
        return Response.forbidden(
          jsonEncode({'error': 'غير مصرح'}),
          headers: {'content-type': 'application/json'},
        );
      }
      try {
        final user = auth.verify(header.substring(7));
        return await inner(request.change(context: {'user': user}));
      } catch (_) {
        return Response.forbidden(
          jsonEncode({'error': 'جلسة غير صالحة'}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  };
}
