import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:money/core/core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final ThemeMode themeMode;
  final bool enableScreenshot;
  final bool enableLockApp;

  const AppSettings({
    required this.themeMode,
    required this.enableScreenshot,
    required this.enableLockApp,
  });
}

class SharedPreferencesService {
  SharedPreferencesService._internal();

  static final SharedPreferencesService _instance =
      SharedPreferencesService._internal();

  factory SharedPreferencesService() => _instance;

  Future<AppSettings> getSettings() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? savedTheme = preferences.getString(
      UserPrefsKeys.themeMode.name,
    );
    final ThemeMode storedThemeMode =
        ThemeMode.values.any((ThemeMode mode) => mode.name == savedTheme)
        ? ThemeMode.values.byName(savedTheme!)
        : AppStrings.defaultThemeMode;
    // Preferências antigas podiam usar ThemeMode.system. O Money trabalha
    // somente com uma escolha explícita entre claro e escuro.
    final ThemeMode themeMode = storedThemeMode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    return AppSettings(
      themeMode: themeMode,
      enableScreenshot:
          preferences.getBool(UserPrefsKeys.enableScreenshot.name) ??
          AppStrings.enableScreenshot,
      enableLockApp:
          preferences.getBool(UserPrefsKeys.enableLockApp.name) ??
          AppStrings.enableLockApp,
    );
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final ThemeMode explicitMode = themeMode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    await preferences.setString(
      UserPrefsKeys.themeMode.name,
      explicitMode.name,
    );
  }

  Future<void> saveEnableScreenshot(bool enable) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(UserPrefsKeys.enableScreenshot.name, enable);
  }

  Future<void> saveEnableLockApp(bool enable) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(UserPrefsKeys.enableLockApp.name, enable);
  }

  Future<bool> getLockAppStatus() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(UserPrefsKeys.enableLockApp.name) ??
        AppStrings.enableLockApp;
  }

  Future<Map<String, dynamic>?> getUserFilters({
    required String scope,
    required int userId,
  }) async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String? raw = preferences.getString(_userFilterKey(scope, userId));
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> saveUserFilters({
    required String scope,
    required int userId,
    required Map<String, Object?> filters,
  }) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _userFilterKey(scope, userId),
      jsonEncode(filters),
    );
  }

  String _userFilterKey(String scope, int userId) {
    final String normalizedScope = scope.trim();
    if (normalizedScope.isEmpty) {
      throw ArgumentError.value(scope, 'scope', 'Informe o escopo do filtro.');
    }
    return '$normalizedScope.filters.user.$userId';
  }
}
