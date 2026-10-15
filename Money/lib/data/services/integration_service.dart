import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_integration.dart';
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/network_status_service.dart';

final class IntegrationServiceException implements Exception {
  final String message;
  final int? statusCode;

  const IntegrationServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class IntegrationService {
  IntegrationService._({http.Client? client})
    : _client = client ?? http.Client();

  static final IntegrationService _instance = IntegrationService._();

  factory IntegrationService() => _instance;

  static const Duration _timeout = Duration(seconds: 45);
  final http.Client _client;
  final AuthService _auth = AuthService();
  final NetworkStatusService _network = NetworkStatusService();

  Future<List<AppBankAccount>> fetchBankAccounts() async =>
      _list('/api/v2/integrations/banking/accounts', AppBankAccount.fromJson);

  Future<AppBankAccount> createBankAccount({
    required String name,
    required List<int> regionIds,
  }) => _object(
    'POST',
    '/api/v2/integrations/banking/accounts',
    AppBankAccount.fromJson,
    data: {'name': name, 'regionIds': regionIds},
  );

  Future<AppBankAccount> updateBankAccount(
    int id, {
    String? name,
    List<int>? regionIds,
  }) => _object(
    'PUT',
    '/api/v2/integrations/banking/accounts/$id',
    AppBankAccount.fromJson,
    data: {'name': ?name, 'regionIds': ?regionIds},
  );

  Future<AppBankAccount> saveSicredi(
    int id, {
    required bool active,
    String? clientId,
    String? clientSecret,
    String? pixKey,
  }) => _object(
    'PUT',
    '/api/v2/integrations/banking/accounts/$id/sicredi',
    AppBankAccount.fromJson,
    data: {
      'active': active,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'pixKey': pixKey,
    },
  );

  Future<AppBankAccount> uploadSicrediFiles(
    int id, {
    XFile? certificate,
    XFile? privateKey,
    XFile? certificateChain,
  }) async {
    try {
      final http.MultipartRequest request = http.MultipartRequest(
        'POST',
        _uri('/api/v2/integrations/banking/accounts/$id/certificates'),
      )..headers.addAll(_headers);
      if (certificate != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'certificate',
            await certificate.readAsBytes(),
            filename: certificate.name,
          ),
        );
      }
      if (privateKey != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'privateKey',
            await privateKey.readAsBytes(),
            filename: privateKey.name,
          ),
        );
      }
      if (certificateChain != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'certificateChain',
            await certificateChain.readAsBytes(),
            filename: certificateChain.name,
          ),
        );
      }
      final http.Response response = await http.Response.fromStream(
        await request.send().timeout(_timeout),
      );
      final Map<String, dynamic> envelope = _decode(response);
      _network.reportSuccessfulRequest();
      return AppBankAccount.fromJson(_responseMap(envelope));
    } catch (error) {
      _throw(error, 'Não foi possível enviar os certificados Sicredi.');
    }
  }

  Future<AppWhatsappConfig> fetchWhatsappConfig() => _object(
    'GET',
    '/api/v2/integrations/whatsapp/config',
    AppWhatsappConfig.fromJson,
  );

  Future<AppWhatsappConfig> saveWhatsappConfig(Map<String, dynamic> data) =>
      _object(
        'PUT',
        '/api/v2/integrations/whatsapp/config',
        AppWhatsappConfig.fromJson,
        data: data,
      );

  Future<List<AppWhatsappDevice>> fetchWhatsappDevices() => _list(
    '/api/v2/integrations/whatsapp/devices',
    AppWhatsappDevice.fromJson,
  );

  Future<List<AppWhatsappDevice>> fetchWhatsappDeviceProgress() => _list(
    '/api/v2/integrations/whatsapp/devices/progress',
    AppWhatsappDevice.fromJson,
  );

  Future<AppWhatsappDevice> refreshWhatsappDevice(int id) => _object(
    'POST',
    '/api/v2/integrations/whatsapp/devices/$id/refresh',
    AppWhatsappDevice.fromJson,
  );

  Future<AppWhatsappDevice> updateWhatsappDeviceRegions(
    int id,
    List<int> regionIds,
  ) => _object(
    'PUT',
    '/api/v2/integrations/whatsapp/devices/$id/regions',
    AppWhatsappDevice.fromJson,
    data: {'regionIds': regionIds},
  );

  Future<AppWhatsappLog> testWhatsappDevice(int id, String phone) => _object(
    'POST',
    '/api/v2/integrations/whatsapp/devices/$id/test',
    AppWhatsappLog.fromJson,
    data: {'phone': phone},
  );

  Future<String> startWhatsappDispatch(int id, String type) async {
    final Map<String, dynamic> response = await _request(
      'POST',
      '/api/v2/integrations/whatsapp/devices/$id/dispatch',
      data: {'type': type},
    );
    return _responseMap(response)['message']?.toString() ?? 'Disparo iniciado.';
  }

  Future<AppWhatsappDevice> stopWhatsappDispatch(int id) => _object(
    'POST',
    '/api/v2/integrations/whatsapp/devices/$id/stop',
    AppWhatsappDevice.fromJson,
  );

  Future<List<AppWhatsappLog>> fetchWhatsappLogs() =>
      _list('/api/v2/integrations/whatsapp/logs', AppWhatsappLog.fromJson);

  Future<void> clearWhatsappLogs() async {
    await _request('DELETE', '/api/v2/integrations/whatsapp/logs');
  }

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) parser,
  ) async {
    final Map<String, dynamic> envelope = await _request('GET', path);
    final Object? raw = envelope['responseBody'];
    if (raw is! List) {
      throw const IntegrationServiceException(
        'O servidor retornou dados de integração inválidos.',
      );
    }
    return raw
        .whereType<Map>()
        .map((item) => parser(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<T> _object<T>(
    String method,
    String path,
    T Function(Map<String, dynamic>) parser, {
    Map<String, dynamic>? data,
  }) async {
    final Map<String, dynamic> envelope = await _request(
      method,
      path,
      data: data,
    );
    return parser(_responseMap(envelope));
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final Uri uri = _uri(path);
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
      final Map<String, dynamic> result = _decode(response);
      _network.reportSuccessfulRequest();
      return result;
    } catch (error) {
      _throw(error, 'Não foi possível concluir a operação de integração.');
    }
  }

  Never _throw(Object error, String fallback) {
    if (error is IntegrationServiceException) throw error;
    if (error is TimeoutException || error is http.ClientException) {
      unawaited(_network.checkNow());
      throw const IntegrationServiceException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    }
    throw IntegrationServiceException(fallback);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = body?['errorMessage']?.toString().trim() ?? '';
      throw IntegrationServiceException(
        message.isEmpty ? 'Não foi possível concluir a solicitação.' : message,
        statusCode: response.statusCode,
      );
    }
    return body ?? const {};
  }

  Map<String, dynamic> _responseMap(Map<String, dynamic> envelope) {
    final Object? raw = envelope['responseBody'];
    if (raw is! Map) {
      throw const IntegrationServiceException(
        'O servidor retornou dados de integração inválidos.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  Uri _uri(String path) =>
      Uri.parse(AuthService.apiBaseUrl).replace(path: path);

  Map<String, String> get _headers => {
    ..._auth.authenticatedHeaders,
    'Accept': 'application/json',
  };
}
