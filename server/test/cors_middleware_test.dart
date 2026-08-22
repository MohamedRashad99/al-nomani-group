import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:al_nomani_server/middleware/cors_middleware.dart';

void main() {
  test('OPTIONS preflight is accepted without hitting the inner handler', () async {
    var innerCalled = false;
    final handler = Pipeline()
        .addMiddleware(corsMiddleware())
        .addHandler((_) async {
          innerCalled = true;
          return Response.forbidden('no');
        });

    final response = await handler(
      Request('OPTIONS', Uri.parse('http://localhost:8080/api/v1/sync/push')),
    );

    expect(innerCalled, isFalse);
    expect(response.statusCode, 200);
    expect(response.headers['access-control-allow-origin'], '*');
    expect(
      response.headers['access-control-allow-headers'],
      contains('Authorization'),
    );
    expect(
      response.headers['access-control-allow-headers'],
      contains('Content-Type'),
    );
    expect(response.headers['access-control-allow-credentials'], isNull);
  });

  test('JSON responses include CORS headers for browser clients', () async {
    final handler = Pipeline()
        .addMiddleware(corsMiddleware())
        .addHandler(
          (_) async => Response.ok(
            '{"ok":true}',
            headers: {'content-type': 'application/json'},
          ),
        );

    final response = await handler(
      Request('POST', Uri.parse('http://localhost:8080/api/v1/sync/push')),
    );

    expect(response.statusCode, 200);
    expect(response.headers['access-control-allow-origin'], '*');
    expect(
      response.headers['access-control-allow-methods'],
      contains('POST'),
    );
  });
}
