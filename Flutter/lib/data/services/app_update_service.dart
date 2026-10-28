import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService _instance = AppUpdateService._();

  factory AppUpdateService() => _instance;

  static const String manifestUrl = String.fromEnvironment(
    'MONEY_UPDATE_MANIFEST_URL',
    defaultValue: 'https://moneyapp.site/appupdate/update.json',
  );
  static const String webReleaseId = String.fromEnvironment(
    'MONEY_WEB_RELEASE_ID',
    defaultValue: 'development',
  );
  static const Duration _requestTimeout = Duration(seconds: 8);
  static const String _cachePrefix = 'money.mandatory-update.v1.';

  final http.Client _client = http.Client();

  AppUpdateTarget get currentTarget {
    if (kIsWeb) return AppUpdateTarget.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AppUpdateTarget.android,
      TargetPlatform.iOS => AppUpdateTarget.ios,
      _ => AppUpdateTarget.unsupported,
    };
  }

  Future<RequiredAppUpdate?> checkForRequiredUpdate() async {
    final AppUpdateTarget target = currentTarget;
    if (target == AppUpdateTarget.unsupported) return null;

    final RequiredAppUpdate? cached = await _readCachedRequirement(target);
    try {
      final AppUpdateManifest manifest = await fetchManifest();
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int installedBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final RequiredAppUpdate? requirement = evaluateRequirement(
        manifest: manifest,
        target: target,
        installedBuild: installedBuild,
        installedWebReleaseId: webReleaseId,
      );
      await _saveCachedRequirement(target, requirement);
      return requirement;
    } catch (_) {
      return cached;
    }
  }

  Future<AppUpdateManifest> fetchManifest() async {
    final Uri configured = Uri.parse(manifestUrl);
    final Uri uri = configured.replace(
      queryParameters: <String, String>{
        ...configured.queryParameters,
        '_money_check': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final http.Response response = await _client
        .get(
          uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw const FormatException('Manifesto de atualização indisponível.');
    }
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Manifesto de atualização inválido.');
    }
    final AppUpdateManifest manifest = AppUpdateManifest.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (manifest.schema != 1) {
      throw const FormatException('Versão de manifesto não suportada.');
    }
    return manifest;
  }

  @visibleForTesting
  static RequiredAppUpdate? evaluateRequirement({
    required AppUpdateManifest manifest,
    required AppUpdateTarget target,
    required int installedBuild,
    required String installedWebReleaseId,
  }) {
    final AppUpdateRelease release = manifest.releaseFor(target);
    if (!release.available) return null;

    final bool required = switch (target) {
      AppUpdateTarget.android || AppUpdateTarget.ios =>
        release.minimumBuild > 0 && installedBuild < release.minimumBuild,
      AppUpdateTarget.web =>
        release.releaseId.isNotEmpty &&
            installedWebReleaseId != 'development' &&
            installedWebReleaseId != release.releaseId,
      AppUpdateTarget.unsupported => false,
    };
    return required ? RequiredAppUpdate.fromRelease(release) : null;
  }

  Future<RequiredAppUpdate?> _readCachedRequirement(
    AppUpdateTarget target,
  ) async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String? raw = preferences.getString('$_cachePrefix${target.name}');
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final RequiredAppUpdate requirement = RequiredAppUpdate.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return requirement.target == target ? requirement : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedRequirement(
    AppUpdateTarget target,
    RequiredAppUpdate? requirement,
  ) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String key = '$_cachePrefix${target.name}';
    if (requirement == null) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, jsonEncode(requirement.toJson()));
    }
  }
}
