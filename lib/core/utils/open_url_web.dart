// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final isTel = uri.scheme == 'tel';
  if (isTel && !_isMobileBrowser) return false;
  if (_openWithAnchor(url, self: isTel)) return true;
  try {
    if (isTel) {
      html.window.location.href = url;
      return true;
    }
    html.window.open(url, '_blank');
    return true;
  } catch (_) {}
  try {
    return await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: isTel ? '_self' : '_blank',
    );
  } catch (_) {
    return false;
  }
}

bool get _isMobileBrowser {
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('android') ||
      ua.contains('mobile');
}

bool _openWithAnchor(String url, {required bool self}) {
  try {
    final anchor = html.AnchorElement(href: url)
      ..target = self ? '_self' : '_blank'
      ..rel = 'noopener noreferrer'
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}
