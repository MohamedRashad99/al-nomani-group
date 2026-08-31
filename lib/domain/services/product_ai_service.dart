import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../../core/di/injector.dart';
import '../../core/errors/app_exception.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/utils/image_mime.dart';
import '../../data/remote/erp_store.dart';
import '../entities/erp_models.dart';
import 'inventory_measure.dart';
import 'product_label.dart';
import 'product_label_recognizer.dart';

class ProductAiSuggestion {
  const ProductAiSuggestion({
    this.name,
    this.brand,
    this.description,
    this.visibleText,
    this.packSize,
    this.packageSize,
    this.unitOfMeasure,
    this.packageType,
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
  final String? packageSize;
  final String? unitOfMeasure;
  final String? packageType;
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
    final ocrText = labels.map((label) => label.text).join('\n');
    final parsedPack = PackingParser.parse(ocrText);
    final matches = await _closestCatalogMatches(labels, mapped.category);
    final offline = ProductAiSuggestion(
      name: matches.isEmpty ? mapped.productType : matches.first,
      description: mapped.category == null
          ? null
          : 'تصنيف مقترح: ${mapped.category}',
      visibleText: ocrText.trim().isEmpty
          ? null
          : ocrText.split('\n').take(8).join(' • '),
      packSize: parsedPack == null
          ? null
          : '${parsedPack.size.toDisplay()} ${parsedPack.unit.symbol}',
      packageSize: parsedPack?.size.toDisplay(),
      unitOfMeasure: parsedPack?.unit.code,
      packageType: parsedPack?.packageType,
      confidence: mapped.confidence,
      category: mapped.category,
      productType: mapped.productType,
      closestMatches: matches,
    );

    final cloud = await _suggestFromGemini(bytes, ocrText: ocrText);
    if (cloud == null) {
      if (offline.category == null &&
          offline.closestMatches.isEmpty &&
          (offline.visibleText == null || offline.visibleText!.isEmpty) &&
          offline.packageSize == null) {
        throw const ValidationException(
          'التعرف الذكي غير متاح حالياً. يمكنك إدخال بيانات المنتج يدوياً.',
        );
      }
      return offline;
    }
    final cloudPack = PackingParser.parse(
      [
        cloud.packSize,
        cloud.visibleText,
        if (cloud.packageSize != null && cloud.unitOfMeasure != null)
          '${cloud.packageSize} ${cloud.unitOfMeasure}',
      ].whereType<String>().join(' '),
    );
    return ProductAiSuggestion(
      name: _prefer(cloud.name, offline.name),
      brand: cloud.brand,
      description: cloud.description ?? offline.description,
      visibleText: cloud.visibleText ?? offline.visibleText,
      packSize: cloud.packSize ?? offline.packSize,
      packageSize:
          cloud.packageSize ??
          cloudPack?.size.toDisplay() ??
          offline.packageSize,
      unitOfMeasure:
          cloud.unitOfMeasure ?? cloudPack?.unit.code ?? offline.unitOfMeasure,
      packageType:
          cloud.packageType ?? cloudPack?.packageType ?? offline.packageType,
      confidence: cloud.confidence > 0 ? cloud.confidence : offline.confidence,
      category: offline.category,
      productType: offline.productType,
      closestMatches: offline.closestMatches,
    );
  }

  String? _prefer(String? primary, String? fallback) {
    final value = primary?.trim() ?? '';
    if (value.isEmpty) return fallback;
    return value;
  }

  Future<ProductAiSuggestion?> _suggestFromGemini(
    Uint8List bytes, {
    String ocrText = '',
  }) async {
    if (!await FirebaseBootstrap.ensure()) return null;
    final mime = imageMimeOf(bytes);
    final sendImage = bytes.isNotEmpty &&
        bytes.length < 3500000 &&
        !isProbablyHeic(bytes);
    const models = ['gemini-2.5-flash', 'gemini-2.0-flash'];
    for (final modelName in models) {
      try {
        final model = FirebaseAI.googleAI().generativeModel(
          model: modelName,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: Schema.object(
              properties: {
                'name': Schema.string(),
                'brand': Schema.string(),
                'description': Schema.string(),
                'visibleText': Schema.string(),
                'packSize': Schema.string(),
                'packageSize': Schema.string(),
                'unitOfMeasure': Schema.string(),
                'packageType': Schema.string(),
                'confidence': Schema.number(),
              },
            ),
          ),
        );
        final parts = <Part>[
          TextPart(
            'You are reading an agricultural product photo for an Egyptian farm-supply shop.\n'
            'Extract the product name, brand, description, every readable label line, '
            'numeric package size, unit of measure (ml, l, kg, g, pcs), and package type '
            '(عبوة, شكارة, كيس, صفيحة, جالون, كرتونة).\n'
            'Use Arabic when the label is Arabic.\n'
            'packageSize must be a number only, like 250 or 50.\n'
            'unitOfMeasure must be one of ml, l, kg, g, pcs.\n'
            'If OCR text is provided, treat it as the label transcript.\n'
            '${ocrText.trim().isEmpty ? '' : 'OCR transcript:\n$ocrText'}',
          ),
          if (sendImage) InlineDataPart(mime, bytes),
        ];
        if (parts.length == 1 && ocrText.trim().isEmpty) return null;
        final response = await model.generateContent([Content.multi(parts)]);
        final text = response.text?.trim() ?? '';
        if (text.isEmpty) continue;
        final decoded = jsonDecode(text);
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);
        return ProductAiSuggestion(
          name: _text(map, 'name'),
          brand: _text(map, 'brand'),
          description: _text(map, 'description'),
          visibleText: _text(map, 'visibleText'),
          packSize: _text(map, 'packSize'),
          packageSize: _text(map, 'packageSize'),
          unitOfMeasure: _text(map, 'unitOfMeasure'),
          packageType: _text(map, 'packageType'),
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
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
      productType ??= label.text.split('•').first.trim();
    }
    final mapped = _categoryFor(label.text);
    if (mapped != null && category == null) {
      category = mapped;
      productType = label.text.split('•').first.trim();
      bestConfidence = label.confidence;
    }
  }
  return (
    category: category,
    productType: productType ?? labels.first.text.split('•').first.trim(),
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
