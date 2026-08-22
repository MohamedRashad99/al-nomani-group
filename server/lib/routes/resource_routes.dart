import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../database/postgres_db.dart';

class ResourceRoutes {
  ResourceRoutes(this.db);
  final PostgresDb db;

  Router get router => Router()
    ..get('/products', (Request request) async {
      final rows = await db.query(
        'SELECT id, name, sku, selling_price, current_stock FROM products WHERE is_deleted = FALSE ORDER BY name',
      );
      return Response.ok(
        jsonEncode({
          'items': rows
              .map(
                (r) => {
                  'id': r[0],
                  'name': r[1],
                  'sku': r[2],
                  'selling_price': r[3].toString(),
                  'current_stock': r[4].toString(),
                },
              )
              .toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });
}
