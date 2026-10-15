import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_region.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';
import 'package:money/data/services/persistent_cache_service.dart';

final class RegionServiceException implements Exception {
  final String message;
  final int? statusCode;

  const RegionServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

typedef RegionExportDownloadProgress = void Function(double progress);

final class RegionService {
  RegionService._({http.Client? client}) : _client = client ?? http.Client();

  static final RegionService _instance = RegionService._();

  factory RegionService() => _instance;

  @visibleForTesting
  RegionService.forTesting(http.Client client) : _client = client;

  static const Duration _requestTimeout = Duration(seconds: 30);

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatusService = NetworkStatusService();
  static const int _maximumCachedLists = 32;
  static const String _cacheNamespace = 'regions';
  static const String _optionsCacheNamespace = 'region_options';

  final LinkedHashMap<String, _CachedRegionList> _listCache = LinkedHashMap();
  final PersistentCacheService _persistentCache = PersistentCacheService();
  List<AppRegionOption>? _optionsCache;

  Future<AppRegionListData> fetchRegions({
    required String query,
    required AppRegionFilters filters,
  }) async {
    final String key = _cacheKey(query, filters);
    final _CachedRegionList? cached =
        _listCache[key] ?? _restoreCachedList(key);
    final Uri uri = _uri('/api/v2/regions', {
      'query': query.trim(),
      if (filters.startDate != null)
        'startDate': _formatDate(filters.startDate!),
      if (filters.endDate != null) 'endDate': _formatDate(filters.endDate!),
      if (filters.regionIds.isNotEmpty)
        'regionIds': (filters.regionIds.toList()..sort()).join(','),
    });

    try {
      final http.Response response = await _client
          .get(
            uri,
            headers: {
              ..._headers,
              if (cached?.etag != null) 'If-None-Match': cached!.etag!,
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 304 && cached != null) {
        _networkStatusService.reportSuccessfulRequest();
        return cached.data;
      }

      final Map<String, dynamic> body = _decodeResponse(response);
      final Map<String, dynamic> responseData = _responseMap(body);
      final AppRegionListData result = AppRegionListData.fromJson(responseData);
      _storeCachedList(
        key,
        _CachedRegionList(data: result, etag: response.headers['etag']),
        persistentData: responseData,
      );
      _networkStatusService.reportSuccessfulRequest();
      return result;
    } on RegionServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } catch (_) {
      throw const RegionServiceException(
        'Não foi possível carregar as regiões.',
      );
    }
  }

