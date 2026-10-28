import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-user preferences in this installation only. Never imported from API.
class NotificationPreferencesStore {
  String _key(int userId) => 'money.deviceNotifications.v1.$userId';

  Future<Map<String, dynamic>> read(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key(userId));
    if (value == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> write(int userId, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key(userId), jsonEncode(value))) {
      throw Exception(
        'Não foi possível salvar a preferência neste dispositivo.',
      );
    }
  }
}
