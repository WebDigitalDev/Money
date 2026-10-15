import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_client.dart';
import 'package:money/data/models/app_region.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';
import 'package:money/data/services/persistent_cache_service.dart';

final class ClientServiceException implements Exception {
  final String message;
  final int? statusCode;

  const ClientServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

typedef ClientExportDownloadProgress = void Function(double progress);

final class AppDownloadedDocument {
  final String fileName;
  final String contentType;
  final Uint8List bytes;

  const AppDownloadedDocument({
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });
}

final class ClientService {
  ClientService._({http.Client? client}) : _client = client ?? http.Client();

  static final ClientService _instance = ClientService._();

  factory ClientService() => _instance;

  @visibleForTesting
  ClientService.forTesting(http.Client client) : _client = client;

  static const Duration _timeout = Duration(seconds: 30);
  static const Duration _detailCacheLifetime = Duration(seconds: 30);
  static const int _maximumCachedLists = 40;
  static const String _cacheNamespace = 'clients';

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  final PersistentCacheService _persistentCache = PersistentCacheService();
  final LinkedHashMap<String, _CachedClientPage> _cache = LinkedHashMap();
  final Map<int, AppClientDetail> _detailCache = {};
  final Map<int, DateTime> _detailCachedAt = {};
  final Map<int, Future<AppClientDetail>> _detailRequests = {};
  int _detailCacheVersion = 0;

  AppClientPage? cachedClients({
    required AppClientStatus? status,
    required String query,
    required Set<int> regionIds,
    required int page,
    required int size,
    bool tutorialMode = false,
  }) {
    final String key = _cacheKey(
      status,
      query,
      regionIds,
      page,
      size,
      tutorialMode: tutorialMode,
    );
    return (_cache[key] ?? _restorePage(key))?.data;
  }

  Future<AppClientPage> fetchClients({
    required AppClientStatus? status,
    required String query,
    required Set<int> regionIds,
    required int page,
    int size = 50,
    bool force = false,
    bool tutorialMode = false,
  }) async {
    final String key = _cacheKey(
      status,
      query,
      regionIds,
      page,
      size,
      tutorialMode: tutorialMode,
    );
    final _CachedClientPage? cached = _cache[key] ?? _restorePage(key);
    final List<int> sortedRegions = regionIds.toList()..sort();
    final Uri uri = _uri('/api/v2/clients', {
      'status': status?.apiValue ?? 'ALL',
      'query': query.trim(),
      if (sortedRegions.isNotEmpty) 'regionIds': sortedRegions.join(','),
      if (tutorialMode) 'tutorial': 'true',
      'page': '$page',
      'size': '$size',
    });
    try {
      final http.Response response = await _client
          .get(
            uri,
            headers: {
              ..._headers,
              if (!force && cached?.etag != null)
                'If-None-Match': cached!.etag!,
            },
          )
          .timeout(_timeout);
      if (response.statusCode == 304 && cached != null) {
        _networkStatus.reportSuccessfulRequest();
        return cached.data;
      }
      final Map<String, dynamic> body = _decode(response);
      final Map<String, dynamic> responseData = _responseMap(body);
      final AppClientPage pageData = AppClientPage.fromJson(responseData);
      _store(
        key,
        _CachedClientPage(pageData, response.headers['etag']),
        persistentData: responseData,
      );
      _networkStatus.reportSuccessfulRequest();
      return pageData;
    } catch (error) {
      return _handleReadError(error, cached?.data);
    }
  }

