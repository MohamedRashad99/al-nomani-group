import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../../core/errors/app_exception.dart';
import '../../core/firebase/firebase_bootstrap.dart';

class ProductAiSuggestion {
  const ProductAiSuggestion({
    this.name,
    this.brand,
    this.description,
    this.visibleText,
    this.packSize,
    this.confidence = 0,
  });

  final String? name;
  final String? brand;
  final String? description;
  final String? visibleText;
  final String? packSize;
  final double confidence;

  bool get lowConfidence => confidence > 0 && confidence < 0.55;
}

class ProductAiService {
  Future<ProductAiSuggestion> suggestFromPhoto(Uint8List bytes) async {
    if (!await FirebaseBootstrap.ensure()) {
      throw const ValidationException(
        'التعرف الذكي غير مفعّل على هذا المشروع. يمكنك إدخال البيانات يدوياً.',
      );
    }
    try {
      final model = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: Schema.object(
            properties: {
              'name': Schema.string(),
              'brand': Schema.string(),
              'description': Schema.string(),
              'visibleText': Schema.string(),
              'packSize': Schema.string(),
              'confidence': Schema.number(),
            },
          ),
        ),
      );
      final response = await model.generateContent([
        Content.multi([
          const TextPart(
            'Extract agricultural product fields from this photo. '
            'Return JSON with name, brand, description, visibleText, packSize, '
            'and confidence from 0 to 1. Use Arabic when the label is Arabic.',
          ),
          InlineDataPart('image/jpeg', bytes),
        ]),
      ]);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        throw const ValidationException(
          'لم يتمكن التعرف الذكي من قراءة الصورة. أكمل الحقول يدوياً.',
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const ValidationException(
          'استجابة التعرف الذكي غير صالحة. أكمل الحقول يدوياً.',
        );
      }
      final map = Map<String, dynamic>.from(decoded);
      return ProductAiSuggestion(
        name: _text(map, 'name'),
        brand: _text(map, 'brand'),
        description: _text(map, 'description'),
        visibleText: _text(map, 'visibleText'),
        packSize: _text(map, 'packSize'),
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      );
    } on ValidationException {
      rethrow;
    } catch (_) {
      throw const ValidationException(
        'التعرف الذكي غير متاح حالياً. يمكنك إدخال بيانات المنتج يدوياً.',
      );
    }
  }

  String? _text(Map<String, dynamic> map, String key) {
    final value = '${map[key] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }
}
