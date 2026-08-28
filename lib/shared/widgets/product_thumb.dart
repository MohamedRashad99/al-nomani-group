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
        child: url.isEmpty
            ? ColoredBox(
                color: AppColors.sand,
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: size * 0.45,
                  color: AppColors.muted,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).toInt(),
                errorBuilder: (_, _, _) => ColoredBox(
                  color: AppColors.sand,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: size * 0.45,
                    color: AppColors.muted,
                  ),
                ),
              ),
      ),
    );
  }
}