  Future<List<AppClientSummary>> fetchClientsForExport({
    required AppClientStatus? status,
    required String query,
    required Set<int> regionIds,
    ClientExportDownloadProgress? onProgress,
    bool tutorialMode = false,
  }) async {
    final List<int> sortedRegions = regionIds.toList()..sort();
    final Uri uri = _uri('/api/v2/clients/export-data', {
      'status': status?.apiValue ?? 'ALL',
      'query': query.trim(),
      if (sortedRegions.isNotEmpty) 'regionIds': sortedRegions.join(','),
      if (tutorialMode) 'tutorial': 'true',
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
      final AppClientPage result = AppClientPage.fromJson(
        _responseMap(_decode(response)),
      );
      _networkStatus.reportSuccessfulRequest();
      onProgress?.call(1);
      return result.items;
    } catch (error) {
      if (error is ClientServiceException) rethrow;
      if (error is TimeoutException || error is http.ClientException) {
        unawaited(_networkStatus.checkNow());
        throw const ClientServiceException(
          'Não foi possível concluir a exportação. Tente novamente.',
        );
      }
      throw const ClientServiceException(
        'Não foi possível preparar os dados da exportação.',
      );
    }
  }

  Future<AppClientDetail> fetchClient(int id, {bool force = false}) async {
    if (!force) {
      final AppClientDetail? cached = _detailCache[id];
      final DateTime? cachedAt = _detailCachedAt[id];
      if (cached != null &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt) < _detailCacheLifetime) {
        return cached;
      }
      _detailCache.remove(id);
      _detailCachedAt.remove(id);
      final Future<AppClientDetail>? inFlight = _detailRequests[id];
      if (inFlight != null) return inFlight;
    }

    final int cacheVersion = _detailCacheVersion;
    final Future<AppClientDetail> request = _fetchClientDetail(id);
    _detailRequests[id] = request;
    try {
      final AppClientDetail result = await request;
      if (cacheVersion == _detailCacheVersion) {
        _detailCache[id] = result;
        _detailCachedAt[id] = DateTime.now();
      }
      return result;
    } finally {
      if (identical(_detailRequests[id], request)) {
        _detailRequests.remove(id);
      }
    }
  }

  Future<void> prefetchClient(int id) async {
    await fetchClient(id);
  }

  Future<AppClientDetail> _fetchClientDetail(int id) async =>
      AppClientDetail.fromJson(
        _responseMap(await _get(_uri('/api/v2/clients/$id'))),
      );

  Future<AppCompanyLookup> fetchCompany(String document) async {
    final String digits = document.replaceAll(RegExp(r'\D'), '');
    return AppCompanyLookup.fromJson(
      _responseMap(await _get(_uri('/api/v2/clients/company/$digits'))),
    );
  }

  Future<AppClientDetail> createClient(Map<String, dynamic> data) async {
    final Map<String, dynamic> result = await _sendJson(
      'POST',
      _uri('/api/v2/clients'),
      data,
    );
    clearCache();
    return AppClientDetail.fromJson(_responseMap(result));
  }

  Future<AppClientDetail> updateClient(
    int id,
    Map<String, dynamic> data,
  ) async {
    final Map<String, dynamic> result = await _sendJson(
      'PUT',
      _uri('/api/v2/clients/$id'),
      data,
    );
    clearCache();
    return AppClientDetail.fromJson(_responseMap(result));
  }

  Future<void> deactivateClient(int id) async {
    await _sendJson(
      'DELETE',
      _uri('/api/v2/clients/$id'),
      const {},
      allowEmpty: true,
    );
    clearCache();
  }

  Future<AppClientDetail> setClientEnabled(int id, bool enabled) async {
    final Map<String, dynamic> body = await _sendJson(
      'PATCH',
      _uri('/api/v2/clients/$id/enabled'),
      {'enabled': enabled},
    );
    clearCache();
    return AppClientDetail.fromJson(_responseMap(body));
  }

  Future<List<AppRegionOption>> fetchDuplicateRegions(int clientId) async {
    final Map<String, dynamic> body = await _get(
      _uri('/api/v2/clients/$clientId/duplicate-regions'),
    );
    return _responseList(
      body,
    ).map(AppRegionOption.fromJson).toList(growable: false);
  }

  Future<AppClientDetail> duplicateClient(int clientId, int regionId) async {
    final Map<String, dynamic> body = await _sendJson(
      'POST',
      _uri('/api/v2/clients/$clientId/duplicate'),
      {'regionId': regionId},
    );
    clearCache();
    return AppClientDetail.fromJson(_responseMap(body));
  }

