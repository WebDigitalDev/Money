import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:money/data/models/app_chat.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';

final class ChatServiceException implements Exception {
  final String message;
  final int? statusCode;

  const ChatServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class AppChatPdfFile {
  final Uint8List bytes;
  final String fileName;

  const AppChatPdfFile({required this.bytes, required this.fileName});
}

final class AppChatUpload {
  final String fileName;
  final Uint8List bytes;

  const AppChatUpload({required this.fileName, required this.bytes});
}

final class ChatService {
  ChatService._({http.Client? client}) : _client = client ?? http.Client();

  static final ChatService _instance = ChatService._();

  factory ChatService() => _instance;

  final http.Client _client;
  final AuthService _authService = AuthService();
  final NetworkStatusService _networkStatus = NetworkStatusService();

  Future<AppCodexConnection> codexStatus() async {
    final Map<String, dynamic> body = await _jsonRequest(
      method: 'GET',
      path: '/api/v2/codex/status',
      timeout: const Duration(seconds: 30),
      fallbackError: 'Não foi possível verificar a conexão com o ChatGPT.',
    );
    return AppCodexConnection.fromJson(_responseBody(body));
  }

  Future<AppCodexLoginChallenge> connectCodex() async {
    final Map<String, dynamic> body = await _jsonRequest(
      method: 'POST',
      path: '/api/v2/codex/connect',
      timeout: const Duration(seconds: 30),
      fallbackError: 'Não foi possível iniciar a conexão com o ChatGPT.',
    );
    return AppCodexLoginChallenge.fromJson(_responseBody(body));
  }

  Future<void> disconnectCodex() async {
    await _jsonRequest(
      method: 'DELETE',
      path: '/api/v2/codex/connection',
      timeout: const Duration(seconds: 30),
      fallbackError: 'Não foi possível desconectar a conta ChatGPT.',
      allowEmptyResponse: true,
    );
  }

  Future<void> interruptCodex(String conversationId) async {
    final String encoded = Uri.encodeQueryComponent(conversationId);
    await _jsonRequest(
      method: 'POST',
      path: '/api/v2/codex/interrupt?conversationId=$encoded',
      timeout: const Duration(seconds: 10),
      fallbackError: 'Não foi possível interromper a resposta.',
      allowEmptyResponse: true,
    );
  }

