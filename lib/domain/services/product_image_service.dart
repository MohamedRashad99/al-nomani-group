import 'dart:convert';
import 'dart:ui' as ui;

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/errors/app_exception.dart';
import '../entities/erp_models.dart';

class ProductImageService {
  static const _maxDocumentBytes = 90000;

  Future<ProductImage> upload({
    required String productId,
    required Uint8List bytes,
  }) async {
    final packed = await _compressImage(bytes);
    return ProductImage(id: newId(), url: packed);
  }
}

Future<String> _compressImage(Uint8List bytes) async {
  try {
    final jpeg = await _resizeJpeg(
      bytes,
      maxWidth: 960,
      quality: 70,
    ).timeout(const Duration(seconds: 8));
    return _dataUrl(_cap(jpeg), 'jpeg');
  } catch (_) {}
  try {
    final png = await _resizePng(bytes, maxWidth: 720)
        .timeout(const Duration(seconds: 8));
    return _dataUrl(_cap(png), 'png');
  } catch (_) {}
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const ValidationException(
      'تعذر قراءة الصورة. استخدم صورة JPG أو PNG.',
    );
  }
  final resized = decoded.width > 720
      ? img.copyResize(decoded, width: 720)
      : decoded;
  return _dataUrl(
    _cap(Uint8List.fromList(img.encodeJpg(resized, quality: 68))),
    'jpeg',
  );
}

Uint8List _cap(Uint8List bytes) {
  if (bytes.length <= ProductImageService._maxDocumentBytes) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes.sublist(0, ProductImageService._maxDocumentBytes);
  var width = decoded.width > 480 ? 480 : decoded.width;
  var quality = 55;
  Uint8List encoded = bytes;
  for (var i = 0; i < 4; i++) {
    final next = img.copyResize(decoded, width: width);
    encoded = Uint8List.fromList(img.encodeJpg(next, quality: quality));
    if (encoded.length <= ProductImageService._maxDocumentBytes) return encoded;
    width = (width * 0.75).round().clamp(160, width);
    quality = (quality - 8).clamp(40, quality);
  }
  return encoded;
}

String _dataUrl(Uint8List bytes, String mime) =>
    'data:image/$mime;base64,${base64Encode(bytes)}';

Future<Uint8List> _resizeJpeg(
  Uint8List bytes, {
  required int maxWidth,
  required int quality,
}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      throw const FormatException('empty image');
    }
    final raster = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(raster, quality: quality));
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _resizePng(Uint8List bytes, {required int maxWidth}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      throw const FormatException('empty png');
    }
    return png.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
