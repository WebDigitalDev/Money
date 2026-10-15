enum AppClientStatus {
  active('ACTIVE'),
  withoutLoans('INACTIVE'),
  missing('MISSING');

  final String apiValue;

  const AppClientStatus(this.apiValue);

  static AppClientStatus fromJson(Object? value) => switch (value?.toString()) {
    'MISSING' => AppClientStatus.missing,
    'INACTIVE' => AppClientStatus.withoutLoans,
    _ => AppClientStatus.active,
  };
}

final class AppClientSummary {
  final int id;
  final String name;
  final String? document;
  final String? primaryPhone;
  final int regionId;
  final String regionName;
  final AppClientStatus status;

  const AppClientSummary({
    required this.id,
    required this.name,
    required this.document,
    required this.primaryPhone,
    required this.regionId,
    required this.regionName,
    required this.status,
  });

  factory AppClientSummary.fromJson(Map<String, dynamic> json) =>
      AppClientSummary(
        id: _int(json['id']),
        name: _text(json['name'], fallback: 'Cliente sem nome'),
        document: _nullableText(json['document']),
        primaryPhone: _nullableText(json['primaryPhone']),
        regionId: _int(json['regionId']),
        regionName: _text(json['regionName'], fallback: 'Região sem nome'),
        status: AppClientStatus.fromJson(json['status']),
      );
}

final class AppClientStatusCounts {
  final int active;
  final int withoutLoans;
  final int missing;

  const AppClientStatusCounts({
    required this.active,
    required this.withoutLoans,
    required this.missing,
  });

  const AppClientStatusCounts.empty()
    : active = 0,
      withoutLoans = 0,
      missing = 0;

  factory AppClientStatusCounts.fromJson(Map<String, dynamic> json) =>
      AppClientStatusCounts(
        active: _int(json['active']),
        withoutLoans: _int(json['withoutLoans']),
        missing: _int(json['missing']),
      );
}

final class AppClientPage {
  final List<AppClientSummary> items;
  final int page;
  final int size;
  final int totalItems;
  final int totalPages;
  final bool hasNext;
  final AppClientStatusCounts counts;

  const AppClientPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
    required this.hasNext,
    required this.counts,
  });

  factory AppClientPage.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    return AppClientPage(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => AppClientSummary.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      page: _int(json['page']),
      size: _int(json['size']),
      totalItems: _int(json['totalItems']),
      totalPages: _int(json['totalPages']),
      hasNext: json['hasNext'] == true,
      counts: json['counts'] is Map
          ? AppClientStatusCounts.fromJson(
              Map<String, dynamic>.from(json['counts'] as Map),
            )
          : const AppClientStatusCounts.empty(),
    );
  }
}

final class AppClientScore {
  final int points;
  final int overdueDays;
  final double totalDebt;

  const AppClientScore({
    required this.points,
    required this.overdueDays,
    required this.totalDebt,
  });

  const AppClientScore.initial() : points = 100, overdueDays = 0, totalDebt = 0;

  factory AppClientScore.fromJson(Map<String, dynamic> json) => AppClientScore(
    points: _int(json['points']).clamp(0, 100).toInt(),
    overdueDays: _int(json['overdueDays']).clamp(0, 0x7fffffff).toInt(),
    totalDebt: (_nullableDouble(json['totalDebt']) ?? 0).clamp(
      0,
      double.maxFinite,
    ),
  );
}

final class AppClientDetail {
  final int id;
  final String name;
  final String? legalName;
  final String? document;
  final String? email;
  final String type;
  final String? stateRegistration;
  final DateTime? birthDate;
  final String? mobilePhone;
  final String? phone;
  final String? secondaryPhone;
  final String? homepage;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int postalCode;
  final int? cityId;
  final String? cityName;
  final String? cityState;
  final String? address;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? collector;
  final String? googleMapsLink;
  final double? latitude;
  final double? longitude;
  final double? businessLatitude;
  final double? businessLongitude;
  final int regionId;
  final String regionName;
  final String? notes;
  final String? business;
  final String? facebook;
  final String? instagram;
  final AppClientStatus status;
  final AppClientScore score;

  const AppClientDetail({
    required this.id,
    required this.name,
    required this.legalName,
    required this.document,
    required this.email,
    required this.type,
    required this.stateRegistration,
    required this.birthDate,
    required this.mobilePhone,
    required this.phone,
    required this.secondaryPhone,
    required this.homepage,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    required this.postalCode,
    required this.cityId,
    required this.cityName,
    required this.cityState,
    required this.address,
    required this.number,
    required this.complement,
    required this.neighborhood,
    required this.collector,
    required this.googleMapsLink,
    required this.latitude,
    required this.longitude,
    required this.businessLatitude,
    required this.businessLongitude,
    required this.regionId,
    required this.regionName,
    required this.notes,
    required this.business,
    required this.facebook,
    required this.instagram,
    required this.status,
    required this.score,
  });

