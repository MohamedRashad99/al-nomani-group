import 'package:flutter/material.dart';

import 'app.dart';
import 'core/utils/egypt_time.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EgyptTime.initialize();
  runApp(const AlNomaniApp());
}
