import 'dart:typed_data';

String imageMimeOf(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

bool isProbablyHeic(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
  return brand == 'heic' || brand == 'heif' || brand == 'mif1';
}
