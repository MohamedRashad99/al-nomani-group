import 'package:shelf/shelf.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

/// Browser Flutter/Dio sends JSON + Authorization, which always triggers an
/// OPTIONS preflight. Answer it here so auth never sees OPTIONS, and never send
/// `Access-Control-Allow-Credentials: true` with `*`.
Middleware corsMiddleware() {
  const headers = {
    ACCESS_CONTROL_ALLOW_ORIGIN: '*',
    ACCESS_CONTROL_ALLOW_METHODS: 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    ACCESS_CONTROL_ALLOW_HEADERS:
        'Origin, Content-Type, Accept, Authorization, X-Requested-With',
    ACCESS_CONTROL_EXPOSE_HEADERS: 'Content-Type, Authorization',
    ACCESS_CONTROL_MAX_AGE: '86400',
  };
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: headers);
      }
      final response = await inner(request);
      return response.change(headers: headers);
    };
  };
}
