import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local credentials used only for authenticated API transport.
///
/// Business data remains in Drift. Tokens are deliberately kept out of
/// localStorage and out of sync payloads.
class AuthTokenStore {
  AuthTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'api_access_token_v1';
  static const _refreshKey = 'api_refresh_token_v1';

  final FlutterSecureStorage _storage;

  Future<String?> accessToken() => _storage.read(key: _accessKey);

  Future<String?> refreshToken() => _storage.read(key: _refreshKey);

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
