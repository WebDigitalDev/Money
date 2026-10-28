import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_user.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';
import 'package:money/data/services/persistent_cache_service.dart';

final class UserServiceException implements Exception {
  final String message;
  final int? statusCode;

  const UserServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class UserService {
  UserService._({http.Client? client}) : _client = client ?? http.Client();

  static final UserService _instance = UserService._();

  factory UserService() => _instance;

  @visibleForTesting
  factory UserService.forTesting(http.Client client) =>
      UserService._(client: client);

  static const Duration _requestTimeout = Duration(seconds: 20);

  static const int _maximumCachedPages = 60;
  static const String _cacheNamespace = 'users';

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatusService = NetworkStatusService();
  final PersistentCacheService _persistentCache = PersistentCacheService();
  final LinkedHashMap<String, _CachedUserPage> _userPageCache = LinkedHashMap();

  Future<AppUserPage> fetchUsers({
    String query = '',
    int page = 0,
    int size = 30,
  }) async {
    final Uri uri = _uri('/api/v2/users', {
      'query': query.trim(),
      'page': '$page',
      'size': '$size',
    });
    final String cacheKey = _usersCacheKey(query, page, size);
    final _CachedUserPage? cached =
        _userPageCache[cacheKey] ?? _restoreUserPage(cacheKey);
    final Map<String, String> headers = {
      ..._headers,
      if (cached?.etag != null) 'If-None-Match': cached!.etag!,
    };

    try {
      final http.Response response = await _client
          .get(uri, headers: headers)
          .timeout(_requestTimeout);
      if (response.statusCode == 304 && cached != null) {
        _touchCache(cacheKey, cached);
        _networkStatusService.reportSuccessfulRequest();
        return cached.page;
      }

      final Map<String, dynamic> body = _decodeResponse(response);
      final Map<String, dynamic> responseData = _responseBody(body);
      final AppUserPage result = AppUserPage.fromJson(responseData);
      _storeUserPage(
        cacheKey,
        _CachedUserPage(page: result, etag: response.headers['etag']),
        persistentData: responseData,
      );
      _networkStatusService.reportSuccessfulRequest();
      return result;
    } on UserServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const UserServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const UserServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } catch (_) {
      throw const UserServiceException('Não foi possível carregar os dados.');
    }
  }

  AppUserPage? cachedUsers({String query = '', int page = 0, int size = 30}) {
    final String cacheKey = _usersCacheKey(query, page, size);
    final _CachedUserPage? cached =
        _userPageCache[cacheKey] ?? _restoreUserPage(cacheKey);
    if (cached == null) return null;
    _touchCache(cacheKey, cached);
    return cached.page;
  }

  void clearCache() {
    _userPageCache.clear();
    unawaited(_persistentCache.clearNamespace(_cacheNamespace));
  }

  Future<AppUserDetail> fetchUser(int id) async {
    final Map<String, dynamic> body = await _get(_uri('/api/v2/users/$id'));
    return AppUserDetail.fromJson(_responseBody(body));
  }

  Future<AppUserDetail> fetchProfile() async {
    final Map<String, dynamic> body = await _get(_uri('/api/v2/profile'));
    return AppUserDetail.fromJson(_responseBody(body));
  }

