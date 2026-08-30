import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../../core/di/injector.dart';
import '../../core/errors/app_exception.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import 'product_label.dart';
import 'product_label_recognizer.dart';

class ProductAiSuggestion {
  const ProductAiSuggestion({
    this.name,
    this.brand,
    this.description,
    this.visibleText,
    this.packSize,
    this.confidence = 0,
    this.category,
    this.productType,
    this.closestMatches = const [],
  });

  final String? name;
  final String? brand;
  final String? description;
  final String? visibleText;
  final String? packSize;
  final double confidence;
  final String? category;
  final String? productType;
  final List<String> closestMatches;

  bool get lowConfidence => confidence > 0 && confidence < 0.55;
}

class ProductAiService {
  Future<ProductAiSuggestion> suggestFromPhoto(Uint8List bytes) async {
    final labels = await recognizeProductLabels(bytes);
    final mapped = _mapLabels(labels);
    final matches = await _closestCatalogMatches(labels, mapped.category);
    final offline = ProductAiSuggestion(
      name: matches.isEmpty ? mapped.productType : matches.first,
      description: mapped.category == null
          ? null
          : 'تصنيف مقترح: ${mapped.category}',
      visibleText: labels.map((label) => label.text).take(6).join(' • '),
      confidence: mapped.confidence,
      category: mapped.category,
      productType: mapped.productType,
      closestMatches: matches,
    );

    final cloud = await _suggestFromGemini(bytes);
    if (cloud == null) {
      if (offline.category == null &&
          offline.closestMatches.isEmpty &&
          (offline.visibleText == null || offline.visibleText!.isEmpty)) {
        throw const ValidationException(
          'التعرف الذكي غير متاح حالياً. يمكنك إدخال بيانات المنتج يدوياً.',
        );
      }
      return offline;
    }
    return ProductAiSuggestion(
      name: cloud.name ?? offline.name,
      brand: cloud.brand,
      description: cloud.description ?? offline.description,
      visibleText: cloud.visibleText ?? offline.visibleText,
      packSize: cloud.packSize,
      confidence: cloud.confidence > 0 ? cloud.confidence : offline.confidence,
      category: offline.category,
      productType: offline.productType,
      closestMatches: offline.closestMatches,
    );
  }

  Future<ProductAiSuggestion?> _suggestFromGemini(Uint8List bytes) async {
    if (!await FirebaseBootstrap.ensure()) return null;
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
      if (text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return ProductAiSuggestion(
        name: _text(map, 'name'),
        brand: _text(map, 'brand'),
        description: _text(map, 'description'),
        visibleText: _text(map, 'visibleText'),
        packSize: _text(map, 'packSize'),
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  String? _text(Map<String, dynamic> map, String key) {
    final value = '${map[key] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }
}

({String? category, String? productType, double confidence}) _mapLabels(
  List<ProductLabel> labels,
) {
  if (labels.isEmpty) {
    return (category: null, productType: null, confidence: 0);
  }
  var bestConfidence = 0.0;
  String? category;
  String? productType;
  for (final label in labels) {
    if (label.confidence > bestConfidence) {
      bestConfidence = label.confidence;
      productType ??= label.text;
    }
    final mapped = _categoryFor(label.text);
    if (mapped != null && category == null) {
      category = mapped;
      productType = label.text;
      bestConfidence = label.confidence;
    }
  }
  return (
    category: category,
    productType: productType ?? labels.first.text,
    confidence: bestConfidence,
  );
}

String? _categoryFor(String raw) {
  final text = raw.toLowerCase();
  const fertilizer = [
    'fertilizer',
    'compost',
    'manure',
    'npk',
    'urea',
    'سماد',
    'أسمدة',
    'يوريا',
  ];
  const nutrient = [
    'nutrient',
    'micronutrient',
    'humic',
    'feed',
    'مغذي',
    'مغذيات',
    'هيوميك',
  ];
  const insect = [
    'insecticide',
    'pesticide',
    'insect',
    'bug',
    'حشر',
    'مبيد حشر',
  ];
  const fungus = ['fungicide', 'fungus', 'mold', 'فطر', 'فطري'];
  const herb = ['herbicide', 'weed', 'أعشاب', 'عشب', 'جليفوس'];
  if (fertilizer.any(text.contains)) return CatalogCategories.all[0].name;
  if (nutrient.any(text.contains)) return CatalogCategories.all[1].name;
  if (insect.any(text.contains)) return CatalogCategories.all[2].name;
  if (fungus.any(text.contains)) return CatalogCategories.all[3].name;
  if (herb.any(text.contains)) return CatalogCategories.all[4].name;
  return null;
}

Future<List<String>> _closestCatalogMatches(
  List<ProductLabel> labels,
  String? category,
) async {
  if (!sl.isRegistered<ErpStore>()) return const [];
  try {
    final products = await sl<ErpStore>().listProducts();
    if (products.isEmpty) return const [];
    final needles = [
      for (final label in labels) label.text.toLowerCase(),
      if (category != null) category.toLowerCase(),
    ];
    final scored = <({String name, int score})>[];
    for (final product in products) {
      final name = product.name.toLowerCase();
      var score = 0;
      for (final needle in needles) {
        if (needle.isEmpty) continue;
        if (name.contains(needle) || needle.contains(name)) score += 2;
        for (final part in needle.split(RegExp(r'\s+'))) {
          if (part.length >= 3 && name.contains(part)) score += 1;
        }
      }
      if (score > 0) scored.add((name: product.name, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final row in scored.take(3)) row.name];
  } catch (_) {
    return const [];
  }
}
