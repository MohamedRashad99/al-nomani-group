import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import 'product_label.dart';

Future<List<ProductLabel>> recognizeProductLabels(Uint8List bytes) async {
  if (bytes.isEmpty || (!Platform.isAndroid && !Platform.isIOS)) {
    return const [];
  }
  final file = File(
    '${Directory.systemTemp.path}/nomani_label_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  final labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.45),
  );
  try {
    await file.writeAsBytes(bytes, flush: true);
    final labels = await labeler.processImage(InputImage.fromFilePath(file.path));
    return [
      for (final label in labels)
        ProductLabel(text: label.label, confidence: label.confidence),
    ];
  } catch (_) {
    return const [];
  } finally {
    await labeler.close();
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
