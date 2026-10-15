final class AppRegionSummary {
  final int id;
  final String description;
  final String? responsiblePeople;
  final int activeClients;
  final int missingClients;
  final int currentClients;
  final int overdueClients;
  final double overdueAmount;
  final double receivedAmount;
  final double dueTodayAmount;
  final double receivableAmount;
  final double missingAmount;
  final double profitAmount;
  final double loanedAmount;

  const AppRegionSummary({
    required this.id,
    required this.description,
    required this.responsiblePeople,
    required this.activeClients,
    required this.missingClients,
    required this.currentClients,
    required this.overdueClients,
    required this.overdueAmount,
    required this.receivedAmount,
    required this.dueTodayAmount,
    required this.receivableAmount,
    required this.missingAmount,
    required this.profitAmount,
    required this.loanedAmount,
  });

  factory AppRegionSummary.fromJson(Map<String, dynamic> json) =>
      AppRegionSummary(
        id: _int(json['id']),
        description: _text(json['description']),
        responsiblePeople: _nullableText(json['responsiblePeople']),
        activeClients: _int(json['activeClients']),
        missingClients: _int(json['missingClients']),
        currentClients: _int(json['currentClients']),
        overdueClients: _int(json['overdueClients']),
        overdueAmount: _double(json['overdueAmount']),
        receivedAmount: _double(json['receivedAmount']),
        dueTodayAmount: _double(json['dueTodayAmount']),
        receivableAmount: _double(json['receivableAmount']),
        missingAmount: _double(json['missingAmount']),
        profitAmount: _double(json['profitAmount']),
        loanedAmount: _double(json['loanedAmount']),
      );

  String get displayName {
    final String responsible = responsiblePeople?.trim() ?? '';
    final String name = description.trim().isEmpty
        ? 'Região #$id'
        : description.trim();
    return responsible.isEmpty ? name : '$name - $responsible';
  }
}

final class AppRegionTotals {
  final int regions;
  final int activeClients;
  final int missingClients;
  final int currentClients;
  final int overdueClients;
  final double overdueAmount;
  final double receivedAmount;
  final double dueTodayAmount;
  final double receivableAmount;
  final double missingAmount;
  final double profitAmount;
  final double loanedAmount;

  const AppRegionTotals({
    required this.regions,
    required this.activeClients,
    required this.missingClients,
    required this.currentClients,
    required this.overdueClients,
    required this.overdueAmount,
    required this.receivedAmount,
    required this.dueTodayAmount,
    required this.receivableAmount,
    required this.missingAmount,
    required this.profitAmount,
    required this.loanedAmount,
  });

  const AppRegionTotals.empty()
    : regions = 0,
      activeClients = 0,
      missingClients = 0,
      currentClients = 0,
      overdueClients = 0,
      overdueAmount = 0,
      receivedAmount = 0,
      dueTodayAmount = 0,
      receivableAmount = 0,
      missingAmount = 0,
      profitAmount = 0,
      loanedAmount = 0;

  factory AppRegionTotals.fromJson(Map<String, dynamic> json) =>
      AppRegionTotals(
        regions: _int(json['regions']),
        activeClients: _int(json['activeClients']),
        missingClients: _int(json['missingClients']),
        currentClients: _int(json['currentClients']),
        overdueClients: _int(json['overdueClients']),
        overdueAmount: _double(json['overdueAmount']),
        receivedAmount: _double(json['receivedAmount']),
        dueTodayAmount: _double(json['dueTodayAmount']),
        receivableAmount: _double(json['receivableAmount']),
        missingAmount: _double(json['missingAmount']),
        profitAmount: _double(json['profitAmount']),
        loanedAmount: _double(json['loanedAmount']),
      );
}

final class AppRegionListData {
  final List<AppRegionSummary> items;
  final AppRegionTotals totals;
  final DateTime? startDate;
  final DateTime? endDate;

  const AppRegionListData({
    required this.items,
    required this.totals,
    required this.startDate,
    required this.endDate,
  });

  factory AppRegionListData.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    return AppRegionListData(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => AppRegionSummary.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      totals: json['totals'] is Map
          ? AppRegionTotals.fromJson(
              Map<String, dynamic>.from(json['totals'] as Map),
            )
          : const AppRegionTotals.empty(),
      startDate: _date(json['startDate']),
      endDate: _date(json['endDate']),
    );
  }
}

final class AppRegionDetail {
  final int id;
  final String description;
  final String? responsiblePeople;
  final String? parentDescription;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? loanMessage;
  final String? refinancedLoanMessage;
  final String? collectionMessage;
  final String? collectionLinkMessage;
  final String? overdueMessage;
  final bool clientOwnerRequired;

  const AppRegionDetail({
    required this.id,
    required this.description,
    required this.responsiblePeople,
    required this.parentDescription,
    required this.createdAt,
    required this.updatedAt,
    required this.loanMessage,
    required this.refinancedLoanMessage,
    required this.collectionMessage,
    required this.collectionLinkMessage,
    required this.overdueMessage,
    required this.clientOwnerRequired,
  });

  factory AppRegionDetail.fromJson(Map<String, dynamic> json) =>
      AppRegionDetail(
        id: _int(json['id']),
        description: _text(json['description']),
        responsiblePeople: _nullableText(json['responsiblePeople']),
        parentDescription: _nullableText(json['parentDescription']),
        createdAt: _dateTime(json['createdAt']),
        updatedAt: _dateTime(json['updatedAt']),
        loanMessage: _nullableText(json['loanMessage']),
        refinancedLoanMessage: _nullableText(json['refinancedLoanMessage']),
        collectionMessage: _nullableText(json['collectionMessage']),
        collectionLinkMessage: _nullableText(json['collectionLinkMessage']),
        overdueMessage: _nullableText(json['overdueMessage']),
        clientOwnerRequired: json['clientOwnerRequired'] == true,
      );
}

final class AppRegionOption {
  final int id;
  final String name;

  const AppRegionOption({required this.id, required this.name});

  factory AppRegionOption.fromJson(Map<String, dynamic> json) =>
      AppRegionOption(id: _int(json['id']), name: _text(json['name']));
}

final class AppRegionFilters {
  final DateTime? startDate;
  final DateTime? endDate;
  final Set<int> regionIds;

  const AppRegionFilters({
    required this.startDate,
    required this.endDate,
    this.regionIds = const {},
  });

  factory AppRegionFilters.lastThirtyDays(DateTime now) {
    final DateTime end = DateTime(now.year, now.month, now.day);
    return AppRegionFilters(
      startDate: end.subtract(const Duration(days: 30)),
      endDate: end,
    );
  }

  int get activeCount =>
      regionIds.length +
      (startDate == null ? 0 : 1) +
      (endDate == null ? 0 : 1);
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _text(Object? value) => value?.toString().trim() ?? '';

String? _nullableText(Object? value) {
  final String result = _text(value);
  return result.isEmpty ? null : result;
}

DateTime? _date(Object? value) {
  final DateTime? parsed = _dateTime(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? _dateTime(Object? value) => DateTime.tryParse(_text(value));
