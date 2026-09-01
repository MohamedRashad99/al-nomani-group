import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/utils/image_mime.dart';
import 'product_label.dart';

Future<List<ProductLabel>> recognizeProductLabels(Uint8List bytes) async {
  if (bytes.isEmpty || (!Platform.isAndroid && !Platform.isIOS)) {
    return const [];
  }
  final ext = imageMimeOf(bytes) == 'image/png' ? 'png' : 'jpg';
  final file = File(
    '${Directory.systemTemp.path}/nomani_label_${DateTime.now().microsecondsSinceEpoch}.$ext',
  );
  final labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.45),
  );
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    await file.writeAsBytes(bytes, flush: true);
    final input = InputImage.fromFilePath(file.path);
    final ocr = await textRecognizer.processImage(input);
    final labels = await labeler.processImage(input);
    final ocrText = ocr.text.trim();
    return [
      if (ocrText.isNotEmpty)
        ProductLabel(text: ocrText, confidence: 0.9),
      for (final label in labels)
        ProductLabel(text: label.label, confidence: label.confidence),
    ];
  } catch (_) {
    return const [];
  } finally {
    await labeler.close();
    await textRecognizer.close();
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
