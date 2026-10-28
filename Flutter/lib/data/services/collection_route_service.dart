import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:money/data/models/app_client.dart';
import 'package:money/data/models/app_collection_route.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';

final class CollectionRouteServiceException implements Exception {
  final String message;
  final int? statusCode;

  const CollectionRouteServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class AppCollectionAttachment {
  final Uint8List bytes;
  final String fileName;
  final String contentType;

  const AppCollectionAttachment({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });
}

final class CollectionRouteService {
  CollectionRouteService._({http.Client? client})
    : _client = client ?? http.Client();

  static final CollectionRouteService _instance = CollectionRouteService._();

  factory CollectionRouteService() => _instance;

  CollectionRouteService.forTesting(http.Client client) : _client = client;

  static const Duration _timeout = Duration(seconds: 30);
  static const Duration _cacheLifetime = Duration(seconds: 20);

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  final Map<String, _CachedRoutePage> _pageCache = {};
  final Map<String, Future<AppCollectionRoutePage>> _pageRequests = {};

  Future<AppCollectionRoutePage> fetchRoutes({
    Set<int> regionIds = const {},
    int? collectorId,
    int? cityId,
    String city = '',
    AppCollectionRouteSort sort = AppCollectionRouteSort.overdueDays,
    String query = '',
    int page = 0,
    int size = 50,
    bool force = false,
  }) {
    final String key = _cacheKey(
      regionIds,
      collectorId,
      cityId,
      city,
      sort,
      query,
      page,
      size,
    );
    final _CachedRoutePage? cached = _pageCache[key];
    if (!force && cached != null && !cached.expired) {
      return Future.value(cached.value);
    }
    final Future<AppCollectionRoutePage>? inFlight = _pageRequests[key];
    if (!force && inFlight != null) return inFlight;
    final Future<AppCollectionRoutePage> request = _fetchRoutes(
      regionIds: regionIds,
      collectorId: collectorId,
      cityId: cityId,
      city: city,
      sort: sort,
      query: query,
      page: page,
      size: size,
    );
    _pageRequests[key] = request;
    return request.whenComplete(() {
      if (identical(_pageRequests[key], request)) _pageRequests.remove(key);
    });
  }

  Future<AppCollectionRoutePage> _fetchRoutes({
    required Set<int> regionIds,
    required int? collectorId,
    required int? cityId,
    required String city,
    required AppCollectionRouteSort sort,
    required String query,
    required int page,
    required int size,
  }) async {
    final List<int> sortedRegions = regionIds.toList()..sort();
    final Uri uri = _uri('/api/v2/routes', {
      if (sortedRegions.isNotEmpty) 'regionIds': sortedRegions.join(','),
      if (collectorId != null && collectorId > 0) 'collectorId': '$collectorId',
      if (cityId != null && cityId > 0) 'cityId': '$cityId',
      if (city.trim().isNotEmpty) 'city': city.trim(),
      'sort': sort.apiValue,
      if (query.trim().isNotEmpty) 'query': query.trim(),
      'page': '$page',
      'size': '$size',
    });
    final Map<String, dynamic> body = await _get(uri);
    final AppCollectionRoutePage result = AppCollectionRoutePage.fromJson(
      _responseMap(body),
    );
    _pageCache[_cacheKey(
      regionIds,
      collectorId,
      cityId,
      city,
      sort,
      query,
      page,
      size,
    )] = _CachedRoutePage(
      result,
      DateTime.now(),
    );
    return result;
  }

  Future<AppCollectionRoutePage> fetchCandidates({
    Set<int> regionIds = const {},
    int? cityId,
    String city = '',
    AppCollectionRouteSort sort = AppCollectionRouteSort.overdueDays,
    String query = '',
    int page = 0,
    int size = 50,
  }) async {
    final List<int> sortedRegions = regionIds.toList()..sort();
    final Map<String, dynamic> body = await _get(
      _uri('/api/v2/routes/candidates', {
        if (sortedRegions.isNotEmpty) 'regionIds': sortedRegions.join(','),
        if (cityId != null && cityId > 0) 'cityId': '$cityId',
        if (city.trim().isNotEmpty) 'city': city.trim(),
        'sort': sort.apiValue,
        if (query.trim().isNotEmpty) 'query': query.trim(),
        'page': '$page',
        'size': '$size',
      }),
    );
    return AppCollectionRoutePage.fromJson(_responseMap(body));
  }

