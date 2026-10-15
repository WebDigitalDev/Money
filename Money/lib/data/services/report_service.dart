import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:money/data/models/app_report.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';

final class ReportServiceException implements Exception {
  final String message;
  final int? statusCode;

  const ReportServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

typedef ReportExportDownloadProgress = void Function(double progress);

final class ReportService {
  ReportService._({http.Client? client}) : _client = client ?? http.Client();

  static final ReportService _instance = ReportService._();

  factory ReportService() => _instance;

  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatus = NetworkStatusService();
  List<String>? _userOptions;

  Future<AppAuditHistoryPage> fetchHistory({
    required AppAuditHistoryFilters filters,
    required int page,
    int size = 250,
  }) async {
    try {
      final http.Response response = await _client
          .get(
            _uri('/api/v2/reports/history', {
              ..._filterParameters(filters),
              'page': '$page',
              'size': '$size',
            }),
            headers: _headers,
          )
          .timeout(_timeout);
      final AppAuditHistoryPage result = AppAuditHistoryPage.fromJson(
        _responseMap(_decode(response)),
      );
      _networkStatus.reportSuccessfulRequest();
      return result;
    } catch (error) {
      throw _readException(error, 'Não foi possível carregar o histórico.');
    }
  }

  Future<List<AppAuditHistoryItem>> fetchHistoryForExport({
    required AppAuditHistoryFilters filters,
    ReportExportDownloadProgress? onProgress,
  }) async {
    final Uri uri = _uri(
      '/api/v2/reports/history/export-data',
      _filterParameters(filters),
    );
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
      final AppAuditHistoryPage result = AppAuditHistoryPage.fromJson(
        _responseMap(_decode(response)),
      );
      _networkStatus.reportSuccessfulRequest();
      onProgress?.call(1);
      return result.items;
    } catch (error) {
      throw _readException(
        error,
        'Não foi possível preparar os dados da exportação.',
      );
    }
  }

  Future<List<String>> fetchHistoryUsers({bool force = false}) async {
    if (!force && _userOptions != null) return _userOptions!;
    try {
      final http.Response response = await _client
          .get(_uri('/api/v2/reports/history/users'), headers: _headers)
          .timeout(_timeout);
      final Object? raw = _decode(response)['responseBody'];
      if (raw is! List) {
        throw const ReportServiceException(
          'O servidor retornou usuários inválidos.',
        );
      }
      final List<String> result = raw
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      _userOptions = result;
      _networkStatus.reportSuccessfulRequest();
      return result;
    } catch (error) {
      throw _readException(error, 'Não foi possível carregar os usuários.');
    }
  }

  Map<String, String> _filterParameters(AppAuditHistoryFilters filters) {
    final List<int> regionIds = filters.regionIds.toList()..sort();
    return {
      'startDate': _formatDate(filters.startDate),
      'endDate': _formatDate(filters.endDate),
      if (filters.usernames.isNotEmpty)
        'usernames': (filters.usernames.toList()..sort()).join(','),
      if (regionIds.isNotEmpty) 'regionIds': regionIds.join(','),
    };
  }

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final Uri base = Uri.parse(AuthService.apiBaseUrl);
    return base.replace(path: path, queryParameters: queryParameters);
  }

  Map<String, String> get _headers => {
    ..._authService.authenticatedHeaders,
    'Accept': 'application/json',
  };

  Map<String, dynamic> _decode(http.Response response) {
    final Object? decoded = response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
    final Map<String, dynamic>? body = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body?['errorMessage']?.toString().trim() ?? '';
      throw ReportServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const ReportServiceException(
        'O servidor retornou dados de relatório inválidos.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  ReportServiceException _readException(Object error, String fallback) {
    if (error is ReportServiceException) return error;
    if (error is TimeoutException || error is http.ClientException) {
      unawaited(_networkStatus.checkNow());
      return const ReportServiceException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    }
    return ReportServiceException(fallback);
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
