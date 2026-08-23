import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FirebaseBootstrap {
  static bool ready = false;
  static String? lastError;

  static Future<bool> ensure() async {
    if (ready) return true;
    try {
      final raw = await rootBundle.loadString('assets/config/firebase.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final apiKey = json['apiKey'] as String? ?? '';
      final appId = json['appId'] as String? ?? '';
      final projectId = json['projectId'] as String? ?? '';
      if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) {
        lastError =
            'أضف مفاتيح تطبيق Firebase في assets/config/firebase.json ثم أعد التشغيل.';
        return false;
      }
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: json['messagingSenderId'] as String? ?? '',
            projectId: projectId,
            authDomain: json['authDomain'] as String?,
            storageBucket: json['storageBucket'] as String?,
            measurementId: json['measurementId'] as String?,
          ),
        );
      }
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      ready = true;
      lastError = null;
      return true;
    } catch (error) {
      lastError = error.toString();
      debugPrint('Firebase bootstrap failed: $error');
      return false;
    }
  }
}
