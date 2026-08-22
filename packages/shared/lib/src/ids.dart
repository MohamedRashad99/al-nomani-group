import 'package:uuid/uuid.dart';

const uuid = Uuid();

String newId() => uuid.v4();
