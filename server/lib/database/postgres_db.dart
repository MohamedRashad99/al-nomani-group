import 'dart:io';

import 'package:postgres/postgres.dart';

import '../config/env.dart';

class PostgresDb {
  PostgresDb(this.env);
  final Env env;
  late final Connection connection;

  Future<void> open() async {
    final uri = Uri.parse(
      env.databaseUrl.replaceFirst('postgres://', 'http://'),
    );
    connection = await Connection.open(
      Endpoint(
        host: uri.host,
        port: uri.port == 0 ? 5432 : uri.port,
        database: uri.path.replaceFirst('/', ''),
        username: uri.userInfo.split(':').first,
        password: uri.userInfo.split(':').skip(1).join(':'),
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
  }

  Future<void> migrate() async {
    final file = File('database/migrations/001_init.sql');
    final alt = File('../database/migrations/001_init.sql');
    final sql = await (file.existsSync() ? file : alt).readAsString();
    final statements = sql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('--'));
    for (final statement in statements) {
      await connection.execute(Sql('$statement;'));
    }
  }

  Future<Result> query(String sql, {Map<String, dynamic>? params}) {
    return connection.execute(Sql.named(sql), parameters: params ?? const {});
  }

  Future<T> transaction<T>(Future<T> Function(TxSession tx) action) {
    return connection.runTx((tx) => action(tx));
  }
}