  Future<List<AppCollectionRouteCollector>> fetchCollectors() async =>
      _responseList(await _get(_uri('/api/v2/routes/collectors')))
          .map(AppCollectionRouteCollector.fromJson)
          .toList(growable: false);

  Future<List<AppCityOption>> fetchAvailableCities({
    Set<int> regionIds = const {},
    int? collectorId,
    String query = '',
    required bool assignedOnly,
  }) async {
    final List<int> sortedRegions = regionIds.toList()..sort();
    return _responseList(
      await _get(
        _uri('/api/v2/routes/cities', {
          if (sortedRegions.isNotEmpty) 'regionIds': sortedRegions.join(','),
          if (collectorId != null && collectorId > 0)
            'collectorId': '$collectorId',
          if (query.trim().isNotEmpty) 'query': query.trim(),
          'assignedOnly': '$assignedOnly',
        }),
      ),
    ).map(AppCityOption.fromJson).toList(growable: false);
  }

  Future<List<AppCollectionRouteCollector>> fetchAssignedCollectors({
    Set<int> regionIds = const {},
    int? cityId,
    String query = '',
  }) async {
    final List<int> sortedRegions = regionIds.toList()..sort();
    return _responseList(
      await _get(
        _uri('/api/v2/routes/assigned-collectors', {
          if (sortedRegions.isNotEmpty) 'regionIds': sortedRegions.join(','),
          if (cityId != null && cityId > 0) 'cityId': '$cityId',
          if (query.trim().isNotEmpty) 'query': query.trim(),
        }),
      ),
    ).map(AppCollectionRouteCollector.fromJson).toList(growable: false);
  }

  Future<int> assignRoutes({
    required int collectorId,
    required Set<int> clientIds,
  }) async {
    try {
      final http.Response response = await _client
          .post(
            _uri('/api/v2/routes/assignments'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'collectorId': collectorId,
              'clientIds': clientIds.toList(growable: false),
            }),
          )
          .timeout(_timeout);
      final Map<String, dynamic> result = _responseMap(_decode(response));
      clearCache();
      _networkStatus.reportSuccessfulRequest();
      return (result['assignedClients'] as num?)?.toInt() ?? 0;
    } catch (error) {
      throw _exception(error, 'Não foi possível adicionar as rotas.');
    }
  }

  Future<void> removeRoute(int clientId) async {
    try {
      final http.Response response = await _client
          .delete(
            _uri('/api/v2/routes/$clientId/assignment'),
            headers: _headers,
          )
          .timeout(_timeout);
      _decode(response);
      clearCache();
      _networkStatus.reportSuccessfulRequest();
    } catch (error) {
      throw _exception(error, 'Não foi possível remover a rota.');
    }
  }

  Future<AppCollectionRouteDetail> fetchDetail(int clientId) async =>
      AppCollectionRouteDetail.fromJson(
        _responseMap(await _get(_uri('/api/v2/routes/$clientId'))),
      );

  Future<List<AppCollectionHistory>> fetchClientHistory(int clientId) async {
    final Map<String, dynamic> body = await _get(
      _uri('/api/v2/clients/$clientId/collections'),
    );
    return _responseList(body)
        .map(AppCollectionHistory.fromJson)
        .toList(growable: false);
  }

