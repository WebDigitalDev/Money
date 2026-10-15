enum AppCollectionRouteStatus {
  inProgress('IN_PROGRESS', 'Em execução'),
  completed('COMPLETED', 'Realizado');

  final String apiValue;
  final String label;

  const AppCollectionRouteStatus(this.apiValue, this.label);

  static AppCollectionRouteStatus fromJson(Object? value) =>
      value?.toString() == completed.apiValue ? completed : inProgress;
}

enum AppCollectionRouteSort {
  overdueDays('OVERDUE_DAYS', 'Mais dias em atraso'),
  overdueAmount('OVERDUE_AMOUNT', 'Maior valor em atraso');

  final String apiValue;
  final String label;

  const AppCollectionRouteSort(this.apiValue, this.label);
}

final class AppCollectionRouteItem {
  final int? routeId;
  final int clientId;
  final String clientName;
  final int regionId;
  final String regionName;
  final double totalDebt;
  final double overdueDebt;
  final int overdueDays;
  final int overdueLoans;
  final String address;
  final AppCollectionRouteStatus status;
  final int collectionCount;
  final DateTime? lastCollectionAt;
  final int? collectorId;
  final String? collectorName;
  final DateTime? assignedAt;

  const AppCollectionRouteItem({
    this.routeId,
    required this.clientId,
    required this.clientName,
    required this.regionId,
    required this.regionName,
    required this.totalDebt,
    required this.overdueDebt,
    required this.overdueDays,
    required this.overdueLoans,
    required this.address,
    required this.status,
    required this.collectionCount,
    required this.lastCollectionAt,
    this.collectorId,
    this.collectorName,
    this.assignedAt,
  });

  factory AppCollectionRouteItem.fromJson(Map<String, dynamic> json) =>
      AppCollectionRouteItem(
        routeId: _routeNullableInt(json['routeId']),
        clientId: _routeInt(json['clientId']),
        clientName: _routeText(json['clientName'], 'Cliente sem nome'),
        regionId: _routeInt(json['regionId']),
        regionName: _routeText(json['regionName'], 'Região sem nome'),
        totalDebt: _routeDouble(json['totalDebt']),
        overdueDebt: _routeDouble(json['overdueDebt']),
        overdueDays: _routeInt(json['overdueDays']),
        overdueLoans: _routeInt(json['overdueLoans']),
        address: _routeText(json['address'], 'Endereço não informado'),
        status: AppCollectionRouteStatus.fromJson(json['status']),
        collectionCount: _routeInt(json['collectionCount']),
        lastCollectionAt: _routeDate(json['lastCollectionAt']),
        collectorId: _routeNullableInt(json['collectorId']),
        collectorName: _routeNullableText(json['collectorName']),
        assignedAt: _routeDate(json['assignedAt']),
      );
}

final class AppCollectionRouteCollector {
  final int id;
  final String name;
  final String username;

  const AppCollectionRouteCollector({
    required this.id,
    required this.name,
    required this.username,
  });

  factory AppCollectionRouteCollector.fromJson(Map<String, dynamic> json) =>
      AppCollectionRouteCollector(
        id: _routeInt(json['id']),
        name: _routeText(json['name'], 'Cobrador'),
        username: _routeText(json['username'], ''),
      );
}

final class AppCollectionRoutePage {
  final List<AppCollectionRouteItem> items;
  final int page;
  final int size;
  final int totalItems;
  final int totalPages;
  final bool hasNext;
  final double totalDebt;
  final double totalOverdueDebt;

  const AppCollectionRoutePage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
    required this.hasNext,
    required this.totalDebt,
    required this.totalOverdueDebt,
  });

  factory AppCollectionRoutePage.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    return AppCollectionRoutePage(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => AppCollectionRouteItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      page: _routeInt(json['page']),
      size: _routeInt(json['size']),
      totalItems: _routeInt(json['totalItems']),
      totalPages: _routeInt(json['totalPages']),
      hasNext: json['hasNext'] == true,
      totalDebt: _routeDouble(json['totalDebt']),
      totalOverdueDebt: _routeDouble(json['totalOverdueDebt']),
    );
  }
}