  Future<List<AppCityOption>> searchCities({
    String query = '',
    int? ibgeCode,
  }) async {
    final Map<String, dynamic> body = await _get(
      _uri('/api/v2/clients/cities', {
        'query': query.trim(),
        if (ibgeCode != null) 'ibgeCode': '$ibgeCode',
      }),
    );
    return _responseList(
      body,
    ).map((item) => AppCityOption.fromJson(item)).toList(growable: false);
  }

  Future<List<AppClientContact>> fetchContacts(int clientId) async {
    final Map<String, dynamic> body = await _get(
      _uri('/api/v2/clients/$clientId/contacts'),
    );
    return _responseList(
      body,
    ).map((item) => AppClientContact.fromJson(item)).toList(growable: false);
  }

  Future<AppClientContact> saveContact(
    int clientId,
    Map<String, dynamic> data, {
    int? contactId,
  }) async {
    final Map<String, dynamic> body = await _sendJson(
      contactId == null ? 'POST' : 'PUT',
      _uri(
        contactId == null
            ? '/api/v2/clients/$clientId/contacts'
            : '/api/v2/clients/$clientId/contacts/$contactId',
      ),
      data,
    );
    return AppClientContact.fromJson(_responseMap(body));
  }

  Future<void> deleteContact(int clientId, int contactId) async {
    await _sendJson(
      'DELETE',
      _uri('/api/v2/clients/$clientId/contacts/$contactId'),
      const {},
      allowEmpty: true,
    );
  }

  Future<List<AppClientDocument>> fetchDocuments(int clientId) async {
    final Map<String, dynamic> body = await _get(
      _uri('/api/v2/clients/$clientId/documents'),
    );
    return _responseList(
      body,
    ).map((item) => AppClientDocument.fromJson(item)).toList(growable: false);
  }

  Future<AppClientDocument> uploadDocument({
    required int clientId,
    required Uint8List bytes,
    required String fileName,
    required String description,
  }) async {
    try {
      final http.MultipartRequest request = http.MultipartRequest(
        'POST',
        _uri('/api/v2/clients/$clientId/documents'),
      )..headers.addAll(_headers);
      request.fields['description'] = description;
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
      final http.Response response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
      final AppClientDocument document = AppClientDocument.fromJson(
        _responseMap(_decode(response)),
      );
      _networkStatus.reportSuccessfulRequest();
      return document;
    } catch (error) {
      throw _writeException(error, 'Não foi possível enviar o documento.');
    }
  }

  Future<AppDownloadedDocument> downloadDocument(
    int clientId,
    AppClientDocument document,
  ) async {
    try {
      final http.Response response = await _client
          .get(
            _uri('/api/v2/clients/$clientId/documents/${document.id}/file'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _decode(response);
      }
      final Uint8List bytes = response.bodyBytes;
      final String contentType = _resolvedDocumentContentType(
        response.headers['content-type'] ?? document.contentType,
        document.fileName,
        bytes,
      );
      final String fileName = _resolvedDocumentFileName(
        _contentDispositionFileName(response.headers['content-disposition']) ??
            document.fileName,
        contentType,
      );
      _networkStatus.reportSuccessfulRequest();
      return AppDownloadedDocument(
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
      );
    } catch (error) {
      throw _writeException(error, 'Não foi possível baixar o documento.');
    }
  }

  Future<AppClientDocument> updateDocument(
    int clientId,
    int documentId,
    String description,
  ) async => AppClientDocument.fromJson(
    _responseMap(
      await _sendJson(
        'PATCH',
        _uri('/api/v2/clients/$clientId/documents/$documentId'),
        {'description': description},
      ),
    ),
  );

  Future<void> deleteDocument(int clientId, int documentId) async {
    await _sendJson(
      'DELETE',
      _uri('/api/v2/clients/$clientId/documents/$documentId'),
      const {},
      allowEmpty: true,
    );
  }

  void clearCache() {
    _cache.clear();
    _detailCache.clear();
    _detailCachedAt.clear();
    _detailRequests.clear();
    ++_detailCacheVersion;
    unawaited(_persistentCache.clearNamespace(_cacheNamespace));
  }

  void invalidateClient(int id) {
    _detailCache.remove(id);
    _detailCachedAt.remove(id);
    _detailRequests.remove(id);
    ++_detailCacheVersion;
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
      throw _writeException(error, 'Não foi possível carregar os dados.');
    }
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    Uri uri,
    Map<String, dynamic> data, {
    bool allowEmpty = false,
  }) async {
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll({..._headers, 'Content-Type': 'application/json'});
      if (method != 'DELETE') request.body = jsonEncode(data);
      final http.Response response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
      if (allowEmpty && response.statusCode == 204) {
        _networkStatus.reportSuccessfulRequest();
        return const {};
      }
      final Map<String, dynamic> result = _decode(response);
      _networkStatus.reportSuccessfulRequest();
      return result;
    } catch (error) {
      throw _writeException(error, 'Não foi possível salvar o cliente.');
    }
  }

