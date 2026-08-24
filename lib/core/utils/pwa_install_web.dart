// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter, avoid_dynamic_calls

import 'dart:html' as html;

enum PwaInstallResult { installed, alreadyInstalled, iosInstructions, unavailable }

html.Event? _deferredPrompt;
var _listening = false;

void ensurePwaInstallListener() {
  if (_listening) return;
  _listening = true;
  html.window.addEventListener('beforeinstallprompt', (event) {
    event.preventDefault();
    _deferredPrompt = event;
  });
}

bool isPwaStandalone() {
  if (html.window.matchMedia('(display-mode: standalone)').matches) {
    return true;
  }
  try {
    return (html.window.navigator as dynamic).standalone == true;
  } catch (_) {
    return false;
  }
}

bool _isIos() {
  final ua = html.window.navigator.userAgent;
  return ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod');
}

Future<PwaInstallResult> promptPwaInstall() async {
  ensurePwaInstallListener();
  if (isPwaStandalone()) return PwaInstallResult.alreadyInstalled;
  final promptEvent = _deferredPrompt;
  if (promptEvent != null) {
    try {
      final dynamic event = promptEvent;
      event.prompt();
      await event.userChoice;
      _deferredPrompt = null;
      return PwaInstallResult.installed;
    } catch (_) {
      _deferredPrompt = null;
    }
  }
  if (_isIos()) return PwaInstallResult.iosInstructions;
  return PwaInstallResult.unavailable;
}