  Future<List<AppUserRegion>> fetchRegionOptions() async {
    final Map<String, dynamic> body = await _get(_uri('/api/v2/users/options'));
    final Object? raw = body['responseBody'];
    if (raw is! List) {
      throw const UserServiceException(
        'O servidor retornou regiões inválidas.',
      );
    }
    return raw
        .whereType<Map>()
        .map((item) => AppUserRegion.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<AppUserDetail> createUser(Map<String, dynamic> data) async {
    final Map<String, dynamic> body = await _sendJson(
      'POST',
      _uri('/api/v2/users'),
      data,
    );
    final AppUserDetail result = AppUserDetail.fromJson(_responseBody(body));
    clearCache();
    return result;
  }

  Future<AppUserDetail> updateUser(int id, Map<String, dynamic> data) async {
    final Map<String, dynamic> body = await _sendJson(
      'PUT',
      _uri('/api/v2/users/$id'),
      data,
    );
    final AppUserDetail result = AppUserDetail.fromJson(_responseBody(body));
    clearCache();
    return result;
  }

  Future<void> changePassword(int id, String password) async {
    await _sendJson('PUT', _uri('/api/v2/users/$id/password'), {
      'password': password,
    }, allowEmptyBody: true);
    clearCache();
  }

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final Uri base = Uri.parse(AuthService.apiBaseUrl);
    return base.replace(path: path, queryParameters: queryParameters);
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final http.Response response = await _client
          .get(uri, headers: _headers)
          .timeout(_requestTimeout);
      final Map<String, dynamic> result = _decodeResponse(response);
      _networkStatusService.reportSuccessfulRequest();
      return result;
    } on UserServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const UserServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const UserServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } catch (_) {
      throw const UserServiceException('Não foi possível carregar os dados.');
    }
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    Uri uri,
    Map<String, dynamic> data, {
    bool allowEmptyBody = false,
  }) async {
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(_headers)
        ..body = jsonEncode(data);
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(_requestTimeout);
      final http.Response response = await http.Response.fromStream(streamed);
      if (allowEmptyBody && response.statusCode == 204) {
        _networkStatusService.reportSuccessfulRequest();
        return const {};
      }
      final Map<String, dynamic> result = _decodeResponse(response);
      _networkStatusService.reportSuccessfulRequest();
      return result;
    } on UserServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const UserServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const UserServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } catch (_) {
      throw const UserServiceException('Não foi possível salvar os dados.');
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final Map<String, dynamic>? body = response.bodyBytes.isEmpty
        ? null
        : _decodeMap(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body?['errorMessage']?.toString().trim() ?? '';
      throw UserServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic>? _decodeMap(List<int> bytes) {
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Map<String, dynamic> _responseBody(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const UserServiceException('O servidor retornou dados inválidos.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Map<String, String> get _headers => {
    ..._authService.authenticatedHeaders,
    'Accept': 'application/json',
  };

  String _usersCacheKey(String query, int page, int size) {
    final int userId = _authService.currentSession?.userId ?? 0;
    return '$userId|${query.trim().toLowerCase()}|$page|$size';
  }

  void _storeUserPage(
    String key,
    _CachedUserPage value, {
    Map<String, dynamic>? persistentData,
  }) {
    _userPageCache.remove(key);
    _userPageCache[key] = value;
    if (persistentData != null) {
      unawaited(
        _persistentCache.write(
          _cacheNamespace,
          key,
          data: persistentData,
          etag: value.etag,
        ),
      );
    }
    while (_userPageCache.length > _maximumCachedPages) {
      final String oldestKey = _userPageCache.keys.first;
      _userPageCache.remove(oldestKey);
      unawaited(_persistentCache.remove(_cacheNamespace, oldestKey));
    }
  }

  _CachedUserPage? _restoreUserPage(String key) {
    final PersistentCacheEntry? stored = _persistentCache.read(
      _cacheNamespace,
      key,
    );
    if (stored?.data is! Map) return null;
    try {
      final AppUserPage page = AppUserPage.fromJson(
        Map<String, dynamic>.from(stored!.data as Map),
      );
      final _CachedUserPage cached = _CachedUserPage(
        page: page,
        etag: stored.etag,
      );
      _storeUserPage(key, cached);
      return cached;
    } catch (_) {
      unawaited(_persistentCache.remove(_cacheNamespace, key));
      return null;
    }
  }

  void _touchCache(String key, _CachedUserPage value) {
    _userPageCache.remove(key);
    _userPageCache[key] = value;
  }
}

final class _CachedUserPage {
  final AppUserPage page;
  final String? etag;

  const _CachedUserPage({required this.page, required this.etag});
}
