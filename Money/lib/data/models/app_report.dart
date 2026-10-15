final class AppAuditHistoryItem {
  final int id;
  final String entityName;
  final String username;
  final int? entityId;
  final String operation;
  final String description;
  final DateTime? timestamp;
  final int? regionId;
  final String? regionDescription;
  final String value;

  const AppAuditHistoryItem({
    required this.id,
    required this.entityName,
    required this.username,
    required this.entityId,
    required this.operation,
    required this.description,
    required this.timestamp,
    required this.regionId,
    required this.regionDescription,
    required this.value,
  });

  factory AppAuditHistoryItem.fromJson(Map<String, dynamic> json) =>
      AppAuditHistoryItem(
        id: _int(json['id']),
        entityName: _text(json['entityName']),
        username: _text(json['username']),
        entityId: _nullableInt(json['entityId']),
        operation: _text(json['operation']),
        description: _text(json['description']),
        timestamp: DateTime.tryParse(_text(json['timestamp'])),
        regionId: _nullableInt(json['regionId']),
        regionDescription: _nullableText(json['regionDescription']),
        value: _text(json['value']),
      );

  String get displayEntityName {
    if (entityName == 'PAGAMENTO' && operation == 'lancarPagamentoContrato') {
      return 'CONTRATO';
    }
    if (entityName == 'PAGAMENTO' &&
        (operation == 'adicionaPagamento' ||
            operation == 'deletaPagamentoEmprestimo')) {
      return 'EMPRESTIMO';
    }
    return entityName;
  }
}

final class AppAuditHistoryPage {
  final List<AppAuditHistoryItem> items;
  final int page;
  final int size;
  final bool hasNext;

  const AppAuditHistoryPage({
    required this.items,
    required this.page,
    required this.size,
    required this.hasNext,
  });

  factory AppAuditHistoryPage.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    return AppAuditHistoryPage(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => AppAuditHistoryItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      page: _int(json['page']),
      size: _int(json['size']),
      hasNext: json['hasNext'] == true,
    );
  }
}

final class AppAuditHistoryFilters {
  final DateTime startDate;
  final DateTime endDate;
  final Set<String> usernames;
  final Set<int> regionIds;

  const AppAuditHistoryFilters({
    required this.startDate,
    required this.endDate,
    required this.usernames,
    required this.regionIds,
  });

  factory AppAuditHistoryFilters.lastThirtyDays(DateTime now) {
    final DateTime end = DateTime(now.year, now.month, now.day);
    return AppAuditHistoryFilters(
      startDate: end.subtract(const Duration(days: 30)),
      endDate: end,
      usernames: const {},
      regionIds: const {},
    );
  }
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

int? _nullableInt(Object? value) {
  if (value == null) return null;
  return value is num ? value.toInt() : int.tryParse('$value');
}

String _text(Object? value) => value?.toString().trim() ?? '';

String? _nullableText(Object? value) {
  final String result = _text(value);
  return result.isEmpty ? null : result;
}
