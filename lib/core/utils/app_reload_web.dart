// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

void hideHtmlBootSplash() {
  html.document.getElementById('boot')?.remove();
}

Future<void> reloadApplication() async {
  await _dropStaleWorker();
  html.window.location.reload();
}

Future<void> ensureCurrentWebBuild(String buildLabel) async {
  if (buildLabel.isEmpty) return;
  try {
    final stored = html.window.localStorage['al_nomani_build_label'];
    html.window.localStorage['al_nomani_build_label'] = buildLabel;
    if (stored != null && stored.isNotEmpty && stored != buildLabel) {
      await _dropStaleWorker();
      html.window.location.reload();
    }
  } catch (_) {}
}

Future<void> _dropStaleWorker() async {
  try {
    final workers = html.window.navigator.serviceWorker;
    if (workers == null) return;
    final registrations = await workers.getRegistrations();
    for (final registration in registrations) {
      try {
        registration.waiting?.postMessage('skipWaiting');
      } catch (_) {}
      await registration.unregister();
    }
  } catch (_) {}
}
