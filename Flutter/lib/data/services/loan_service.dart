import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:money/data/models/app_loan.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/client_service.dart';
import 'package:money/data/services/network_status_service.dart';
import 'package:money/data/services/persistent_cache_service.dart';

final class LoanServiceException implements Exception {
  final String message;
  final int? statusCode;

  const LoanServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

typedef LoanExportDownloadProgress = void Function(double progress);

final class LoanService {
  LoanService._({http.Client? client}) : _client = client ?? http.Client();

  static final LoanService _instance = LoanService._();

  factory LoanService() => _instance;

  static const Duration _timeout = Duration(seconds: 30);
  static const int _maximumCachedPages = 48;
  static const String _cacheNamespace = 'loans';

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  final PersistentCacheService _persistentCache = PersistentCacheService();
  final LinkedHashMap<String, _CachedLoanPage> _cache = LinkedHashMap();

  AppLoanPage? cachedLoans({
    required String query,
    required AppLoanFilters filters,
    required int page,
    required int size,
    bool tutorialMode = false,
  }) {
    final String key = _cacheKey(
      query,
      filters,
      page,
      size,
      tutorialMode: tutorialMode,
    );
    return (_cache[key] ?? _restorePage(key))?.data;
  }

  Future<AppLoanPage> fetchLoans({
    required String query,
    required AppLoanFilters filters,
    required int page,
    int size = 50,
    bool force = false,
    bool tutorialMode = false,
  }) async {
    final String key = _cacheKey(
      query,
      filters,
      page,
      size,
      tutorialMode: tutorialMode,
    );
    final _CachedLoanPage? cached = _cache[key] ?? _restorePage(key);
    final List<String> statuses = filters.statuses.toList()..sort();
    final List<int> regionIds = filters.regionIds.toList()..sort();
    final Uri uri = _uri('/api/v2/loans', {
      'query': query.trim(),
      if (statuses.isNotEmpty) 'statuses': statuses.join(','),
      if (regionIds.isNotEmpty) 'regionIds': regionIds.join(','),
      if (tutorialMode) 'tutorial': 'true',
      if (filters.startDate != null)
        'startDate': _formatDate(filters.startDate!),
      if (filters.endDate != null) 'endDate': _formatDate(filters.endDate!),
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
      final AppLoanPage result = AppLoanPage.fromJson(responseData);
      _store(
        key,
        _CachedLoanPage(result, response.headers['etag']),
        persistentData: responseData,
      );
      _networkStatus.reportSuccessfulRequest();
      return result;
    } catch (error) {
      if (cached != null) {
        unawaited(_networkStatus.checkNow());
        return cached.data;
      }
      if (error is LoanServiceException) rethrow;
      if (error is TimeoutException || error is http.ClientException) {
        unawaited(_networkStatus.checkNow());
        throw const LoanServiceException(
          'Não foi possível conectar ao servidor. Tente novamente.',
        );
      }
      throw const LoanServiceException(
        'Não foi possível carregar os empréstimos.',
      );
    }
  }

  Future<List<AppLoanSummary>> fetchLoansForExport({
    required String query,
    required AppLoanFilters filters,
    LoanExportDownloadProgress? onProgress,
    bool tutorialMode = false,
  }) async {
    final List<String> statuses = filters.statuses.toList()..sort();
    final List<int> regionIds = filters.regionIds.toList()..sort();
    final Uri uri = _uri('/api/v2/loans/export-data', {
      'query': query.trim(),
      if (statuses.isNotEmpty) 'statuses': statuses.join(','),
      if (regionIds.isNotEmpty) 'regionIds': regionIds.join(','),
      if (tutorialMode) 'tutorial': 'true',
      if (filters.startDate != null)
        'startDate': _formatDate(filters.startDate!),
      if (filters.endDate != null) 'endDate': _formatDate(filters.endDate!),
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
      final Map<String, dynamic> body = _decode(response);
      final AppLoanPage result = AppLoanPage.fromJson(_responseMap(body));
      _networkStatus.reportSuccessfulRequest();
      onProgress?.call(1);
      return result.items;
    } catch (error) {
      if (error is LoanServiceException) rethrow;
      if (error is TimeoutException || error is http.ClientException) {
        unawaited(_networkStatus.checkNow());
        throw const LoanServiceException(
          'Não foi possível concluir a exportação. Tente novamente.',
        );
      }
      throw const LoanServiceException(
        'Não foi possível preparar os dados da exportação.',
      );
    }
  }

  Future<AppLoanDetail> fetchDetail(int loanId, {bool compact = false}) async {
    return _detailRequest(
      'GET',
      '/api/v2/loans/$loanId',
      query: {if (compact) 'compact': 'true'},
    );
  }

  Future<List<AppLoanFeedback>> fetchFeedbacks(int loanId) async {
    final Map<String, dynamic> envelope = await _request(
      'GET',
      '/api/v2/loans/$loanId/feedbacks',
    );
    final Object? raw = envelope['responseBody'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => AppLoanFeedback.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<AppLoanFeedback> addFeedback(int loanId, String text) async {
    final Map<String, dynamic> envelope = await _request(
      'POST',
      '/api/v2/loans/$loanId/feedbacks',
      data: {'text': text.trim()},
    );
    return AppLoanFeedback.fromJson(_responseMap(envelope));
  }

  Future<void> deleteFeedback(int loanId, int feedbackId) async {
    await _request('DELETE', '/api/v2/loans/$loanId/feedbacks/$feedbackId');
  }

  Future<AppLoanDetail> createLoan(Map<String, dynamic> data) =>
      _detailRequest('POST', '/api/v2/loans', data: data);

  Future<String> fetchLoanMessage(int loanId, String type) async {
    final Map<String, dynamic> envelope = await _request(
      'GET',
      '/api/v2/loans/$loanId/message/$type',
    );
    final String message = _responseMap(envelope)['message']?.toString() ?? '';
    if (message.trim().isEmpty) {
      throw const LoanServiceException(
        'O servidor não conseguiu gerar a mensagem.',
      );
    }
    return message;
  }

  Future<String> fetchInstallmentMessage(
    int loanId,
    int installmentId,
    String type,
  ) async {
    final Map<String, dynamic> envelope = await _request(
      'GET',
      '/api/v2/loans/$loanId/installments/$installmentId/message/$type',
    );
    final String message = _responseMap(envelope)['message']?.toString() ?? '';
    if (message.trim().isEmpty) {
      throw const LoanServiceException(
        'O servidor não conseguiu gerar a mensagem da parcela.',
      );
    }
    return message;
  }

  Future<AppLoanDetail> updateLoan(int loanId, Map<String, dynamic> data) =>
      _detailRequest('PUT', '/api/v2/loans/$loanId', data: data);

  Future<AppLoanDetail> updateInstallment(
    int loanId,
    int installmentId,
    Map<String, dynamic> data,
  ) => _detailRequest(
    'PUT',
    '/api/v2/loans/$loanId/installments/$installmentId',
    data: data,
  );

  Future<AppLoanDetail> addInstallmentPayment(
    int loanId,
    int installmentId,
    Map<String, dynamic> data,
  ) => _detailRequest(
    'POST',
    '/api/v2/loans/$loanId/installments/$installmentId/payments',
    data: data,
  );

  Future<AppLoanDetail> updateInstallmentPayment(
    int loanId,
    int installmentId,
    int paymentId,
    Map<String, dynamic> data,
  ) => _detailRequest(
    'PUT',
    '/api/v2/loans/$loanId/installments/$installmentId/payments/$paymentId',
    data: data,
  );

  Future<AppLoanDetail> deleteInstallmentPayment(
    int loanId,
    int installmentId,
    int paymentId,
  ) => _detailRequest(
    'DELETE',
    '/api/v2/loans/$loanId/installments/$installmentId/payments/$paymentId',
  );

  Future<AppLoanDetail> distributePayment(
    int loanId,
    Map<String, dynamic> data,
  ) => _detailRequest('POST', '/api/v2/loans/$loanId/payments', data: data);

  Future<AppLoanDetail> interestOnlyPayment(
    int loanId,
    Map<String, dynamic> data,
  ) =>
      _detailRequest('POST', '/api/v2/loans/$loanId/interest-roll', data: data);

  Future<AppLoanDetail?> closeLoan(int loanId, String action) async {
    final Map<String, dynamic> envelope = await _request(
      'POST',
      '/api/v2/loans/$loanId/closure/$action',
    );
    final Object? raw = envelope['responseBody'];
    clearCache();
    final AppLoanDetail? result = raw is Map
        ? AppLoanDetail.fromJson(Map<String, dynamic>.from(raw))
        : null;
    if (result != null) ClientService().invalidateClient(result.clientId);
    return result;
  }

  Future<AppLoanDetail> negotiate(
    int loanId,
    String mode,
    Map<String, dynamic> data,
  ) => _detailRequest(
    'POST',
    '/api/v2/loans/$loanId/negotiations/$mode',
    data: data,
  );

  Future<AppLoanDetail?> decideApproval(
    int loanId,
    int approvalId, {
    required bool approve,
    String? reason,
  }) async {
    final Map<String, dynamic> envelope = await _request(
      'POST',
      '/api/v2/loans/$loanId/approvals/$approvalId/${approve ? 'approve' : 'reject'}',
      data: {'reason': reason},
    );
    final Object? raw = envelope['responseBody'];
    clearCache();
    final AppLoanDetail? result = raw is Map
        ? AppLoanDetail.fromJson(Map<String, dynamic>.from(raw))
        : null;
    if (result != null) ClientService().invalidateClient(result.clientId);
    return result;
  }

  Future<AppPixCharge?> fetchCurrentPix(
    int loanId, {
    int? installmentId,
  }) async {
    final Map<String, dynamic> envelope = await _request(
      'GET',
      '/api/v2/loans/$loanId/pix/current',
      query: {if (installmentId != null) 'installmentId': '$installmentId'},
    );
    final Object? raw = envelope['responseBody'];
    return raw is Map
        ? AppPixCharge.fromJson(Map<String, dynamic>.from(raw))
        : null;
  }

  Future<AppPixCharge> generatePix(
    int loanId, {
    int? installmentId,
    required double amount,
  }) => _pixRequest(
    'POST',
    '/api/v2/loans/$loanId/pix',
    data: {'installmentId': installmentId, 'amount': amount},
  );

  Future<AppPixCharge> refreshPix(int pixId) =>
      _pixRequest('POST', '/api/v2/pix/$pixId/refresh');

  Future<AppPixCharge> sendPixWhatsapp(int pixId) =>
      _pixRequest('POST', '/api/v2/pix/$pixId/whatsapp');

  Future<AppPixCancellationResult> cancelPendingPix(int loanId) async {
    final Map<String, dynamic> envelope = await _request(
      'POST',
      '/api/v2/loans/$loanId/pix/cancel-pending',
    );
    clearCache();
    return AppPixCancellationResult.fromJson(_responseMap(envelope));
  }

  Future<AppPixCharge> _pixRequest(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final Map<String, dynamic> envelope = await _request(
      method,
      path,
      data: data,
    );
    return AppPixCharge.fromJson(_responseMap(envelope));
  }

  Future<AppLoanDetail> _detailRequest(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? query,
  }) async {
    final Map<String, dynamic> envelope = await _request(
      method,
      path,
      data: data,
      query: query,
    );
    final Map<String, dynamic> body = _responseMap(envelope);
    clearCache();
    final AppLoanDetail result = AppLoanDetail.fromJson(body);
    if (method != 'GET') ClientService().invalidateClient(result.clientId);
    return result;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? query,
  }) async {
    try {
      final Uri uri = _uri(path, query);
      final Map<String, String> headers = {
        ..._headers,
        if (data != null) 'Content-Type': 'application/json',
      };
      final String? body = data == null ? null : jsonEncode(data);
      final http.Response response = switch (method) {
        'POST' =>
          await _client
              .post(uri, headers: headers, body: body)
              .timeout(_timeout),
        'PUT' =>
          await _client
              .put(uri, headers: headers, body: body)
              .timeout(_timeout),
        'DELETE' =>
          await _client.delete(uri, headers: headers).timeout(_timeout),
        _ => await _client.get(uri, headers: headers).timeout(_timeout),
      };
      final Map<String, dynamic> decoded = _decode(response);
      _networkStatus.reportSuccessfulRequest();
      return decoded;
    } catch (error) {
      if (error is LoanServiceException) rethrow;
      if (error is TimeoutException || error is http.ClientException) {
        unawaited(_networkStatus.checkNow());
        throw const LoanServiceException(
          'Não foi possível conectar ao servidor. Tente novamente.',
        );
      }
      throw const LoanServiceException(
        'Não foi possível concluir a operação financeira.',
      );
    }
  }

  void clearCache() {
    _cache.clear();
    unawaited(_persistentCache.clearNamespace(_cacheNamespace));
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
      throw LoanServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const LoanServiceException(
        'O servidor retornou dados de empréstimos inválidos.',
      );
    }
    return Map<String, dynamic>.from(raw);
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
    String query,
    AppLoanFilters filters,
    int page,
    int size, {
    bool tutorialMode = false,
  }) {
    final List<String> statuses = filters.statuses.toList()..sort();
    final List<int> regions = filters.regionIds.toList()..sort();
    final String scope = tutorialMode ? 'tutorial' : 'normal';
    return '$scope|${_authService.currentSession?.userId ?? 0}|'
        '${query.trim().toLowerCase()}|${statuses.join(',')}|'
        '${regions.join(',')}|${filters.startDate?.toIso8601String() ?? ''}|'
        '${filters.endDate?.toIso8601String() ?? ''}|$page|$size';
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void _store(
    String key,
    _CachedLoanPage value, {
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
    while (_cache.length > _maximumCachedPages) {
      final String oldest = _cache.keys.first;
      _cache.remove(oldest);
      unawaited(_persistentCache.remove(_cacheNamespace, oldest));
    }
  }

  _CachedLoanPage? _restorePage(String key) {
    final PersistentCacheEntry? stored = _persistentCache.read(
      _cacheNamespace,
      key,
    );
    if (stored?.data is! Map) return null;
    try {
      final AppLoanPage page = AppLoanPage.fromJson(
        Map<String, dynamic>.from(stored!.data as Map),
      );
      final _CachedLoanPage cached = _CachedLoanPage(page, stored.etag);
      _store(key, cached);
      return cached;
    } catch (_) {
      unawaited(_persistentCache.remove(_cacheNamespace, key));
      return null;
    }
  }
}

final class _CachedLoanPage {
  final AppLoanPage data;
  final String? etag;

  const _CachedLoanPage(this.data, this.etag);
}