  T _handleReadError<T>(Object error, T? cached) {
    if (cached != null) {
      unawaited(_networkStatus.checkNow());
      return cached;
    }
    throw _writeException(error, 'Não foi possível carregar os clientes.');
  }

  ClientServiceException _writeException(Object error, String fallback) {
    if (error is ClientServiceException) return error;
    if (error is TimeoutException || error is http.ClientException) {
      unawaited(_networkStatus.checkNow());
      return const ClientServiceException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    }
    return ClientServiceException(fallback);
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
      throw ClientServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const ClientServiceException(
        'O servidor retornou dados inválidos.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  List<Map<String, dynamic>> _responseList(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! List) {
      throw const ClientServiceException(
        'O servidor retornou dados inválidos.',
      );
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
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
    AppClientStatus? status,
    String query,
    Set<int> regionIds,
    int page,
    int size, {
    bool tutorialMode = false,
  }) {
    final List<int> ids = regionIds.toList()..sort();
    final String scope = tutorialMode ? 'tutorial' : 'normal';
    return '$scope|${_authService.currentSession?.userId ?? 0}|${status?.apiValue ?? 'ALL'}|'
        '${query.trim().toLowerCase()}|${ids.join(',')}|$page|$size';
  }

  void _store(
    String key,
    _CachedClientPage value, {
    Map<String, dynamic>? persistentData,
  }) {
    _cache.remove(key);
    _cache[key] = value;
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
    while (_cache.length > _maximumCachedLists) {
      final String oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      unawaited(_persistentCache.remove(_cacheNamespace, oldestKey));
    }
  }

  _CachedClientPage? _restorePage(String key) {
    final PersistentCacheEntry? stored = _persistentCache.read(
      _cacheNamespace,
      key,
    );
    if (stored?.data is! Map) return null;
    try {
      final AppClientPage page = AppClientPage.fromJson(
        Map<String, dynamic>.from(stored!.data as Map),
      );
      final _CachedClientPage cached = _CachedClientPage(page, stored.etag);
      _store(key, cached);
      return cached;
    } catch (_) {
      unawaited(_persistentCache.remove(_cacheNamespace, key));
      return null;
    }
  }
}

String? _contentDispositionFileName(String? header) {
  if (header == null || header.trim().isEmpty) return null;
  final RegExpMatch? encoded = RegExp(
    r'''filename\*\s*=\s*(?:UTF-8'')?([^;]+)''',
    caseSensitive: false,
  ).firstMatch(header);
  String? value = encoded?.group(1)?.trim();
  if (value == null) {
    final RegExpMatch? quoted = RegExp(
      r'''filename\s*=\s*"([^"]+)"''',
      caseSensitive: false,
    ).firstMatch(header);
    value = quoted?.group(1)?.trim();
  }
  if (value == null) {
    final RegExpMatch? plain = RegExp(
      r'''filename\s*=\s*([^;]+)''',
      caseSensitive: false,
    ).firstMatch(header);
    value = plain?.group(1)?.trim();
  }
  if (value == null || value.isEmpty) return null;
  value = value.replaceAll(RegExp(r'''^["']|["']$'''), '');
  try {
    value = Uri.decodeComponent(value);
  } on FormatException {
    // Keep the server value if it is not RFC 5987 encoded.
  }
  return value;
}

String _resolvedDocumentContentType(
  String? declaredType,
  String fileName,
  Uint8List bytes,
) {
  String? value = declaredType?.split(';').first.trim().toLowerCase();
  if (value == 'image/jpg') value = 'image/jpeg';
  if (value == 'application/x-pdf') value = 'application/pdf';
  if (value == null ||
      value.isEmpty ||
      value == 'application/octet-stream' ||
      value == 'binary/octet-stream' ||
      value == 'content/unknown') {
    return _documentTypeFromBytes(bytes) ??
        _documentTypeFromExtension(_documentExtension(fileName)) ??
        'application/octet-stream';
  }
  return value;
}

String _resolvedDocumentFileName(String rawName, String contentType) {
  String fileName = rawName.trim().replaceAll('\\', '_').replaceAll('/', '_');
  if (fileName.isEmpty) fileName = 'documento';
  final String? current = _documentExtension(fileName);
  final String? expected = _documentExtensionFromType(contentType);
  if (expected != null &&
      (current == null || current == 'bin' || current == 'dat')) {
    final int dot = fileName.lastIndexOf('.');
    final String base = current == null ? fileName : fileName.substring(0, dot);
    return '$base.$expected';
  }
  return fileName;
}

String? _documentExtension(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return null;
  final String value = fileName.substring(dot + 1).toLowerCase();
  return value.length <= 10 ? value : null;
}

String? _documentTypeFromExtension(String? extension) => switch (extension) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'bmp' => 'image/bmp',
  'tif' || 'tiff' => 'image/tiff',
  'pdf' => 'application/pdf',
  'zip' => 'application/zip',
  'mp4' => 'video/mp4',
  'txt' => 'text/plain',
  'html' || 'htm' => 'text/html',
  'doc' => 'application/msword',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls' => 'application/vnd.ms-excel',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  _ => null,
};

