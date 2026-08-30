// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> pickWebCameraImage() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false;
  input.setAttribute('capture', 'environment');
  final done = Completer<Uint8List?>();
  late StreamSubscription<html.Event> change;
  change = input.onChange.listen((_) async {
    await change.cancel();
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      if (!done.isCompleted) done.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final result = reader.result;
    if (result is ByteBuffer) {
      if (!done.isCompleted) done.complete(Uint8List.view(result));
    } else if (result is Uint8List) {
      if (!done.isCompleted) done.complete(result);
    } else if (!done.isCompleted) {
      done.complete(null);
    }
  });
  Timer(const Duration(seconds: 45), () {
    if (!done.isCompleted) done.complete(null);
  });
  html.document.body?.append(input);
  input.click();
  final bytes = await done.future;
  input.remove();
  return bytes;
}
