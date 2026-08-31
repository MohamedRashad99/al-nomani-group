// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import '../../core/utils/image_mime.dart';
import 'product_label.dart';

Future<List<ProductLabel>> recognizeProductLabels(Uint8List bytes) async {
  final result = await recognizeProductPhoto(bytes);
  return result.labels;
}

class WebPhotoRead {
  const WebPhotoRead({
    required this.labels,
    required this.jpegBytes,
    this.ocrText = '',
    this.packageSize,
    this.unitOfMeasure,
  });

  final List<ProductLabel> labels;
  final Uint8List jpegBytes;
  final String ocrText;
  final String? packageSize;
  final String? unitOfMeasure;
}

Future<WebPhotoRead> recognizeProductPhoto(Uint8List bytes) async {
  if (bytes.isEmpty) {
    return WebPhotoRead(labels: const [], jpegBytes: bytes);
  }
  try {
    await _ensureScript();
    final jpeg = await _toJpeg(bytes);
    final requestId = 'nomani-tf-${DateTime.now().microsecondsSinceEpoch}';
    final host = html.DivElement()
      ..id = requestId
      ..style.display = 'none';
    html.document.body?.append(host);
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    final ready = host.on['nomani-ready'].first;
    final runner = html.ScriptElement()
      ..text =
          'nomaniReadProductImage(${jsonEncode(dataUrl)}).then(function(result){'
          'var el=document.getElementById("$requestId");'
          'if(!el)return;'
          'el.setAttribute("data-result", JSON.stringify(result||{}));'
          'el.dispatchEvent(new Event("nomani-ready"));'
          '}).catch(function(){'
          'var el=document.getElementById("$requestId");'
          'if(!el)return;'
          'el.setAttribute("data-result","{}");'
          'el.dispatchEvent(new Event("nomani-ready"));'
          '});';
    html.document.body?.append(runner);
    await ready.timeout(const Duration(seconds: 55));
    runner.remove();
    final raw = host.getAttribute('data-result') ?? '{}';
    host.remove();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return WebPhotoRead(labels: const [], jpegBytes: jpeg);
    }
    final map = Map<String, dynamic>.from(decoded);
    final labelsRaw = map['labels'];
    final labels = <ProductLabel>[
      if (labelsRaw is List)
        for (final item in labelsRaw)
          if (item is Map)
            ProductLabel(
              text: '${item['text'] ?? ''}',
              confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            ),
    ].where((label) => label.text.trim().isNotEmpty).toList();
    final ocr = '${map['text'] ?? ''}'.trim();
    final size = '${map['packageSize'] ?? ''}'.trim();
    final unit = '${map['unitOfMeasure'] ?? ''}'.trim();
    return WebPhotoRead(
      labels: labels,
      jpegBytes: jpeg,
      ocrText: ocr,
      packageSize: size.isEmpty ? null : size,
      unitOfMeasure: unit.isEmpty ? null : unit,
    );
  } catch (_) {
    return WebPhotoRead(labels: const [], jpegBytes: bytes);
  }
}

Future<Uint8List> _toJpeg(Uint8List bytes) async {
  if (isProbablyHeic(bytes)) return bytes;
  final mime = imageMimeOf(bytes);
  final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
  final image = html.ImageElement();
  final loaded = Completer<void>();
  image.onLoad.listen((_) {
    if (!loaded.isCompleted) loaded.complete();
  });
  image.onError.listen((_) {
    if (!loaded.isCompleted) loaded.completeError(StateError('image'));
  });
  image.src = dataUrl;
  try {
    await loaded.future.timeout(const Duration(seconds: 8));
  } catch (_) {
    return bytes;
  }
  var width = image.naturalWidth;
  var height = image.naturalHeight;
  if (width <= 0 || height <= 0) return bytes;
  const max = 1600;
  if (width > max || height > max) {
    final scale = max / (width > height ? width : height);
    width = (width * scale).round();
    height = (height * scale).round();
  }
  final canvas = html.CanvasElement(width: width, height: height);
  canvas.context2D.drawImageScaled(image, 0, 0, width, height);
  final jpegUrl = canvas.toDataUrl('image/jpeg', 0.88);
  final comma = jpegUrl.indexOf(',');
  if (comma < 0) return bytes;
  return base64Decode(jpegUrl.substring(comma + 1));
}

Future<void> _ensureScript() async {
  if (html.document.querySelector('script[data-nomani-tf]') != null) return;
  final loaded = Completer<void>();
  final script = html.ScriptElement()
    ..src = 'tf_label.js'
    ..async = true;
  script.setAttribute('data-nomani-tf', '1');
  script.onLoad.listen((_) {
    if (!loaded.isCompleted) loaded.complete();
  });
  script.onError.listen((_) {
    if (!loaded.isCompleted) {
      loaded.completeError(StateError('tf_label'));
    }
  });
  html.document.head?.append(script);
  await loaded.future.timeout(const Duration(seconds: 20));
}
