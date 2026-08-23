import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> downloadBytes(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
}) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'حفظ الملف',
    fileName: filename,
    bytes: bytes,
  );
}
