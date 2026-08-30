// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'product_label.dart';

Future<List<ProductLabel>> recognizeProductLabels(Uint8List bytes) async {
  if (bytes.isEmpty) return const [];
  try {
    await _ensureScript();
    final requestId = 'nomani-tf-${DateTime.now().microsecondsSinceEpoch}';
    final host = html.DivElement()
      ..id = requestId
      ..style.display = 'none';
    html.document.body?.append(host);
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    final ready = host.on['nomani-ready'].first;
    final runner = html.ScriptElement()
      ..text =
          'nomaniClassifyImage(${jsonEncode(dataUrl)}).then(function(preds){'
          'var el=document.getElementById("$requestId");'
          'if(!el)return;'
          'el.setAttribute("data-result", JSON.stringify(preds));'
          'el.dispatchEvent(new Event("nomani-ready"));'
          '}).catch(function(){'
          'var el=document.getElementById("$requestId");'
          'if(!el)return;'
          'el.setAttribute("data-result","[]");'
          'el.dispatchEvent(new Event("nomani-ready"));'
          '});';
    html.document.body?.append(runner);
    await ready.timeout(const Duration(seconds: 20));
    runner.remove();
    final raw = host.getAttribute('data-result') ?? '[]';
    host.remove();
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map)
          ProductLabel(
            text: '${item['text'] ?? ''}',
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
          ),
    ].where((label) => label.text.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
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
  await loaded.future.timeout(const Duration(seconds: 12));
}