String? _documentExtensionFromType(String contentType) => switch (contentType) {
  'image/jpeg' => 'jpg',
  'image/png' => 'png',
  'image/gif' => 'gif',
  'image/webp' => 'webp',
  'image/bmp' => 'bmp',
  'image/tiff' => 'tiff',
  'application/pdf' => 'pdf',
  'application/zip' => 'zip',
  'video/mp4' => 'mp4',
  'text/plain' => 'txt',
  'text/html' => 'html',
  'application/msword' => 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
    'docx',
  'application/vnd.ms-excel' => 'xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'xlsx',
  _ => null,
};

String? _documentTypeFromBytes(Uint8List bytes) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (int index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }

  if (startsWith(const [0x25, 0x50, 0x44, 0x46])) {
    return 'application/pdf';
  }
  if (startsWith(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (startsWith(ascii.encode('GIF87a')) ||
      startsWith(ascii.encode('GIF89a'))) {
    return 'image/gif';
  }
  if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WEBP'), 8)) {
    return 'image/webp';
  }
  if (startsWith(const [0x42, 0x4d])) return 'image/bmp';
  if (startsWith(const [0x49, 0x49, 0x2a, 0x00]) ||
      startsWith(const [0x4d, 0x4d, 0x00, 0x2a])) {
    return 'image/tiff';
  }
  if (startsWith(const [0x50, 0x4b, 0x03, 0x04]) ||
      startsWith(const [0x50, 0x4b, 0x05, 0x06]) ||
      startsWith(const [0x50, 0x4b, 0x07, 0x08])) {
    return 'application/zip';
  }
  if (startsWith(ascii.encode('ftyp'), 4)) return 'video/mp4';
  return null;
}

final class _CachedClientPage {
  final AppClientPage data;
  final String? etag;

  const _CachedClientPage(this.data, this.etag);
}