  Future<AppChatResponse> query({
    required String message,
    required String conversationId,
    String mode = 'READY',
    int? clientId,
    int? regionId,
    String? model,
    String? serviceTier,
    List<AppChatUpload> attachments = const [],
  }) async {
    if (attachments.isNotEmpty) {
      return _queryWithFiles(
        message: message,
        conversationId: conversationId,
        mode: mode,
        clientId: clientId,
        regionId: regionId,
        model: model,
        serviceTier: serviceTier,
        attachments: attachments,
      );
    }
    final Uri uri = Uri.parse('${AuthService.apiBaseUrl}/api/v2/codex/query');
    try {
      final http.Response response = await _client
          .post(
            uri,
            headers: {
              ..._authService.authenticatedHeaders,
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'message': message.trim(),
              'conversationId': conversationId,
              'mode': mode,
              'clientId': ?clientId,
              'regionId': ?regionId,
              'model': ?model,
              'serviceTier': ?serviceTier,
            }),
          )
          .timeout(const Duration(seconds: 190));
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const {};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String message = body['errorMessage']?.toString().trim() ?? '';
        throw ChatServiceException(
          message.isEmpty ? 'Não foi possível concluir a consulta.' : message,
          statusCode: response.statusCode,
        );
      }
      final Object? rawResponse = body['responseBody'];
      if (rawResponse is! Map) {
        throw const ChatServiceException(
          'O servidor retornou uma resposta inválida.',
        );
      }
      _networkStatus.reportSuccessfulRequest();
      return AppChatResponse.fromJson(Map<String, dynamic>.from(rawResponse));
    } on ChatServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'A consulta demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } on FormatException {
      throw const ChatServiceException(
        'O servidor retornou uma resposta inválida.',
      );
    }
  }

  Future<AppChatResponse> _queryWithFiles({
    required String message,
    required String conversationId,
    required String mode,
    required List<AppChatUpload> attachments,
    int? clientId,
    int? regionId,
    String? model,
    String? serviceTier,
  }) async {
    final Uri uri = Uri.parse(
      '${AuthService.apiBaseUrl}/api/v2/codex/query-with-files',
    );
    try {
      final http.MultipartRequest request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          ..._authService.authenticatedHeaders,
          'Accept': 'application/json',
        })
        ..fields.addAll({
          'message': message.trim(),
          'conversationId': conversationId,
          'mode': mode,
          if (clientId != null) 'clientId': '$clientId',
          if (regionId != null) 'regionId': '$regionId',
          if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
          if (serviceTier != null && serviceTier.trim().isNotEmpty)
            'serviceTier': serviceTier.trim(),
        });
      for (final AppChatUpload attachment in attachments) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            attachment.bytes,
            filename: attachment.fileName,
          ),
        );
      }
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 190));
      final http.Response response = await http.Response.fromStream(streamed);
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const {};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String serverMessage =
            body['errorMessage']?.toString().trim() ?? '';
        throw ChatServiceException(
          serverMessage.isEmpty
              ? 'Não foi possível concluir a consulta.'
              : serverMessage,
          statusCode: response.statusCode,
        );
      }
      _networkStatus.reportSuccessfulRequest();
      return AppChatResponse.fromJson(_responseBody(body));
    } on ChatServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'A consulta demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } on FormatException {
      throw const ChatServiceException(
        'O servidor retornou uma resposta inválida.',
      );
    }
  }

  Future<AppChatPdfFile> exportSummaryPdf(AppChatSummaryContext summary) async {
    final Map<String, String> query = {'regionId': '${summary.regionId}'};
    if (summary.startDate != null && summary.endDate != null) {
      query['startDate'] = _date(summary.startDate!);
      query['endDate'] = _date(summary.endDate!);
    }
    final Uri uri = Uri.parse(
      '${AuthService.apiBaseUrl}/api/v2/chat/summary-pdf',
    ).replace(queryParameters: query);
    try {
      final http.Response response = await _client
          .get(
            uri,
            headers: {
              ..._authService.authenticatedHeaders,
              'Accept': 'application/pdf',
            },
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = 'Não foi possível gerar o resumo em PDF.';
        try {
          final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map) {
            final String serverMessage =
                decoded['errorMessage']?.toString().trim() ?? '';
            if (serverMessage.isNotEmpty) message = serverMessage;
          }
        } on Object {
          // Mantém a mensagem segura quando a falha não retorna JSON.
        }
        throw ChatServiceException(message);
      }
      _networkStatus.reportSuccessfulRequest();
      return AppChatPdfFile(
        bytes: response.bodyBytes,
        fileName: _pdfFileName(
          response.headers['content-disposition'],
          summary.regionName,
        ),
      );
    } on ChatServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'A geração do PDF demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'Não foi possível conectar ao servidor para gerar o PDF.',
      );
    }
  }

  Future<Map<String, dynamic>> _jsonRequest({
    required String method,
    required String path,
    required Duration timeout,
    required String fallbackError,
    bool allowEmptyResponse = false,
  }) async {
    final Uri uri = Uri.parse('${AuthService.apiBaseUrl}$path');
    try {
      final Map<String, String> headers = {
        ..._authService.authenticatedHeaders,
        'Accept': 'application/json',
      };
      final http.Response response = switch (method) {
        'POST' => await _client.post(uri, headers: headers).timeout(timeout),
        'DELETE' =>
          await _client.delete(uri, headers: headers).timeout(timeout),
        _ => await _client.get(uri, headers: headers).timeout(timeout),
      };
      if (allowEmptyResponse && response.bodyBytes.isEmpty) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _networkStatus.reportSuccessfulRequest();
          return const {};
        }
      }
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final Map<String, dynamic> body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const {};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String serverMessage =
            body['errorMessage']?.toString().trim() ?? '';
        throw ChatServiceException(
          serverMessage.isEmpty ? fallbackError : serverMessage,
          statusCode: response.statusCode,
        );
      }
      _networkStatus.reportSuccessfulRequest();
      return body;
    } on ChatServiceException {
      rethrow;
    } on TimeoutException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      unawaited(_networkStatus.checkNow());
      throw const ChatServiceException(
        'Não foi possível conectar ao servidor.',
      );
    } on FormatException {
      throw const ChatServiceException(
        'O servidor retornou uma resposta inválida.',
      );
    }
  }

  Map<String, dynamic> _responseBody(Map<String, dynamic> envelope) {
    final Object? value = envelope['responseBody'];
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const ChatServiceException(
      'O servidor retornou uma resposta inválida.',
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _pdfFileName(String? disposition, String regionName) {
  final String source = disposition ?? '';
  final RegExpMatch? utf8Name = RegExp(
    r"filename\*=UTF-8''([^;]+)",
    caseSensitive: false,
  ).firstMatch(source);
  if (utf8Name != null) {
    return Uri.decodeComponent(utf8Name.group(1)!.replaceAll('"', '').trim());
  }
  final RegExpMatch? plainName = RegExp(
    r'filename="?([^";]+)"?',
    caseSensitive: false,
  ).firstMatch(source);
  if (plainName != null) return plainName.group(1)!.trim();
  final String clean = regionName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'resumo_financeiro_${clean.isEmpty ? 'regiao' : clean}.pdf';
}
