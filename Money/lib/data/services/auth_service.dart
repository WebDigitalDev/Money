import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/auth_session.dart';
import 'package:money/data/services/persistent_cache_service.dart';

enum AuthenticationFailureKind {
  invalidCredentials,
  forbidden,
  network,
  invalidResponse,
  unknown,
}

final class AuthenticationException implements Exception {
  final String message;
  final AuthenticationFailureKind kind;

  const AuthenticationException(this.message, this.kind);

  @override
  String toString() => message;
}

final class AuthService {
  AuthService._();

  static final AuthService _instance = AuthService._();

  factory AuthService() => _instance;

  static const String apiBaseUrl = String.fromEnvironment(
    'MONEY_API_BASE_URL',
    defaultValue: 'https://decided-triple-html-subcommittee.trycloudflare.com',
  );
  static const String _signInUrl = '$apiBaseUrl/api/v2/auth/signin';
  static const String _changePasswordUrl = '$apiBaseUrl/api/v2/auth/password';
  static const String _completeTutorialUrl = '$apiBaseUrl/api/v2/auth/tutorial';
  static const String _beginTutorialUrl =
      '$apiBaseUrl/api/v2/auth/tutorial/access';
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const String _savedUsernameKey = 'auth.biometric.username';
  static const String _savedPasswordKey = 'auth.biometric.password';
  static const String _lastUsernameKey = 'auth.last.username';
  static const String _savedSessionKey = 'auth.cached.session';
  static const WebOptions _webStorageOptions = WebOptions(
    publicKey: 'MoneySecureStorageV2',
  );

