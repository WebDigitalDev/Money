import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:money/data/models/app_conference.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/client_service.dart';
import 'package:money/data/services/network_status_service.dart';

final class ConferenceServiceException implements Exception {
  final String message;
  final int? statusCode;

  const ConferenceServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class ConferenceService {
  ConferenceService._({http.Client? client})
    : _client = client ?? http.Client();

  static final ConferenceService _instance = ConferenceService._();

  factory ConferenceService() => _instance;

  static const Duration _timeout = Duration(seconds: 30);
  final http.Client _client;
  final AuthService _auth = AuthService();
  final NetworkStatusService _network = NetworkStatusService();

  Future<AppConferenceListData> fetch({
    required AppConferenceCategory category,
    String query = '',
    Set<int> regionIds = const {},
  }) async {
    final Map<String, dynamic> response = await _request(
      'GET',
      '/api/v2/conferences',
      query: {
        'query': query.trim(),
        'category': category.apiValue,
        if (regionIds.isNotEmpty)
          'regionIds': (regionIds.toList()..sort()).join(','),
        'size': '200',
        'includeDetails': 'false',
      },
    );
    return AppConferenceListData.fromJson(_responseMap(response));
  }

  Future<List<AppConferenceDetail>> fetchDetails(int id) async {
    final Map<String, dynamic> response = await _request(
      'GET',
      '/api/v2/conferences/$id/details',
    );
    final Object? rawDetails = _responseMap(response)['details'];
    if (rawDetails is! List) return const [];
    return rawDetails
        .whereType<Map>()
        .map(
          (detail) =>
              AppConferenceDetail.fromJson(Map<String, dynamic>.from(detail)),
        )
        .toList(growable: false);
  }

  Future<String> decide(
    int id, {
    required bool approve,
    String? observation,
  }) async {
    final Map<String, dynamic> response = await _request(
      'POST',
      '/api/v2/conferences/$id/${approve ? 'approve' : 'reject'}',
      data: {'observation': observation?.trim()},
    );
    ClientService().clearCache();
    return _responseMap(response)['message']?.toString().trim() ??
        (approve ? 'Operação conferida.' : 'Operação indeferida.');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? data,
  }) async {
    try {
      final Uri uri = Uri.parse(
        AuthService.apiBaseUrl,
      ).replace(path: path, queryParameters: query);
      final Map<String, String> headers = {
        ..._auth.authenticatedHeaders,
        'Accept': 'application/json',
      };
      final http.Response response = method == 'POST'
          ? await _client
                .post(uri, headers: headers, body: jsonEncode(data ?? const {}))
                .timeout(_timeout)
          : await _client.get(uri, headers: headers).timeout(_timeout);
      final Map<String, dynamic> result = _decode(response);
      _network.reportSuccessfulRequest();
      return result;
    } catch (error) {
      if (error is ConferenceServiceException) rethrow;
      if (error is TimeoutException || error is http.ClientException) {
        unawaited(_network.checkNow());
        throw const ConferenceServiceException(
          'Não foi possível conectar ao servidor.',
        );
      }
      throw const ConferenceServiceException(
        'Não foi possível concluir a conferência.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body?['errorMessage']?.toString().trim() ?? '';
      throw ConferenceServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const ConferenceServiceException(
        'O servidor retornou dados de conferência inválidos.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }
}
