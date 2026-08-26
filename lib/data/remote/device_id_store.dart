import 'dart:async';

import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdStore {
  DeviceIdStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _deviceKey = 'device_id_v1';
  static const _prefix = 'pref_';

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = newId();
    await _storage.write(key: _deviceKey, value: id);
    return id;
  }

  Future<String?> getPref(String key) => _storage.read(key: '$_prefix$key');

  Future<void> setPref(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);
}
