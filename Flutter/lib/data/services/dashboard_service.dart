import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_dashboard.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';
import 'package:money/data/services/persistent_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class DashboardServiceException implements Exception {
  final String message;
  final int? statusCode;

  const DashboardServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class DashboardService {
  DashboardService._({http.Client? client}) : _client = client ?? http.Client();

  static final DashboardService _instance = DashboardService._();

  factory DashboardService() => _instance;

  @visibleForTesting
  DashboardService.forTesting(http.Client client) : _client = client;

  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _freshCacheDuration = Duration(seconds: 30);
  static const int _maximumMemoryEntries = 12;
  static const String _cacheNamespace = 'dashboard';
  static const String _lastRegionPrefix = 'dashboard.last_region.';
  static const String _lastRegionsPrefix = 'dashboard.last_regions.';

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatusService = NetworkStatusService();
  final PersistentCacheService _persistentCache = PersistentCacheService();
  final Map<String, _CachedDashboard> _memoryCache = {};
  final Map<String, Future<AppDashboardData>> _requestsInFlight = {};

  Future<AppDashboardData> fetchDashboard({
    int? regionId,
    Iterable<int>? regionIds,
    bool forceRefresh = false,
    bool persistSelection = true,
    bool tutorialMode = false,
  }) async {
    final List<int> selectedRegionIds = _normalizeRegionIds(
      regionIds ?? <int>[?regionId],
    );
    final String key = _cacheKeyFor(
      selectedRegionIds,
      tutorialMode: tutorialMode,
    );
    final _CachedDashboard? cached =
        _memoryCache[key] ?? _restoreCachedDashboard(key);
    if (!forceRefresh && cached != null && _isFresh(cached)) {
      if (persistSelection) {
        await saveLastRegionIds(cached.data.selectedRegionIds);
      }
      return cached.data;
    }

    final Future<AppDashboardData>? pending = _requestsInFlight[key];
    if (pending != null) {
      final AppDashboardData result = await pending;
      if (persistSelection) {
        await saveLastRegionIds(result.selectedRegionIds);
      }
      return result;
    }

    final Future<AppDashboardData> request = _fetchRemote(
      key: key,
      selectedRegionIds: selectedRegionIds,
      cached: cached,
      forceRefresh: forceRefresh,
      tutorialMode: tutorialMode,
    );
    _requestsInFlight[key] = request;
    try {
      final AppDashboardData result = await request;
      if (persistSelection) {
        await saveLastRegionIds(result.selectedRegionIds);
      }
      return result;
    } finally {
      if (identical(_requestsInFlight[key], request)) {
        _requestsInFlight.remove(key);
      }
    }
  }

  Future<AppDashboardData> _fetchRemote({
    required String key,
    required List<int> selectedRegionIds,
    required _CachedDashboard? cached,
    required bool forceRefresh,
    required bool tutorialMode,
  }) async {
    final Uri uri = _uri('/api/v2/dashboard', {
      if (selectedRegionIds.isNotEmpty)
        'regionIds': selectedRegionIds.join(','),
      if (tutorialMode) 'tutorial': 'true',
    });

    try {
      final http.Response response = await _client
          .get(
            uri,
            headers: {
              ..._authService.authenticatedHeaders,
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
              if (!forceRefresh && cached?.etag != null)
                'If-None-Match': cached!.etag!,
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 304 && cached != null) {
        _networkStatusService.reportSuccessfulRequest();
        return cached.data;
      }
      final Map<String, dynamic> envelope = _decodeResponse(response);
      final Object? raw = envelope['responseBody'];
      if (raw is! Map) {
        throw const DashboardServiceException(
          'O servidor retornou dados inválidos para o painel.',
        );
      }
      final Map<String, dynamic> responseData = Map<String, dynamic>.from(raw);
      final AppDashboardData result = AppDashboardData.fromJson(responseData);
      final _CachedDashboard value = _CachedDashboard(
        data: result,
        etag: response.headers['etag'],
        savedAt: DateTime.now(),
      );
      _storeCachedDashboard(key, value, responseData);
      final String selectedKey = _cacheKeyFor(
        result.selectedRegionIds,
        tutorialMode: tutorialMode,
      );
      if (selectedKey != key) {
        _storeCachedDashboard(selectedKey, value, responseData);
      }
      _networkStatusService.reportSuccessfulRequest();
      return result;
    } on DashboardServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatusService.checkNow());
      throw const DashboardServiceException(
        'O servidor demorou para carregar o painel.',
      );
    } on http.ClientException {
      unawaited(_networkStatusService.checkNow());
      throw const DashboardServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } catch (_) {
      throw const DashboardServiceException(
        'Não foi possível carregar o painel.',
      );
    }
  }

  AppDashboardData? cachedDashboard({
    int? regionId,
    Iterable<int>? regionIds,
    bool tutorialMode = false,
  }) {
    final String key = _cacheKeyFor(
      _normalizeRegionIds(regionIds ?? <int>[?regionId]),
      tutorialMode: tutorialMode,
    );
    return (_memoryCache[key] ?? _restoreCachedDashboard(key))?.data;
  }

  Future<int?> lastRegionId() async {
    final List<int> ids = await lastRegionIds();
    return ids.isEmpty ? null : ids.first;
  }

  Future<List<int>> lastRegionIds() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final List<int> saved =
        (preferences.getStringList('$_lastRegionsPrefix$_userId') ??
                const <String>[])
            .map(int.tryParse)
            .whereType<int>()
            .where((id) => id > 0)
            .toList(growable: false);
    if (saved.isNotEmpty) return _normalizeRegionIds(saved);
    final int? legacy = preferences.getInt('$_lastRegionPrefix$_userId');
    return legacy == null ? const [] : <int>[legacy];
  }

  Future<void> saveLastRegionId(int regionId) async {
    await saveLastRegionIds(<int>[regionId]);
  }

  Future<void> saveLastRegionIds(Iterable<int> regionIds) async {
    final List<int> normalized = _normalizeRegionIds(regionIds);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      '$_lastRegionsPrefix$_userId',
      normalized.map((id) => '$id').toList(growable: false),
    );
    if (normalized.isNotEmpty) {
      await preferences.setInt('$_lastRegionPrefix$_userId', normalized.first);
    }
  }

  String get _userId => '${_authService.currentSession?.userId ?? 0}';

  String _cacheKey(int? regionId) => '$_userId|${regionId ?? 'default'}';

  String _cacheKeyFor(List<int> regionIds, {bool tutorialMode = false}) {
    final String scope = tutorialMode ? 'tutorial' : 'normal';
    return regionIds.isEmpty
        ? '$scope|${_cacheKey(null)}'
        : '$scope|$_userId|${regionIds.join(',')}';
  }

  List<int> _normalizeRegionIds(Iterable<int> values) {
    final List<int> result = values.where((id) => id > 0).toSet().toList()
      ..sort();
    return List<int>.unmodifiable(result);
  }

  Uri _uri(String path, Map<String, String> queryParameters) {
    final Uri base = Uri.parse(AuthService.apiBaseUrl);
    return base.replace(path: path, queryParameters: queryParameters);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final Map<String, dynamic>? body = response.bodyBytes.isEmpty
        ? null
        : _decodeMap(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body?['errorMessage']?.toString().trim() ?? '';
      throw DashboardServiceException(
        message.isEmpty ? 'Não foi possível carregar o painel.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic>? _decodeMap(List<int> bytes) {
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  void _storeCachedDashboard(
    String key,
    _CachedDashboard value,
    Map<String, dynamic> persistentData,
  ) {
    _memoryCache.remove(key);
    _memoryCache[key] = value;
    while (_memoryCache.length > _maximumMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    unawaited(
      _persistentCache.write(
        _cacheNamespace,
        key,
        data: persistentData,
        etag: value.etag,
      ),
    );
  }

  _CachedDashboard? _restoreCachedDashboard(String key) {
    final PersistentCacheEntry? entry = _persistentCache.read(
      _cacheNamespace,
      key,
    );
    if (entry?.data is! Map) return null;
    try {
      final AppDashboardData data = AppDashboardData.fromJson(
        Map<String, dynamic>.from(entry!.data as Map),
      );
      final _CachedDashboard value = _CachedDashboard(
        data: data,
        etag: entry.etag,
        savedAt: entry.savedAt,
      );
      _memoryCache[key] = value;
      return value;
    } catch (_) {
      unawaited(_persistentCache.remove(_cacheNamespace, key));
      return null;
    }
  }

  bool _isFresh(_CachedDashboard value) {
    return DateTime.now().difference(value.savedAt) < _freshCacheDuration;
  }
}

final class _CachedDashboard {
  final AppDashboardData data;
  final String? etag;
  final DateTime savedAt;

  const _CachedDashboard({
    required this.data,
    required this.etag,
    required this.savedAt,
  });
}
