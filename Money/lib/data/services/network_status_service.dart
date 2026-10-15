import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/services/auth_service.dart';

enum NetworkStatus { online, offline }

final class NetworkStatusService with WidgetsBindingObserver {
  NetworkStatusService._();

  static final NetworkStatusService _instance = NetworkStatusService._();

  factory NetworkStatusService() => _instance;

  static const Duration _probeInterval = Duration(seconds: 10);
  static const Duration _probeTimeout = Duration(seconds: 5);

  final http.Client _client = http.Client();
  final ValueNotifier<NetworkStatus> _status = ValueNotifier(
    NetworkStatus.online,
  );

  Timer? _timer;
  Timer? _resumeCheckTimer;
  Future<bool>? _activeCheck;
  bool _started = false;
  bool _foreground = true;
  int _checkGeneration = 0;

  ValueListenable<NetworkStatus> get statusListenable => _status;
  NetworkStatus get status => _status.value;
  bool get isOnline => status == NetworkStatus.online;

  void start() {
    if (_started) return;
    _started = true;
    _foreground = true;
    WidgetsBinding.instance.addObserver(this);
    _scheduleChecks();
    unawaited(checkNow());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _foreground = false;
    _checkGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _resumeCheckTimer?.cancel();
    _resumeCheckTimer = null;
    _activeCheck = null;
  }

  Future<bool> checkNow({bool markOfflineOnFailure = true}) {
    final Future<bool>? activeCheck = _activeCheck;
    if (activeCheck != null) return activeCheck;

    final Future<bool> check = _performCheck(
      markOfflineOnFailure: markOfflineOnFailure,
    );
    _activeCheck = check;
    check.whenComplete(() {
      if (identical(_activeCheck, check)) _activeCheck = null;
    });
    return check;
  }

  void reportSuccessfulRequest() => _setStatus(NetworkStatus.online);

  @visibleForTesting
  void setStatusForTesting(NetworkStatus value) => _setStatus(value);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _checkGeneration++;
        _activeCheck = null;
        _scheduleChecks();
        _resumeCheckTimer?.cancel();
        _resumeCheckTimer = Timer(
          const Duration(milliseconds: 800),
          () => unawaited(_checkAfterResume()),
        );
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        _checkGeneration++;
        _activeCheck = null;
        _timer?.cancel();
        _timer = null;
        _resumeCheckTimer?.cancel();
        _resumeCheckTimer = null;
    }
  }

  Future<void> _checkAfterResume() async {
    if (!_started || !_foreground) return;
    final bool wasOnline = isOnline;
    final bool successful = await checkNow(markOfflineOnFailure: !wasOnline);
    if (successful || !wasOnline || !_started || !_foreground) return;

    _resumeCheckTimer?.cancel();
    _resumeCheckTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(checkNow()),
    );
  }

  Future<bool> _performCheck({required bool markOfflineOnFailure}) async {
    final int generation = _checkGeneration;
    try {
      final Uri base = Uri.parse(AuthService.apiBaseUrl);
      final Uri healthUri = base.replace(
        path: '/api/v2/health',
        queryParameters: const {},
      );
      final http.Response response = await _client
          .get(healthUri, headers: const {'Accept': 'application/json'})
          .timeout(_probeTimeout);
      final bool successful =
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          _reportsHealthy(response.bodyBytes);
      if (_foreground && generation == _checkGeneration) {
        if (successful) {
          _setStatus(NetworkStatus.online);
        } else if (markOfflineOnFailure) {
          _setStatus(NetworkStatus.offline);
        }
      }
      return successful;
    } catch (_) {
      if (_foreground &&
          generation == _checkGeneration &&
          markOfflineOnFailure) {
        _setStatus(NetworkStatus.offline);
      }
      return false;
    }
  }

  bool _reportsHealthy(List<int> bytes) {
    if (bytes.isEmpty) return false;
    try {
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map && decoded['status'] == 'UP';
    } catch (_) {
      return false;
    }
  }

  void _scheduleChecks() {
    if (!_started || _timer != null) return;
    _timer = Timer.periodic(_probeInterval, (_) => unawaited(checkNow()));
  }

  void _setStatus(NetworkStatus value) {
    if (_status.value == value) return;
    _status.value = value;
  }
}
