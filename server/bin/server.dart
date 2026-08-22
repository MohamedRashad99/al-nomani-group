import 'dart:io';

import 'package:al_nomani_server/app.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await createServer(port: port);
  stdout.writeln('Al Nomani ERP API listening on port ${server.port}');
}
