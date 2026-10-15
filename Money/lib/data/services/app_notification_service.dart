import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/services/auth_service.dart';
import 'package:money/data/services/notification_preferences_store.dart';

class AppNotification {
  final int id;
  final String kind, title, body;
  final DateTime createdAt, expiresAt;
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
  });
  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] as num).toInt(),
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
  bool visibleAt(DateTime now) => expiresAt.isAfter(now);
}

/// Events originate in Money's authenticated API, without a third-party push
/// provider. OS suspension may pause polling; history remains on the server.
class AppNotificationService extends ChangeNotifier {
  AppNotificationService._();
  static final instance = AppNotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  final _http = http.Client();
  final _preferences = NotificationPreferencesStore();
  final _events = StreamController<AppNotification>.broadcast();
  Stream<AppNotification> get alerts => _events.stream;
  Timer? _timer;
  Timer? _expiryTimer;
  DateTime? _paymentsSince, _goalsSince;
  int? _user;
  int _generation = 0;
  bool _busy = false, _ready = false, _baseline = false;
  bool payments = false, goals = false;
  bool historyOpen = false;
  int _ticks = 0;
  List<AppNotification> _items = [];
  final Set<int> _seen = {};
  List<AppNotification> get items =>
      _items.where((n) => n.visibleAt(DateTime.now())).toList();

  Future<void> start() async {
    final user = AuthService().currentSession?.userId;
    if (user == null) return;
    if (_user == user && _timer != null) return;
    stop();
    _user = user;
    final generation = _generation;
    try {
      await loadPreferences();
      await refresh();
    } catch (_) {
      /* Pages expose retry; background polling must not block login. */
    }
    if (generation != _generation) return;
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      _ticks++;
      if (payments || goals || historyOpen || _ticks % 3 == 0) {
        unawaited(_poll());
      }
      notifyListeners(); // Expire visible history even with alerts disabled.
    });
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _expiryTimer?.cancel();
    _timer = null;
    _user = null;
    _items = [];
    _seen.clear();
    payments = false;
    goals = false;
    _baseline = false;
    _paymentsSince = null;
    _goalsSince = null;
    unawaited(_cancelDeviceNotifications());
  }

  Future<void> _cancelDeviceNotifications() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> _poll() async {
    try {
      await loadPreferences();
      if (payments || goals || historyOpen) await refresh();
    } catch (_) {}
  }

  Future<void> loadPreferences() async {
    final generation = _generation;
    final user = _user;
    if (user == null) return;
    final result = await _preferences.read(user);
    if (generation != _generation) return;
    final map = result;
    payments = map['payments'] == true;
    goals = map['goals'] == true;
    _paymentsSince = DateTime.tryParse('${map['paymentsSince']}');
    _goalsSince = DateTime.tryParse('${map['goalsSince']}');
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_busy || AuthService().currentSession?.userId != _user) return;
    _busy = true;
    final generation = _generation;
    try {
      final result = await _request('GET', '') as List;
      if (generation != _generation) return;
      final next = result
          .map(
            (e) =>
                AppNotification.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      for (final event in next.reversed) {
        final fresh = _seen.add(event.id);
        final since = event.kind == 'PAYMENT' ? _paymentsSince : _goalsSince;
        if (_baseline &&
            fresh &&
            (since == null || !event.createdAt.isBefore(since)) &&
            event.visibleAt(DateTime.now()) &&
            (event.kind == 'PAYMENT' ? payments : goals)) {
          _events.add(event);
          unawaited(_showDevice(event));
        }
      }
      _baseline = true;
      _items = next;
      _scheduleExpiry();
      _seen.removeWhere((id) => !next.any((n) => n.id == id));
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<void> setPreference({
    required bool payment,
    required bool enabled,
  }) async {
    await start();
    final user = _user;
    if (user == null) return;
    final generation = _generation;
    if (enabled && !await _permission()) {
      throw Exception(
        'Permissão de notificações não concedida. Verifique as configurações do dispositivo ou navegador.',
      );
    }
    if (generation != _generation) return;
    // Establish the baseline before enabling; do not alert for old events.
    await refresh();
    final nextPayments = payment ? enabled : payments;
    final nextGoals = payment ? goals : enabled;
    final now = DateTime.now().toUtc();
    final paymentsSince = nextPayments && !payments ? now : _paymentsSince;
    final goalsSince = nextGoals && !goals ? now : _goalsSince;
    await _preferences.write(user, {
      'payments': nextPayments,
      'goals': nextGoals,
      'paymentsSince': paymentsSince?.toIso8601String(),
      'goalsSince': goalsSince?.toIso8601String(),
    });
    if (generation != _generation) return;
    payments = nextPayments;
    goals = nextGoals;
    _paymentsSince = paymentsSince;
    _goalsSince = goalsSince;
    if (!payments && !goals) await _cancelDeviceNotifications();
    notifyListeners();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final remaining = items;
    if (remaining.isEmpty) return;
    final expiry = remaining
        .map((e) => e.expiresAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = expiry.difference(DateTime.now());
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _items.removeWhere((e) => !e.visibleAt(DateTime.now()));
      notifyListeners();
      _scheduleExpiry();
    });
  }

  Future<void> _initializeDevice() async {
    if (_ready) return;
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        web: WebInitializationSettings(),
      ),
    );
    _ready = initialized == true;
  }

  Future<bool> _permission() async {
    await _initializeDevice();
    if (kIsWeb) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                WebFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      case TargetPlatform.iOS:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      case TargetPlatform.macOS:
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      default:
        return false;
    }
  }

  Future<void> _showDevice(AppNotification event) async {
    final generation = _generation;
    try {
      await _initializeDevice();
      if (generation != _generation || !event.visibleAt(DateTime.now())) return;
      await _plugin.show(
        id: event.id,
        title: event.title,
        body: event.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'money_events',
            'Pagamentos e metas',
            channelDescription: 'Notificações da aplicação Money',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          web: WebNotificationDetails(),
        ),
      );
    } catch (_) {
      /* Browser/OS may revoke permission; in-app history still works. */
    }
  }

  Future<Object?> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request =
        http.Request(
            method,
            Uri.parse('${AuthService.apiBaseUrl}/api/v2/notifications$path'),
          )
          ..headers.addAll({
            ...AuthService().authenticatedHeaders,
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _http
        .send(request)
        .timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        stop();
        notifyListeners();
      }
      throw Exception('Não foi possível carregar as notificações.');
    }
    return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['responseBody'];
  }
}
