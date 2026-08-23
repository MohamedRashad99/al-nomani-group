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
      settings: ConnectionSettings(
        sslMode: env.databaseSsl ? SslMode.require : SslMode.disable,
      ),
    );
  }

  Future<void> migrate() async {
    final primary = Directory('database/migrations');
    final alternate = Directory('../database/migrations');
    final directory = primary.existsSync() ? primary : alternate;
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final sql = await file.readAsString();
      final withoutComments = sql
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n');
      final statements = withoutComments
          .split(';')
          .map((statement) => statement.trim())
          .where((statement) => statement.isNotEmpty);
      for (final statement in statements) {
        await connection.execute(Sql('$statement;'));
      }
    }
  }

  Future<Result> query(String sql, {Map<String, dynamic>? params}) {
    return connection.execute(Sql.named(sql), parameters: params ?? const {});
  }

  Future<T> transaction<T>(Future<T> Function(TxSession tx) action) {
    return connection.runTx((tx) => action(tx));
  }
}
