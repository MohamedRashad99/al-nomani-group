import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/erp_models.dart';
import '../../domain/services/product_ai_service.dart';
import '../../domain/services/product_image_service.dart';
import 'product_thumb.dart';

class ProductImagesEditor extends StatefulWidget {
  const ProductImagesEditor({
    super.key,
    required this.productId,
    required this.images,
    required this.onChanged,
    this.onSuggestion,
  });

  final String productId;
  final List<ProductImage> images;
  final ValueChanged<List<ProductImage>> onChanged;
  final ValueChanged<ProductAiSuggestion>? onSuggestion;

  @override
  State<ProductImagesEditor> createState() => _ProductImagesEditorState();
}

class _ProductImagesEditorState extends State<ProductImagesEditor> {
  var _busy = false;
  String? _error;
  Uint8List? _lastPicked;

  Future<void> _add({required bool camera}) async {
    Uint8List? bytes;
    try {
      bytes = await _pickBytes(camera: camera);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر فتح اختيار الصورة. جرّب JPG أو PNG.');
      }
      return;
    }
    if (bytes == null || bytes.isEmpty || !mounted) return;
    _lastPicked = bytes;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await sl<ProductImageService>().upload(
        productId: widget.productId,
        bytes: bytes,
      );
      widget.onChanged([...widget.images, image]);
      if (camera && widget.onSuggestion != null && mounted) {
        await _suggest();
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'تعذر حفظ الصورة. استخدم صورة JPG أو PNG أصغر.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _pickBytes({required bool camera}) async {
    if (camera) {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      return file == null ? null : await file.readAsBytes();
    }
    if (kIsWeb) {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    return file == null ? null : await file.readAsBytes();
  }

  Future<void> _suggest() async {
    final bytes = _lastPicked;
    if (bytes == null || bytes.isEmpty) {
      setState(
        () => _error = 'اختر صورة أولاً ثم اضغط تعرّف.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final suggestion = await sl<ProductAiService>().suggestFromPhoto(bytes);
      if (!mounted) return;
      final confirmed = await showModalBottomSheet<ProductAiSuggestion>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _AiReviewSheet(suggestion: suggestion),
      );
      if (confirmed != null) widget.onSuggestion?.call(confirmed);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'التعرف الذكي غير متاح حالياً. يمكنك إدخال البيانات يدوياً.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: Text('صور المنتج'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            onReorder: (from, to) {
              final next = [...widget.images];
              if (to > from) to -= 1;
              final item = next.removeAt(from);
              next.insert(to, item);
              widget.onChanged(next);
            },
            children: [
              for (var i = 0; i < widget.images.length; i++)
                Padding(
                  key: ValueKey(widget.images[i].id),
                  padding: const EdgeInsets.only(left: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 88,
                          height: 88,
                          child: ProductImageView(
                            url: widget.images[i].displayUrl,
                            size: 88,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy
                              ? null
                              : () {
                                  final next = [...widget.images]..removeAt(i);
                                  widget.onChanged(next);
                                },
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _add(camera: false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('معرض'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _add(camera: true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('كاميرا'),
            ),
            if (widget.onSuggestion != null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _suggest,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('تعرّف'),
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
      ],
    );
  }
}

class _AiReviewSheet extends StatefulWidget {
  const _AiReviewSheet({required this.suggestion});

  final ProductAiSuggestion suggestion;

  @override
  State<_AiReviewSheet> createState() => _AiReviewSheetState();
}

class _AiReviewSheetState extends State<_AiReviewSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.suggestion.name ?? '',
  );
  late final TextEditingController _brand = TextEditingController(
    text: widget.suggestion.brand ?? '',
  );
  late final TextEditingController _pack = TextEditingController(
    text: widget.suggestion.packSize ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.suggestion.description ?? widget.suggestion.visibleText ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _pack.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('راجع اقتراح التعرف قبل الحفظ'),
          if (widget.suggestion.category != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('التصنيف: ${widget.suggestion.category}'),
            ),
          if (widget.suggestion.closestMatches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'أقرب منتجات: ${widget.suggestion.closestMatches.join(' • ')}',
              ),
            ),
          if (widget.suggestion.lowConfidence)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'الثقة منخفضة — عدّل الحقول قبل التأكيد.',
                style: TextStyle(color: AppColors.orange),
              ),
            ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          TextField(
            controller: _brand,
            decoration: const InputDecoration(labelText: 'العلامة'),
          ),
          TextField(
            controller: _pack,
            decoration: const InputDecoration(labelText: 'الحجم / العبوة'),
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'الوصف'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              ProductAiSuggestion(
                name: _name.text.trim(),
                brand: _brand.text.trim(),
                packSize: _pack.text.trim(),
                description: _description.text.trim(),
                confidence: widget.suggestion.confidence,
              ),
            ),
            child: const Text('تطبيق الاقتراح'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
