final class AppUserSummary {
  final int id;
  final String name;
  final String username;
  final String? email;
  final bool enabled;
  final bool administrator;
  final bool canEdit;
  final bool collector;
  final DateTime? lastAccess;

  const AppUserSummary({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.enabled,
    required this.administrator,
    required this.canEdit,
    this.collector = false,
    required this.lastAccess,
  });

  factory AppUserSummary.fromJson(Map<String, dynamic> json) {
    return AppUserSummary(
      id: _readInt(json['id']),
      name: json['name']?.toString().trim() ?? '',
      username: json['username']?.toString().trim() ?? '',
      email: _readNullableString(json['email']),
      enabled: json['enabled'] == true,
      administrator: json['administrator'] == true,
      canEdit: json['canEdit'] == true,
      collector: json['collector'] == true,
      lastAccess: _readDate(json['lastAccess']),
    );
  }
}

final class AppUserDetail {
  final int id;
  final String firstName;
  final String lastName;
  final String name;
  final String username;
  final String email;
  final bool enabled;
  final bool locked;
  final bool expired;
  final bool credentialsExpired;
  final bool forcePasswordChange;
  final bool administrator;
  final bool canEdit;
  final bool collector;
  final bool tutorialCompleted;
  final DateTime? lastAccess;
  final List<AppUserRegion> regions;

  const AppUserDetail({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.username,
    required this.email,
    required this.enabled,
    required this.locked,
    required this.expired,
    required this.credentialsExpired,
    required this.forcePasswordChange,
    required this.administrator,
    required this.canEdit,
    this.collector = false,
    this.tutorialCompleted = false,
    required this.lastAccess,
    required this.regions,
  });

  factory AppUserDetail.fromJson(Map<String, dynamic> json) {
    final Object? rawRegions = json['regions'];
    return AppUserDetail(
      id: _readInt(json['id']),
      firstName: json['firstName']?.toString().trim() ?? '',
      lastName: json['lastName']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      username: json['username']?.toString().trim() ?? '',
      email: json['email']?.toString().trim() ?? '',
      enabled: json['enabled'] == true,
      locked: json['locked'] == true,
      expired: json['expired'] == true,
      credentialsExpired: json['credentialsExpired'] == true,
      forcePasswordChange: json['forcePasswordChange'] == true,
      administrator: json['administrator'] == true,
      canEdit: json['canEdit'] == true,
      collector: json['collector'] == true,
      tutorialCompleted: json['tutorialCompleted'] == true,
      lastAccess: _readDate(json['lastAccess']),
      regions: rawRegions is List
          ? rawRegions
                .whereType<Map>()
                .map(
                  (item) =>
                      AppUserRegion.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

final class AppUserRegion {
  final int id;
  final String name;
  final bool assigned;

  const AppUserRegion({
    required this.id,
    required this.name,
    required this.assigned,
  });

  factory AppUserRegion.fromJson(Map<String, dynamic> json) {
    return AppUserRegion(
      id: _readInt(json['id']),
      name: json['name']?.toString().trim() ?? '',
      assigned: json['assigned'] == true,
    );
  }
}

final class AppUserPage {
  final List<AppUserSummary> items;
  final int page;
  final int size;
  final int totalItems;
  final int totalPages;
  final bool hasNext;

  const AppUserPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
    required this.hasNext,
  });

  factory AppUserPage.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    return AppUserPage(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      AppUserSummary.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
      page: _readInt(json['page']),
      size: _readInt(json['size']),
      totalItems: _readInt(json['totalItems']),
      totalPages: _readInt(json['totalPages']),
      hasNext: json['hasNext'] == true,
    );
  }
}

int _readInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _readNullableString(Object? value) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _readDate(Object? value) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text);
}