final class AppCollectionContract {
  final int loanId;
  final String type;
  final double totalDebt;
  final double overdueDebt;
  final int overdueDays;
  final DateTime? oldestDueDate;

  const AppCollectionContract({
    required this.loanId,
    required this.type,
    required this.totalDebt,
    required this.overdueDebt,
    required this.overdueDays,
    required this.oldestDueDate,
  });

  factory AppCollectionContract.fromJson(Map<String, dynamic> json) =>
      AppCollectionContract(
        loanId: _routeInt(json['loanId']),
        type: _routeText(json['type'], 'Empréstimo'),
        totalDebt: _routeDouble(json['totalDebt']),
        overdueDebt: _routeDouble(json['overdueDebt']),
        overdueDays: _routeInt(json['overdueDays']),
        oldestDueDate: _routeDate(json['oldestDueDate']),
      );
}

final class AppCollectionHistory {
  final int id;
  final int clientId;
  final int regionId;
  final String regionName;
  final int userId;
  final String collectorName;
  final String observation;
  final double debtAmount;
  final int overdueDays;
  final String? attachmentName;
  final String? attachmentContentType;
  final int? attachmentSize;
  final bool attachmentAvailable;
  final DateTime? createdAt;

  const AppCollectionHistory({
    required this.id,
    required this.clientId,
    required this.regionId,
    required this.regionName,
    required this.userId,
    required this.collectorName,
    required this.observation,
    required this.debtAmount,
    required this.overdueDays,
    required this.attachmentName,
    required this.attachmentContentType,
    required this.attachmentSize,
    required this.attachmentAvailable,
    required this.createdAt,
  });

  factory AppCollectionHistory.fromJson(Map<String, dynamic> json) =>
      AppCollectionHistory(
        id: _routeInt(json['id']),
        clientId: _routeInt(json['clientId']),
        regionId: _routeInt(json['regionId']),
        regionName: _routeText(json['regionName'], 'Região sem nome'),
        userId: _routeInt(json['userId']),
        collectorName: _routeText(json['collectorName'], 'Usuário'),
        observation: _routeText(json['observation'], 'Sem observação'),
        debtAmount: _routeDouble(json['debtAmount']),
        overdueDays: _routeInt(json['overdueDays']),
        attachmentName: _routeNullableText(json['attachmentName']),
        attachmentContentType: _routeNullableText(
          json['attachmentContentType'],
        ),
        attachmentSize: _routeNullableInt(json['attachmentSize']),
        attachmentAvailable: json['attachmentAvailable'] == true,
        createdAt: _routeDate(json['createdAt']),
      );
}

final class AppCollectionRouteDetail {
  final AppCollectionRouteItem debt;
  final List<AppCollectionContract> contracts;
  final List<AppCollectionHistory> history;
  final bool canRegisterCollection;

  const AppCollectionRouteDetail({
    required this.debt,
    required this.contracts,
    required this.history,
    required this.canRegisterCollection,
  });

  factory AppCollectionRouteDetail.fromJson(Map<String, dynamic> json) {
    final Object? rawContracts = json['contracts'];
    final Object? rawHistory = json['history'];
    return AppCollectionRouteDetail(
      debt: AppCollectionRouteItem.fromJson(
        Map<String, dynamic>.from(json['debt'] as Map? ?? const {}),
      ),
      contracts: rawContracts is List
          ? rawContracts
                .whereType<Map>()
                .map(
                  (item) => AppCollectionContract.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      history: rawHistory is List
          ? rawHistory
                .whereType<Map>()
                .map(
                  (item) => AppCollectionHistory.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      canRegisterCollection: json['canRegisterCollection'] == true,
    );
  }
}

int _routeInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

int? _routeNullableInt(Object? value) {
  if (value == null) return null;
  return value is num ? value.toInt() : int.tryParse('$value');
}

double _routeDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _routeText(Object? value, String fallback) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _routeNullableText(Object? value) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _routeDate(Object? value) =>
    DateTime.tryParse(value?.toString().trim() ?? '');