  Future<List<AppRegionSummary>> fetchRegionsForExport({
    required String query,
    required AppRegionFilters filters,
    RegionExportDownloadProgress? onProgress,
  }) async {
    final Uri uri = _uri('/api/v2/regions', {
      'query': query.trim(),
      if (filters.startDate != null)
        'startDate': _formatDate(filters.startDate!),
      if (filters.endDate != null) 'endDate': _formatDate(filters.endDate!),
      if (filters.regionIds.isNotEmpty)
        'regionIds': (filters.regionIds.toList()..sort()).join(','),
    });
    try {
      final http.Request request = http.Request('GET', uri)
        ..headers.addAll(_headers);
      final http.StreamedResponse streamedResponse = await _client
          .send(request)
          .timeout(const Duration(minutes: 2));
      final int expectedBytes = streamedResponse.contentLength ?? 0;
      final List<int> receivedBytes = <int>[];
      await for (final List<int> chunk in streamedResponse.stream.timeout(
        const Duration(minutes: 2),
      )) {
        receivedBytes.addAll(chunk);
        final double progress = expectedBytes > 0
            ? receivedBytes.length / expectedBytes
            : receivedBytes.length / (receivedBytes.length + 500000);
        onProgress?.call(progress.clamp(0, .98));
      }
      final http.Response response = http.Response.bytes(
        receivedBytes,
        streamedResponse.statusCode,
        headers: streamedResponse.headers,
        request: streamedResponse.request,
      );
      final AppRegionListData result = AppRegionListData.fromJson(
        _responseMap(_decodeResponse(response)),
      );
      _networkStatusService.reportSuccessfulRequest();
      onProgress?.call(1);
      return result.items;
    } on RegionServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'Não foi possível concluir a exportação. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'Não foi possível concluir a exportação. Tente novamente.',
      );
    } catch (_) {
      throw const RegionServiceException(
        'Não foi possível preparar os dados da exportação.',
      );
    }
  }

  AppRegionListData? cachedRegions({
    required String query,
    required AppRegionFilters filters,
  }) {
    final String key = _cacheKey(query, filters);
    return (_listCache[key] ?? _restoreCachedList(key))?.data;
  }

  Future<List<AppRegionOption>> fetchOptions({
    bool force = false,
    bool tutorialMode = false,
  }) async {
    if (tutorialMode) {
      final Map<String, dynamic> tutorialBody = await _get(
        _uri('/api/v2/regions/options', const {'tutorial': 'true'}),
      );
      return _decodeOptions(tutorialBody);
    }
    _optionsCache ??= _restoreOptions();
    if (!force && _optionsCache != null) {
      unawaited(_refreshOptions());
      return _optionsCache!;
    }
    final Map<String, dynamic> body = await _get(
      _uri('/api/v2/regions/options'),
    );
    final List<AppRegionOption> result = _decodeOptions(body);
    final Object? raw = body['responseBody'];
    _optionsCache = result;
    unawaited(
      _persistentCache.write(
        _optionsCacheNamespace,
        _optionsCacheKey,
        data: raw,
      ),
    );
    return result;
  }

  List<AppRegionOption> _decodeOptions(Map<String, dynamic> body) {
    final Object? raw = body['responseBody'];
    if (raw is! List) {
      throw const RegionServiceException(
        'O servidor retornou opções de regiões inválidas.',
      );
    }
    final List<AppRegionOption> result = raw
        .whereType<Map>()
        .map(
          (item) => AppRegionOption.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
    return result;
  }

  Future<AppRegionDetail> fetchRegion(int id) async {
    final Map<String, dynamic> body = await _get(_uri('/api/v2/regions/$id'));
    return AppRegionDetail.fromJson(_responseMap(body));
  }

  Future<AppRegionDetail> createRegion(Map<String, dynamic> data) async {
    final Map<String, dynamic> body = await _sendJson(
      'POST',
      _uri('/api/v2/regions'),
      data,
    );
    clearCache();
    return AppRegionDetail.fromJson(_responseMap(body));
  }

  Future<AppRegionDetail> updateRegion(
    int id,
    Map<String, dynamic> data,
  ) async {
    final Map<String, dynamic> body = await _sendJson(
      'PUT',
      _uri('/api/v2/regions/$id'),
      data,
    );
    clearCache();
    return AppRegionDetail.fromJson(_responseMap(body));
  }

  Future<void> deleteRegion(int id) async {
    await _sendJson(
      'DELETE',
      _uri('/api/v2/regions/$id'),
      const {},
      allowEmptyBody: true,
    );
    clearCache();
  }

  void clearCache() {
    _listCache.clear();
    _optionsCache = null;
    unawaited(_persistentCache.clearNamespace(_cacheNamespace));
    unawaited(_persistentCache.clearNamespace(_optionsCacheNamespace));
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final http.Response response = await _client
          .get(uri, headers: _headers)
          .timeout(_requestTimeout);
      final Map<String, dynamic> result = _decodeResponse(response);
      _networkStatusService.reportSuccessfulRequest();
      return result;
    } on RegionServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } catch (_) {
      throw const RegionServiceException('Não foi possível carregar os dados.');
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
        ..headers.addAll(_headers);
      if (method != 'DELETE') request.body = jsonEncode(data);
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
    } on RegionServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const RegionServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } catch (_) {
      throw const RegionServiceException('Não foi possível salvar a região.');
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final Map<String, dynamic>? body = response.bodyBytes.isEmpty
        ? null
        : _decodeMap(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body?['errorMessage']?.toString().trim() ?? '';
      throw RegionServiceException(
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

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const RegionServiceException(
        'O servidor retornou dados de região inválidos.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final Uri base = Uri.parse(AuthService.apiBaseUrl);
    return base.replace(path: path, queryParameters: queryParameters);
  }

  Map<String, String> get _headers => {
    ..._authService.authenticatedHeaders,
    'Accept': 'application/json',
  };

  String _cacheKey(String query, AppRegionFilters filters) {
    final List<int> ids = filters.regionIds.toList()..sort();
    return '${_authService.currentSession?.userId ?? 0}|'
        '${query.trim().toLowerCase()}|'
        '${filters.startDate?.toIso8601String() ?? ''}|'
        '${filters.endDate?.toIso8601String() ?? ''}|${ids.join(',')}';
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void _storeCachedList(
    String key,
    _CachedRegionList value, {
    Map<String, dynamic>? persistentData,
  }) {
    _listCache.remove(key);
    _listCache[key] = value;
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
    while (_listCache.length > _maximumCachedLists) {
      final String oldestKey = _listCache.keys.first;
      _listCache.remove(oldestKey);
      unawaited(_persistentCache.remove(_cacheNamespace, oldestKey));
    }
  }

  _CachedRegionList? _restoreCachedList(String key) {
    final PersistentCacheEntry? stored = _persistentCache.read(
      _cacheNamespace,
      key,
    );
    if (stored?.data is! Map) return null;
    try {
      final AppRegionListData data = AppRegionListData.fromJson(
        Map<String, dynamic>.from(stored!.data as Map),
      );
      final _CachedRegionList cached = _CachedRegionList(
        data: data,
        etag: stored.etag,
      );
      _storeCachedList(key, cached);
      return cached;
    } catch (_) {
      unawaited(_persistentCache.remove(_cacheNamespace, key));
      return null;
    }
  }

  String get _optionsCacheKey => '${_authService.currentSession?.userId ?? 0}';

  List<AppRegionOption>? _restoreOptions() {
    final PersistentCacheEntry? stored = _persistentCache.read(
      _optionsCacheNamespace,
      _optionsCacheKey,
    );
    final Object? raw = stored?.data;
    if (raw is! List) return null;
    try {
      return raw
          .whereType<Map>()
          .map(
            (item) => AppRegionOption.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } catch (_) {
      unawaited(
        _persistentCache.remove(_optionsCacheNamespace, _optionsCacheKey),
      );
      return null;
    }
  }

  Future<void> _refreshOptions() async {
    try {
      await fetchOptions(force: true);
    } on RegionServiceException {
      // Mantém as opções persistidas até a próxima revalidação online.
    }
  }
}

final class _CachedRegionList {
  final AppRegionListData data;
  final String? etag;

  const _CachedRegionList({required this.data, required this.etag});
}
