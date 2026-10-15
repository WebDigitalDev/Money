import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_financial_goal.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';
import 'package:money/data/services/persistent_cache_service.dart';

final class FinancialGoalServiceException implements Exception {
  final String message;
  final int? statusCode;

  const FinancialGoalServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class FinancialGoalService {
  FinancialGoalService._({http.Client? client})
    : _client = client ?? http.Client();

  static final FinancialGoalService _instance = FinancialGoalService._();

  factory FinancialGoalService() => _instance;

  @visibleForTesting
  FinancialGoalService.forTesting(http.Client client) : _client = client;

  static const Duration _timeout = Duration(seconds: 40);

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatus = NetworkStatusService();

  List<AppFinancialGoal> get cachedGoals {
    final id = _authService.currentSession?.userId;
    if (id == null) return const [];
    final raw = PersistentCacheService().read('goals', '$id')?.data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AppFinancialGoal.fromJson(Map<String, dynamic>.from(e)))
        .where((goal) => goal.isVisibleInGoalsAt(DateTime.now()))
        .toList();
  }

  Future<List<AppFinancialGoal>> fetchGoals() async {
    final userId = _authService.currentSession?.userId;
    final Map<String, dynamic> envelope = await _send('GET', _uri, null);
    final Object? raw = envelope['responseBody'];
    if (raw is! List) {
      throw const FinancialGoalServiceException(
        'O servidor retornou metas financeiras inválidas.',
      );
    }
    final DateTime now = DateTime.now();
    final List<Map<String, dynamic>> visibleRaw = [];
    final List<AppFinancialGoal> visibleGoals = [];
    for (final Map item in raw.whereType<Map>()) {
      final Map<String, dynamic> json = Map<String, dynamic>.from(item);
      final AppFinancialGoal goal = AppFinancialGoal.fromJson(json);
      if (!goal.isVisibleInGoalsAt(now)) continue;
      visibleRaw.add(json);
      visibleGoals.add(goal);
    }
    if (userId != null && userId == _authService.currentSession?.userId) {
      unawaited(
        PersistentCacheService().write('goals', '$userId', data: visibleRaw),
      );
    }
    return List<AppFinancialGoal>.unmodifiable(visibleGoals);
  }

  Future<AppFinancialGoal> createGoal(AppFinancialGoalDraft draft) async {
    final Map<String, dynamic> envelope = await _send(
      'POST',
      _uri,
      draft.toJson(),
    );
    return AppFinancialGoal.fromJson(_responseMap(envelope));
  }

  Future<AppFinancialGoal> updateGoal(
    int id,
    AppFinancialGoalDraft draft,
  ) async {
    final Map<String, dynamic> envelope = await _send(
      'PUT',
      _uri.replace(path: '${_uri.path}/$id'),
      draft.toJson(),
    );
    return AppFinancialGoal.fromJson(_responseMap(envelope));
  }

  Future<void> deleteGoal(int id) async {
    await _send('DELETE', _uri.replace(path: '${_uri.path}/$id'), null);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(_timeout);
      final http.Response response = await http.Response.fromStream(streamed);
      final Map<String, dynamic> result = _decode(response);
      _networkStatus.reportSuccessfulRequest();
      return result;
    } on FinancialGoalServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatus.checkNow());
      throw const FinancialGoalServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatus.checkNow());
      throw const FinancialGoalServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } on Object {
      throw const FinancialGoalServiceException(
        'Não foi possível concluir a operação com a meta financeira.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Object? decoded = response.bodyBytes.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes));
    final Map<String, dynamic> result = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = result['errorMessage']?.toString().trim() ?? '';
      throw FinancialGoalServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return result;
  }

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const FinancialGoalServiceException(
        'O servidor retornou uma meta financeira inválida.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  Uri get _uri {
    final Uri base = Uri.parse(AuthService.apiBaseUrl);
    return base.replace(path: '/api/v2/financial-goals');
  }

  Map<String, String> get _headers => {
    ..._authService.authenticatedHeaders,
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
}