  factory AppClientDetail.fromJson(Map<String, dynamic> json) =>
      AppClientDetail(
        id: _int(json['id']),
        name: _text(json['name'], fallback: 'Cliente sem nome'),
        legalName: _nullableText(json['legalName']),
        document: _nullableText(json['document']),
        email: _nullableText(json['email']),
        type: _text(json['type'], fallback: 'FISICA'),
        stateRegistration: _nullableText(json['stateRegistration']),
        birthDate: _date(json['birthDate']),
        mobilePhone: _nullableText(json['mobilePhone']),
        phone: _nullableText(json['phone']),
        secondaryPhone: _nullableText(json['secondaryPhone']),
        homepage: _nullableText(json['homepage']),
        enabled: json['enabled'] != false,
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        postalCode: _int(json['postalCode']),
        cityId: _nullableInt(json['cityId']),
        cityName: _nullableText(json['cityName']),
        cityState: _nullableText(json['cityState']),
        address: _nullableText(json['address']),
        number: _nullableText(json['number']),
        complement: _nullableText(json['complement']),
        neighborhood: _nullableText(json['neighborhood']),
        collector: _nullableText(json['collector']),
        googleMapsLink: _nullableText(json['googleMapsLink']),
        latitude: _nullableDouble(json['latitude']),
        longitude: _nullableDouble(json['longitude']),
        businessLatitude: _nullableDouble(json['businessLatitude']),
        businessLongitude: _nullableDouble(json['businessLongitude']),
        regionId: _int(json['regionId']),
        regionName: _text(json['regionName'], fallback: 'Região sem nome'),
        notes: _nullableText(json['notes']),
        business: _nullableText(json['business']),
        facebook: _nullableText(json['facebook']),
        instagram: _nullableText(json['instagram']),
        status: AppClientStatus.fromJson(json['status']),
        score: _clientScore(json),
      );
}

final class AppCompanyLookup {
  final String document;
  final String legalName;
  final String? tradeName;
  final String? stateRegistration;
  final String? email;
  final String? primaryPhone;
  final String? secondaryPhone;
  final int? postalCode;
  final int? cityIbgeCode;
  final String? cityName;
  final String? state;
  final String? address;
  final String? number;
  final String? complement;
  final String? neighborhood;

  const AppCompanyLookup({
    required this.document,
    required this.legalName,
    required this.tradeName,
    required this.stateRegistration,
    required this.email,
    required this.primaryPhone,
    required this.secondaryPhone,
    required this.postalCode,
    required this.cityIbgeCode,
    required this.cityName,
    required this.state,
    required this.address,
    required this.number,
    required this.complement,
    required this.neighborhood,
  });

  factory AppCompanyLookup.fromJson(Map<String, dynamic> json) =>
      AppCompanyLookup(
        document: _text(json['document']),
        legalName: _text(json['legalName']),
        tradeName: _nullableText(json['tradeName']),
        stateRegistration: _nullableText(json['stateRegistration']),
        email: _nullableText(json['email']),
        primaryPhone: _nullableText(json['primaryPhone']),
        secondaryPhone: _nullableText(json['secondaryPhone']),
        postalCode: _nullableInt(json['postalCode']),
        cityIbgeCode: _nullableInt(json['cityIbgeCode']),
        cityName: _nullableText(json['cityName']),
        state: _nullableText(json['state']),
        address: _nullableText(json['address']),
        number: _nullableText(json['number']),
        complement: _nullableText(json['complement']),
        neighborhood: _nullableText(json['neighborhood']),
      );
}

final class AppClientContact {
  final int id;
  final int clientId;
  final String name;
  final String? phone;
  final String? type;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppClientContact({
    required this.id,
    required this.clientId,
    required this.name,
    required this.phone,
    required this.type,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppClientContact.fromJson(Map<String, dynamic> json) =>
      AppClientContact(
        id: _int(json['id']),
        clientId: _int(json['clientId']),
        name: _text(json['name']),
        phone: _nullableText(json['phone']),
        type: _nullableText(json['type']),
        notes: _nullableText(json['notes']),
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
      );
}

final class AppClientDocument {
  final int id;
  final int clientId;
  final String description;
  final String fileName;
  final String? contentType;
  final bool available;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppClientDocument({
    required this.id,
    required this.clientId,
    required this.description,
    required this.fileName,
    required this.contentType,
    required this.available,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppClientDocument.fromJson(Map<String, dynamic> json) =>
      AppClientDocument(
        id: _int(json['id']),
        clientId: _int(json['clientId']),
        description: _text(json['description'], fallback: 'Documento'),
        fileName: _text(json['fileName'], fallback: 'documento'),
        contentType: _nullableText(json['contentType']),
        available: json['available'] == true,
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
      );
}

final class AppCityOption {
  final int id;
  final int? ibgeCode;
  final String name;
  final String state;
  final String displayName;

  const AppCityOption({
    required this.id,
    required this.ibgeCode,
    required this.name,
    required this.state,
    required this.displayName,
  });

  factory AppCityOption.fromJson(Map<String, dynamic> json) => AppCityOption(
    id: _int(json['id']),
    ibgeCode: _nullableInt(json['ibgeCode']),
    name: _text(json['name']),
    state: _text(json['state']),
    displayName: _text(json['displayName']),
  );
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

int? _nullableInt(Object? value) {
  if (value == null) return null;
  return value is num ? value.toInt() : int.tryParse(value.toString());
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  return value is num ? value.toDouble() : double.tryParse(value.toString());
}

String _text(Object? value, {String fallback = ''}) {
  final String result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

String? _nullableText(Object? value) {
  final String result = value?.toString().trim() ?? '';
  return result.isEmpty ? null : result;
}

DateTime? _date(Object? value) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text);
}

AppClientScore _clientScore(Map<String, dynamic> json) {
  final AppClientScore parsed = json['score'] is Map
      ? AppClientScore.fromJson(Map<String, dynamic>.from(json['score'] as Map))
      : const AppClientScore.initial();
  if (AppClientStatus.fromJson(json['status']) != AppClientStatus.missing) {
    return parsed;
  }
  return AppClientScore(
    points: 0,
    overdueDays: parsed.overdueDays,
    totalDebt: parsed.totalDebt,
  );
}
