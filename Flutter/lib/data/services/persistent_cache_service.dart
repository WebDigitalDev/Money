import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class PersistentCacheEntry {
  final Object? data;
  final String? etag;
  final DateTime savedAt;

  const PersistentCacheEntry({
    required this.data,
    required this.etag,
    required this.savedAt,
  });
}

/// Cache persistente de leitura, sem banco de dados local.
///
/// Os dados permanecem entre reinicializações do aplicativo, são separados
/// por usuário nas chaves fornecidas pelos serviços e continuam sendo
/// revalidados no servidor por ETag. Logout e rejeição da sessão removem tudo.
final class PersistentCacheService {
  PersistentCacheService._();

  static final PersistentCacheService _instance = PersistentCacheService._();

  factory PersistentCacheService() => _instance;

  static const String _prefix = 'money.read_cache.v1.';
  final Map<String, String> _entries = {};
  SharedPreferences? _preferences;
  Future<void>? _initialization;
  bool _writesEnabled = false;

  Future<void> initialize() => _initialization ??= _load();

  void resumeWrites() => _writesEnabled = true;

  PersistentCacheEntry? read(String namespace, String key) {
    final String storageKey = _storageKey(namespace, key);
    final String? raw = _entries[storageKey];
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> value = Map<String, dynamic>.from(decoded);
      final DateTime? savedAt = DateTime.tryParse(
        value['savedAt']?.toString() ?? '',
      );
      if (value['version'] != 1 || savedAt == null) return null;
      return PersistentCacheEntry(
        data: value['data'],
        etag: _nullableText(value['etag']),
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String namespace,
    String key, {
    required Object? data,
    String? etag,
  }) async {
    final SharedPreferences? preferences = _preferences;
    if (preferences == null || !_writesEnabled) return;
    final String storageKey = _storageKey(namespace, key);
    final String encoded = jsonEncode({
      'version': 1,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'etag': etag,
      'data': data,
    });
    _entries[storageKey] = encoded;
    await preferences.setString(storageKey, encoded);
  }

  Future<void> remove(String namespace, String key) async {
    final String storageKey = _storageKey(namespace, key);
    _entries.remove(storageKey);
    await _preferences?.remove(storageKey);
  }

  Future<void> clearNamespace(String namespace) async {
    final String namespacePrefix = '$_prefix$namespace.';
    final List<String> keys = _entries.keys
        .where((key) => key.startsWith(namespacePrefix))
        .toList(growable: false);
    for (final String key in keys) {
      _entries.remove(key);
      await _preferences?.remove(key);
    }
  }

  Future<void> clearAll({bool suspendWrites = false}) async {
    if (suspendWrites) _writesEnabled = false;
    final List<String> keys = _entries.keys.toList(growable: false);
    _entries.clear();
    for (final String key in keys) {
      await _preferences?.remove(key);
    }
  }

  Future<void> _load() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    for (final String key in preferences.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final String? value = preferences.getString(key);
      if (value != null) _entries[key] = value;
    }
  }

  String _storageKey(String namespace, String key) {
    final String encodedKey = base64Url.encode(utf8.encode(key));
    return '$_prefix$namespace.$encodedKey';
  }
}

String? _nullableText(Object? value) {
  final String result = value?.toString().trim() ?? '';
  return result.isEmpty ? null : result;
}
