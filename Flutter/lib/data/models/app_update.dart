enum AppUpdateTarget { android, ios, web, unsupported }

final class AppUpdateRelease {
  final AppUpdateTarget target;
  final bool available;
  final int minimumBuild;
  final int latestBuild;
  final String version;
  final String downloadUrl;
  final String installUrl;
  final int size;
  final String sha256;
  final String releaseId;

  const AppUpdateRelease({
    required this.target,
    required this.available,
    required this.minimumBuild,
    required this.latestBuild,
    required this.version,
    required this.downloadUrl,
    required this.installUrl,
    required this.size,
    required this.sha256,
    required this.releaseId,
  });

  factory AppUpdateRelease.fromJson(
    AppUpdateTarget target,
    Map<String, dynamic> json,
  ) {
    return AppUpdateRelease(
      target: target,
      available: json['available'] == true,
      minimumBuild: _integer(json['minimumBuild']),
      latestBuild: _integer(json['latestBuild']),
      version: _text(json['version']),
      downloadUrl: _text(json['downloadUrl']),
      installUrl: _text(json['installUrl']),
      size: _integer(json['size']),
      sha256: _text(json['sha256']).toLowerCase(),
      releaseId: _text(json['releaseId']),
    );
  }

  static int _integer(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}

final class AppUpdateManifest {
  final int schema;
  final DateTime? publishedAt;
  final AppUpdateRelease android;
  final AppUpdateRelease ios;
  final AppUpdateRelease web;

  const AppUpdateManifest({
    required this.schema,
    required this.publishedAt,
    required this.android,
    required this.ios,
    required this.web,
  });

  factory AppUpdateManifest.fromJson(Map<String, dynamic> json) {
    return AppUpdateManifest(
      schema: _integer(json['schema']),
      publishedAt: DateTime.tryParse(_text(json['publishedAt'])),
      android: AppUpdateRelease.fromJson(
        AppUpdateTarget.android,
        _map(json['android']),
      ),
      ios: AppUpdateRelease.fromJson(AppUpdateTarget.ios, _map(json['ios'])),
      web: AppUpdateRelease.fromJson(AppUpdateTarget.web, _map(json['web'])),
    );
  }

  AppUpdateRelease releaseFor(AppUpdateTarget target) => switch (target) {
    AppUpdateTarget.android => android,
    AppUpdateTarget.ios => ios,
    AppUpdateTarget.web => web,
    AppUpdateTarget.unsupported => const AppUpdateRelease(
      target: AppUpdateTarget.unsupported,
      available: false,
      minimumBuild: 0,
      latestBuild: 0,
      version: '',
      downloadUrl: '',
      installUrl: '',
      size: 0,
      sha256: '',
      releaseId: '',
    ),
  };

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static int _integer(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}

final class RequiredAppUpdate {
  final AppUpdateTarget target;
  final int minimumBuild;
  final int latestBuild;
  final String version;
  final String downloadUrl;
  final String installUrl;
  final int size;
  final String sha256;
  final String releaseId;

  const RequiredAppUpdate({
    required this.target,
    required this.minimumBuild,
    required this.latestBuild,
    required this.version,
    required this.downloadUrl,
    required this.installUrl,
    required this.size,
    required this.sha256,
    required this.releaseId,
  });

  factory RequiredAppUpdate.fromRelease(AppUpdateRelease release) {
    return RequiredAppUpdate(
      target: release.target,
      minimumBuild: release.minimumBuild,
      latestBuild: release.latestBuild,
      version: release.version,
      downloadUrl: release.downloadUrl,
      installUrl: release.installUrl,
      size: release.size,
      sha256: release.sha256,
      releaseId: release.releaseId,
    );
  }

  factory RequiredAppUpdate.fromJson(Map<String, dynamic> json) {
    final String targetName = json['target']?.toString() ?? '';
    final AppUpdateTarget target = AppUpdateTarget.values.firstWhere(
      (AppUpdateTarget value) => value.name == targetName,
      orElse: () => AppUpdateTarget.unsupported,
    );
    return RequiredAppUpdate(
      target: target,
      minimumBuild: _integer(json['minimumBuild']),
      latestBuild: _integer(json['latestBuild']),
      version: _text(json['version']),
      downloadUrl: _text(json['downloadUrl']),
      installUrl: _text(json['installUrl']),
      size: _integer(json['size']),
      sha256: _text(json['sha256']),
      releaseId: _text(json['releaseId']),
    );
  }

  String get actionUrl => switch (target) {
    AppUpdateTarget.android => downloadUrl,
    AppUpdateTarget.ios => installUrl,
    AppUpdateTarget.web || AppUpdateTarget.unsupported => '',
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'target': target.name,
    'minimumBuild': minimumBuild,
    'latestBuild': latestBuild,
    'version': version,
    'downloadUrl': downloadUrl,
    'installUrl': installUrl,
    'size': size,
    'sha256': sha256,
    'releaseId': releaseId,
  };

  bool sameRelease(RequiredAppUpdate? other) {
    return other != null &&
        target == other.target &&
        minimumBuild == other.minimumBuild &&
        latestBuild == other.latestBuild &&
        releaseId == other.releaseId &&
        actionUrl == other.actionUrl;
  }

  static int _integer(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}
