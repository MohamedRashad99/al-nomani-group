import 'dart:typed_data';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

import '../../core/errors/app_exception.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../entities/erp_models.dart';

class ProductImageService {
  static const _companyId = 'al_nomani';

  Future<ProductImage> upload({
    required String productId,
    required Uint8List bytes,
  }) async {
    if (!await FirebaseBootstrap.ensure()) {
      throw const ValidationException(
        'تعذر رفع الصورة لأن الاتصال بـ Firebase غير جاهز.',
      );
    }
    final compressed = _compressImage(bytes);
    final imageId = newId();
    final base = 'companies/$_companyId/products/$productId/$imageId';
    final fullPath = '$base.jpg';
    final thumbPath = '${base}_thumb.jpg';
    final storage = FirebaseStorage.instance;
    final fullRef = storage.ref(fullPath);
    final thumbRef = storage.ref(thumbPath);
    await fullRef.putData(
      compressed.full,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    await thumbRef.putData(
      compressed.thumb,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ProductImage(
      id: imageId,
      url: await fullRef.getDownloadURL(),
      thumbUrl: await thumbRef.getDownloadURL(),
      storagePath: fullPath,
    );
  }
}

class _CompressedImage {
  const _CompressedImage({required this.full, required this.thumb});
  final Uint8List full;
  final Uint8List thumb;
}

_CompressedImage _compressImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('تعذر قراءة الصورة.');
  }
  final full = decoded.width > 1280
      ? img.copyResize(decoded, width: 1280)
      : decoded;
  final thumb = img.copyResize(decoded, width: 200);
  return _CompressedImage(
    full: Uint8List.fromList(img.encodeJpg(full, quality: 82)),
    thumb: Uint8List.fromList(img.encodeJpg(thumb, quality: 72)),
  );
}