  Future<AppCollectionHistory> registerCollection({
    required int clientId,
    required String observation,
    Uint8List? attachmentBytes,
    String? attachmentName,
  }) async {
    try {
      final http.MultipartRequest request = http.MultipartRequest(
        'POST',
        _uri('/api/v2/routes/$clientId/collections'),
      );
      final Map<String, String> headers = Map.of(_headers)
        ..remove('Content-Type');
      request.headers.addAll(headers);
      request.fields['observation'] = observation.trim();
      if (attachmentBytes != null &&
          attachmentBytes.isNotEmpty &&
          attachmentName != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            attachmentBytes,
            filename: attachmentName,
          ),
        );
      }
      final http.Response response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
      final AppCollectionHistory result = AppCollectionHistory.fromJson(
        _responseMap(_decode(response)),
      );
      clearCache();
      _networkStatus.reportSuccessfulRequest();
      return result;
    } catch (error) {
      throw _exception(error, 'Não foi possível registrar a cobrança.');
    }
  }

  Future<AppCollectionAttachment> downloadAttachment(
    AppCollectionHistory collection,
  ) async {
    try {
      final http.Response response = await _client
          .get(
            _uri('/api/v2/collections/${collection.id}/file'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _decode(response);
      }
      _networkStatus.reportSuccessfulRequest();
      return AppCollectionAttachment(
        bytes: response.bodyBytes,
        fileName:
            _fileName(response.headers['content-disposition']) ??
            collection.attachmentName ??
            'anexo-cobranca',
        contentType:
            response.headers['content-type']?.split(';').first.trim() ??
            collection.attachmentContentType ??
            'application/octet-stream',
      );
    } catch (error) {
      throw _exception(error, 'Não foi possível baixar o anexo.');
    }
  }

  void clearCache() {
    _pageCache.clear();
    _pageRequests.clear();
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final http.Response response = await _client
          .get(uri, headers: _headers)
          .timeout(_timeout);
      final Map<String, dynamic> result = _decode(response);
      _networkStatus.reportSuccessfulRequest();
      return result;
    } catch (error) {
      throw _exception(error, 'Não foi possível carregar as rotas.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    if (response.bodyBytes.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body?['errorMessage']?.toString().trim() ?? '';
      throw CollectionRouteServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const CollectionRouteServiceException(
        'O servidor retornou dados inválidos.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  List<Map<String, dynamic>> _responseList(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! List) {
      throw const CollectionRouteServiceException(
        'O servidor retornou dados inválidos.',
      );
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  CollectionRouteServiceException _exception(Object error, String fallback) {
    if (error is CollectionRouteServiceException) return error;
    if (error is TimeoutException || error is http.ClientException) {
      unawaited(_networkStatus.checkNow());
      return const CollectionRouteServiceException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    }
    return CollectionRouteServiceException(fallback);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final Uri base = Uri.parse(AuthService.apiBaseUrl);
    return base.replace(path: path, queryParameters: query);
  }

  Map<String, String> get _headers => {
    ..._authService.authenticatedHeaders,
    'Accept': 'application/json',
  };

  String _cacheKey(
    Set<int> regionIds,
    int? collectorId,
    int? cityId,
    String city,
    AppCollectionRouteSort sort,
    String query,
    int page,
    int size,
  ) {
    final List<int> sorted = regionIds.toList()..sort();
    return '${_authService.currentSession?.userId ?? 0}|${sorted.join(',')}|'
        '${collectorId ?? 0}|${cityId ?? 0}|${city.trim().toLowerCase()}|${sort.apiValue}|'
        '${query.trim().toLowerCase()}|$page|$size';
  }
}

final class _CachedRoutePage {
  final AppCollectionRoutePage value;
  final DateTime savedAt;

  const _CachedRoutePage(this.value, this.savedAt);

  bool get expired =>
      DateTime.now().difference(savedAt) >
      CollectionRouteService._cacheLifetime;
}

String? _fileName(String? contentDisposition) {
  if (contentDisposition == null) return null;
  final RegExpMatch? encoded = RegExp(
    r'''filename\*\s*=\s*(?:UTF-8'')?([^;]+)''',
    caseSensitive: false,
  ).firstMatch(contentDisposition);
  final RegExpMatch? quoted = RegExp(
    r'''filename\s*=\s*"([^"]+)"''',
    caseSensitive: false,
  ).firstMatch(contentDisposition);
  String? value = encoded?.group(1) ?? quoted?.group(1);
  if (value == null) return null;
  value = value.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  }
}
