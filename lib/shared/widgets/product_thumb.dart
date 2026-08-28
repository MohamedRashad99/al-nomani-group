import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/erp_models.dart';

class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.product, this.size = 44});

  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = product.images.isEmpty ? '' : product.images.first.displayUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: ProductImageView(url: url, size: size),
      ),
    );
  }
}

class ProductImageView extends StatelessWidget {
  const ProductImageView({super.key, required this.url, this.size});

  final String url;
  final double? size;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return ColoredBox(
        color: AppColors.sand,
        child: Icon(
          Icons.inventory_2_outlined,
          size: (size ?? 44) * 0.45,
          color: AppColors.muted,
        ),
      );
    }
    final memory = _memoryBytes(url);
    if (memory != null) {
      return Image.memory(
        memory,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _broken(size),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: size == null ? null : (size! * 3).toInt(),
      filterQuality: FilterQuality.low,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const ColoredBox(
          color: AppColors.sand,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => _broken(size),
    );
  }
}

Widget _broken(double? size) {
  return ColoredBox(
    color: AppColors.sand,
    child: Icon(
      Icons.broken_image_outlined,
      size: (size ?? 44) * 0.45,
      color: AppColors.muted,
    ),
  );
}

Uint8List? _memoryBytes(String url) {
  const prefix = 'data:image/';
  if (!url.startsWith(prefix)) return null;
  final comma = url.indexOf(',');
  if (comma < 0 || comma == url.length - 1) return null;
  try {
    return base64Decode(url.substring(comma + 1));
  } catch (_) {
    return null;
  }
}
