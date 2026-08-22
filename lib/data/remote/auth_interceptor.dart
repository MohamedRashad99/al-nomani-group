import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import 'auth_token_store.dart';

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required AuthTokenStore tokens,
    required AppConfig config,
    required Dio refreshClient,
  }) : _tokens = tokens,
       _config = config,
       _refreshClient = refreshClient;

  final AuthTokenStore _tokens;
  final AppConfig _config;
  final Dio _refreshClient;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokens.accessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (error.response?.statusCode != 401 &&
        error.response?.statusCode != 403) {
      handler.next(error);
      return;
    }
    if (error.requestOptions.extra['authRetried'] == true ||
        error.requestOptions.path.endsWith('/auth/refresh')) {
      handler.next(error);
      return;
    }

    final refresh = await _tokens.refreshToken();
    if (refresh == null || refresh.isEmpty) {
      handler.next(error);
      return;
    }

    try {
      final response = await _refreshClient.post<Map<String, dynamic>>(
        '${_config.apiBaseUrl}/api/v1/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = response.data ?? const <String, dynamic>{};
      final access = data['access_token'] as String?;
      final rotatedRefresh = data['refresh_token'] as String? ?? refresh;
      if (access == null || access.isEmpty) {
        handler.next(error);
        return;
      }
      await _tokens.save(
        accessToken: access,
        refreshToken: rotatedRefresh,
      );

      final request = error.requestOptions;
      request.extra['authRetried'] = true;
      request.headers['Authorization'] = 'Bearer $access';
      final retry = await _refreshClient.fetch<dynamic>(request);
      handler.resolve(retry);
    } catch (_) {
      await _tokens.clear();
      handler.next(error);
    }
  }
}
