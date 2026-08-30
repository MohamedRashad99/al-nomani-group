class EgyptPhone {
  const EgyptPhone._();

  static String digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'[^\d+]'), '');

  /// International digits without `+`, defaulting local Egyptian numbers to 20.
  static String? e164Digits(String? raw) {
    var value = digitsOnly(raw?.trim() ?? '');
    if (value.isEmpty) return null;
    if (value.startsWith('+')) value = value.substring(1);
    if (value.startsWith('00')) value = value.substring(2);
    if (value.startsWith('0')) value = value.substring(1);
    if (value.startsWith('20')) return value;
    if (value.startsWith('1') && value.length == 10) return '20$value';
    if (value.length >= 8 && value.length <= 11) return '20$value';
    return value;
  }

  static String? telUri(String? raw) {
    final digits = e164Digits(raw);
    if (digits == null || digits.isEmpty) return null;
    return 'tel:+$digits';
  }

  static String? whatsAppMe(String? raw) {
    final digits = e164Digits(raw);
    if (digits == null || digits.isEmpty) return null;
    return 'https://wa.me/$digits';
  }

  static String? whatsAppApi(String? raw) {
    final digits = e164Digits(raw);
    if (digits == null || digits.isEmpty) return null;
    return 'https://api.whatsapp.com/send?phone=$digits';
  }
}