  final http.Client _client = http.Client();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    webOptions: _webStorageOptions,
  );

  AuthSession? _currentSession;
  AuthCredentials? _lastCredentials;
  bool _offlineSession = false;

  AuthSession? get currentSession => _currentSession;
  bool get isOfflineSession => _offlineSession;

  Map<String, String> get authenticatedHeaders {
    final AuthSession? session = _currentSession;
    if (session == null) return const {'Content-Type': 'application/json'};

    return {
      'Content-Type': 'application/json',
      'Authorization': session.authorizationHeader,
    };
  }

  Future<AuthSession> signIn({
    required String username,
    required String password,
  }) async {
    final String normalizedUsername = username.trim().toUpperCase();

    try {
      final http.Response response = await _client
          .post(
            Uri.parse(_signInUrl),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'username': normalizedUsername,
              'password': password,
            }),
          )
          .timeout(_requestTimeout);

      final Map<String, dynamic>? responseJson = _decodeBody(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String serverMessage =
            responseJson?['errorMessage']?.toString().trim() ?? '';
        final bool invalidCredentials = serverMessage.toLowerCase().contains(
          'usuário/senha inválido',
        );

        throw AuthenticationException(
          serverMessage.isEmpty
              ? 'Não foi possível entrar. Tente novamente.'
              : serverMessage,
          invalidCredentials
              ? AuthenticationFailureKind.invalidCredentials
              : response.statusCode == 403
              ? AuthenticationFailureKind.forbidden
              : AuthenticationFailureKind.unknown,
        );
      }

      final Object? rawResponseBody = responseJson?['responseBody'];
      if (rawResponseBody is! Map) {
        throw const AuthenticationException(
          'O servidor retornou uma resposta inválida.',
          AuthenticationFailureKind.invalidResponse,
        );
      }

      final AuthSession session;
      try {
        session = AuthSession.fromJson(
          Map<String, dynamic>.from(rawResponseBody),
        );
      } on FormatException {
        throw const AuthenticationException(
          'O servidor retornou uma resposta de login incompleta.',
          AuthenticationFailureKind.invalidResponse,
        );
      }

      _currentSession = session;
      _offlineSession = false;
      PersistentCacheService().resumeWrites();
      _lastCredentials = AuthCredentials(
        username: normalizedUsername,
        password: password,
      );
      return session;
    } on AuthenticationException {
      rethrow;
    } on TimeoutException {
      throw const AuthenticationException(
        'O servidor demorou para responder. Verifique sua conexão.',
        AuthenticationFailureKind.network,
      );
    } on http.ClientException {
      throw const AuthenticationException(
        'Não foi possível conectar ao servidor.',
        AuthenticationFailureKind.network,
      );
    } on FormatException {
      throw const AuthenticationException(
        'O servidor retornou uma resposta inválida.',
        AuthenticationFailureKind.invalidResponse,
      );
    } catch (_) {
      throw const AuthenticationException(
        'Não foi possível entrar. Tente novamente.',
        AuthenticationFailureKind.unknown,
      );
    }
  }

  Future<AuthSession> signInWithSavedCredentials() async {
    final AuthCredentials? credentials = await savedCredentials;
    if (credentials == null) {
      throw const AuthenticationException(
        'Entre novamente com seu usuário e senha.',
        AuthenticationFailureKind.invalidCredentials,
      );
    }

    final AuthSession session = await signIn(
      username: credentials.username,
      password: credentials.password,
    );
    await _writeSavedSession(session);
    return session;
  }

  Future<bool> restoreOfflineSession({
    String? username,
    String? password,
  }) async {
    try {
      final AuthCredentials? credentials = await savedCredentials;
      if (credentials == null) return false;

      if (username != null &&
          credentials.username != username.trim().toUpperCase()) {
        return false;
      }
      if (password != null && credentials.password != password) return false;

      final String? rawSession = await _secureStorage.read(
        key: _savedSessionKey,
      );
      if (rawSession == null || rawSession.isEmpty) return false;
      final Object? decoded = jsonDecode(rawSession);
      if (decoded is! Map) return false;

      _currentSession = AuthSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      PersistentCacheService().resumeWrites();
      _lastCredentials = credentials;
      _offlineSession = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<AuthSession> changeRequiredPassword(String password) async {
    final AuthSession? currentSession = _currentSession;
    if (currentSession == null) {
      throw const AuthenticationException(
        'Sua sessão expirou. Entre novamente.',
        AuthenticationFailureKind.invalidCredentials,
      );
    }

    try {
      final http.Response response = await _client
          .put(
            Uri.parse(_changePasswordUrl),
            headers: {'Accept': 'application/json', ...authenticatedHeaders},
            body: jsonEncode({'password': password}),
          )
          .timeout(_requestTimeout);
      final Map<String, dynamic>? responseJson = _decodeBody(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String serverMessage =
            responseJson?['errorMessage']?.toString().trim() ?? '';
        throw AuthenticationException(
          serverMessage.isEmpty
              ? 'Não foi possível alterar a senha.'
              : serverMessage,
          response.statusCode == 401
              ? AuthenticationFailureKind.invalidCredentials
              : response.statusCode == 403
              ? AuthenticationFailureKind.forbidden
              : AuthenticationFailureKind.unknown,
        );
      }

      final Object? rawResponseBody = responseJson?['responseBody'];
      if (rawResponseBody is! Map) {
        throw const AuthenticationException(
          'O servidor retornou uma resposta inválida.',
          AuthenticationFailureKind.invalidResponse,
        );
      }
      final AuthSession updatedSession = AuthSession.fromJson(
        Map<String, dynamic>.from(rawResponseBody),
      );
      _currentSession = updatedSession;
      _lastCredentials = AuthCredentials(
        username: updatedSession.name.trim().toUpperCase(),
        password: password,
      );
      try {
        await saveCredentials();
      } catch (_) {}
      return updatedSession;
    } on AuthenticationException {
      rethrow;
    } on TimeoutException {
      throw const AuthenticationException(
        'O servidor demorou para responder. Tente novamente.',
        AuthenticationFailureKind.network,
      );
    } on http.ClientException {
      throw const AuthenticationException(
        'Não foi possível conectar ao servidor.',
        AuthenticationFailureKind.network,
      );
    } on FormatException {
      throw const AuthenticationException(
        'O servidor retornou uma resposta inválida.',
        AuthenticationFailureKind.invalidResponse,
      );
    } catch (_) {
      throw const AuthenticationException(
        'Não foi possível alterar a senha. Tente novamente.',
        AuthenticationFailureKind.unknown,
      );
    }
  }

  Future<AuthSession> completeTutorial() async {
    final AuthSession? currentSession = _currentSession;
    if (currentSession == null) {
      throw const AuthenticationException(
        'Sua sessão expirou. Entre novamente.',
        AuthenticationFailureKind.invalidCredentials,
      );
    }
    if (_offlineSession) {
      throw const AuthenticationException(
        'Conecte-se à internet para concluir o tutorial.',
        AuthenticationFailureKind.network,
      );
    }

    try {
      final http.Response response = await _client
          .put(
            Uri.parse(_completeTutorialUrl),
            headers: {'Accept': 'application/json', ...authenticatedHeaders},
          )
          .timeout(_requestTimeout);
      final Map<String, dynamic>? responseJson = _decodeBody(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String serverMessage =
            responseJson?['errorMessage']?.toString().trim() ?? '';
        throw AuthenticationException(
          serverMessage.isEmpty
              ? 'Não foi possível concluir o tutorial.'
              : serverMessage,
          response.statusCode == 401
              ? AuthenticationFailureKind.invalidCredentials
              : response.statusCode == 403
              ? AuthenticationFailureKind.forbidden
              : AuthenticationFailureKind.unknown,
        );
      }

      final Object? rawResponseBody = responseJson?['responseBody'];
      if (rawResponseBody is! Map) {
        throw const AuthenticationException(
          'O servidor retornou uma resposta inválida.',
          AuthenticationFailureKind.invalidResponse,
        );
      }
      final AuthSession updatedSession = AuthSession.fromJson(
        Map<String, dynamic>.from(rawResponseBody),
      );
      _currentSession = updatedSession;
      await _writeSavedSession(updatedSession);
      return updatedSession;
    } on AuthenticationException {
      rethrow;
    } on TimeoutException {
      throw const AuthenticationException(
        'O servidor demorou para responder. Tente novamente.',
        AuthenticationFailureKind.network,
      );
    } on http.ClientException {
      throw const AuthenticationException(
        'Não foi possível conectar ao servidor.',
        AuthenticationFailureKind.network,
      );
    } on FormatException {
      throw const AuthenticationException(
        'O servidor retornou uma resposta inválida.',
        AuthenticationFailureKind.invalidResponse,
      );
    } catch (_) {
      throw const AuthenticationException(
        'Não foi possível concluir o tutorial. Tente novamente.',
        AuthenticationFailureKind.unknown,
      );
    }
  }

  Future<void> beginTutorial() async {
    if (_currentSession == null) {
      throw const AuthenticationException(
        'Sua sessão expirou. Entre novamente.',
        AuthenticationFailureKind.invalidCredentials,
      );
    }
    try {
      final http.Response response = await _client
          .post(
            Uri.parse(_beginTutorialUrl),
            headers: {'Accept': 'application/json', ...authenticatedHeaders},
          )
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String message =
            _decodeBody(response)?['errorMessage']?.toString().trim() ?? '';
        throw AuthenticationException(
          message.isEmpty
              ? 'Não foi possível preparar os dados do tutorial.'
              : message,
          AuthenticationFailureKind.unknown,
        );
      }
    } on AuthenticationException {
      rethrow;
    } on TimeoutException {
      throw const AuthenticationException(
        'O servidor demorou para preparar o tutorial.',
        AuthenticationFailureKind.network,
      );
    } on http.ClientException {
      throw const AuthenticationException(
        'Não foi possível conectar ao servidor para iniciar o tutorial.',
        AuthenticationFailureKind.network,
      );
    }
  }

  Future<AuthCredentials?> get savedCredentials async {
    final String? username = await _secureStorage.read(key: _savedUsernameKey);
    final String? password = await _secureStorage.read(key: _savedPasswordKey);

    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    return AuthCredentials(username: username, password: password);
  }

  Future<bool> hasSavedCredentials() async {
    return await savedCredentials != null;
  }

  Future<String?> get savedUsername async {
    final String? lastUsername = await _secureStorage.read(
      key: _lastUsernameKey,
    );
    if (lastUsername != null && lastUsername.isNotEmpty) {
      return lastUsername;
    }

    final String? credentialsUsername = await _secureStorage.read(
      key: _savedUsernameKey,
    );
    if (credentialsUsername == null || credentialsUsername.isEmpty) {
      return null;
    }

    return credentialsUsername;
  }

  Future<void> saveCredentials() async {
    final AuthCredentials? credentials = _lastCredentials;
    if (credentials == null) {
      throw const AuthenticationException(
        'Entre novamente para salvar seu acesso.',
        AuthenticationFailureKind.invalidCredentials,
      );
    }

    // The web implementation creates its encryption key on the first write.
    // Keep these operations sequential so every value uses the same key.
    await _secureStorage.write(
      key: _savedUsernameKey,
      value: credentials.username,
    );
    await _secureStorage.write(
      key: _savedPasswordKey,
      value: credentials.password,
    );
    await _secureStorage.write(
      key: _lastUsernameKey,
      value: credentials.username,
    );
    final AuthSession? session = _currentSession;
    if (session != null) await _writeSavedSession(session);
  }

  Future<void> clearSavedCredentials() async {
    final String? username = await _secureStorage.read(key: _savedUsernameKey);
    if (username != null && username.isNotEmpty) {
      await _secureStorage.write(key: _lastUsernameKey, value: username);
    }

    await _secureStorage.delete(key: _savedUsernameKey);
    await _secureStorage.delete(key: _savedPasswordKey);
    await _secureStorage.delete(key: _savedSessionKey);
    await PersistentCacheService().clearAll(suspendWrites: true);
  }

  Future<void> signOut() async {
    _currentSession = null;
    _lastCredentials = null;
    _offlineSession = false;
    await clearSavedCredentials();
  }

  Future<void> _writeSavedSession(AuthSession session) {
    return _secureStorage.write(
      key: _savedSessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Map<String, dynamic>? _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;

    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }
}
