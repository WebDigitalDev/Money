enum AppFinancialGoalType {
  loaned('EMPRESTADO', 'Valor emprestado'),
  received('RECEBIDO', 'Valor recebido'),
  profit('LUCRO', 'Lucro'),
  newClients('CLIENTES_ATIVOS', 'Novos clientes ativos'),
  onTimeClients('CLIENTES_EM_DIA', 'Clientes em dia'),
  overdueClients('CLIENTES_ATRASO', 'Clientes em atraso');

  bool get isClient => code.startsWith('CLIENTES_');
  bool get isPercentage => this == onTimeClients || this == overdueClients;

  final String code;
  final String label;

  const AppFinancialGoalType(this.code, this.label);

  static AppFinancialGoalType fromCode(Object? value) => values.firstWhere(
    (type) => type.code == value?.toString().trim().toUpperCase(),
    orElse: () => loaned,
  );
}

enum AppFinancialGoalStatus {
  upcoming('FUTURA', 'Futura'),
  active('ATIVA', 'Em andamento'),
  completed('ENCERRADA', 'Encerrada');

  final String code;
  final String label;

  const AppFinancialGoalStatus(this.code, this.label);

  static AppFinancialGoalStatus fromCode(Object? value) => values.firstWhere(
    (status) => status.code == value?.toString().trim().toUpperCase(),
    orElse: () => active,
  );
}

final class AppFinancialGoal {
  final int id;
  final int regionId;
  final String regionName;
  final List<int> regionIds;
  final List<String> regionNames;
  final AppFinancialGoalType type;
  final double targetAmount;
  final double achievedAmount;
  final double remainingAmount;
  final double percentage;
  final DateTime startDate;
  final DateTime endDate;
  final AppFinancialGoalStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool canManage;
  final int activeClients;
  final int onTimeClients;
  final int overdueClients;
  final int newClients;
  final bool repeatFrequency;

  const AppFinancialGoal({
    required this.id,
    required this.regionId,
    required this.regionName,
    this.regionIds = const [],
    this.regionNames = const [],
    required this.type,
    required this.targetAmount,
    required this.achievedAmount,
    required this.remainingAmount,
    required this.percentage,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.canManage,
    this.activeClients = 0,
    this.onTimeClients = 0,
    this.overdueClients = 0,
    this.newClients = 0,
    this.repeatFrequency = false,
  });

  factory AppFinancialGoal.fromJson(Map<String, dynamic> json) {
    final int regionId = _int(json['regionId']);
    final String regionName = _text(json['regionName'], fallback: 'Região');
    final List<int> regionIds = json['regionIds'] is List
        ? (json['regionIds'] as List)
              .map(_int)
              .where((id) => id > 0)
              .toList(growable: false)
        : <int>[regionId];
    final List<String> regionNames = json['regionNames'] is List
        ? (json['regionNames'] as List)
              .map((value) => _text(value))
              .where((name) => name.isNotEmpty)
              .toList(growable: false)
        : <String>[regionName];
    return AppFinancialGoal(
      id: _int(json['id']),
      regionId: regionId,
      regionName: regionName,
      regionIds: regionIds.isEmpty ? <int>[regionId] : regionIds,
      regionNames: regionNames.isEmpty ? <String>[regionName] : regionNames,
      type: AppFinancialGoalType.fromCode(json['type']),
      targetAmount: _double(json['targetAmount']),
      achievedAmount: _double(json['achievedAmount']),
      remainingAmount: _double(json['remainingAmount']),
      percentage: _double(json['percentage']),
      startDate: _date(json['startDate']) ?? DateTime.now(),
      endDate: _date(json['endDate']) ?? DateTime.now(),
      status: AppFinancialGoalStatus.fromCode(json['status']),
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
      canManage: json['canManage'] == true,
      activeClients: _int((json['clients'] as Map?)?['active']),
      onTimeClients: _int((json['clients'] as Map?)?['onTime']),
      overdueClients: _int((json['clients'] as Map?)?['overdue']),
      newClients: _int((json['clients'] as Map?)?['newClients']),
      repeatFrequency: json['repeatFrequency'] == true,
    );
  }

  double get displayPercentage => percentage.clamp(0, 100).toDouble();
  double get progress => (percentage / 100).clamp(0, 1);
  bool get isRegionGroup => regionIds.length > 1;

  bool isVisibleInGoalsAt(DateTime moment) {
    if (status != AppFinancialGoalStatus.completed) return true;
    final DateTime hiddenAt = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 3));
    return moment.isBefore(hiddenAt);
  }
}

final class AppFinancialGoalDraft {
  final List<int> regionIds;
  final AppFinancialGoalType type;
  final double targetAmount;
  final DateTime startDate;
  final DateTime endDate;
  final bool repeatFrequency;

  const AppFinancialGoalDraft({
    required this.regionIds,
    required this.type,
    required this.targetAmount,
    required this.startDate,
    required this.endDate,
    this.repeatFrequency = false,
  });

  Map<String, dynamic> toJson() => {
    'regionId': regionIds.first,
    'regionIds': regionIds,
    'type': type.code,
    'targetAmount': targetAmount,
    'startDate': _formatDate(startDate),
    'endDate': _formatDate(endDate),
    'repeatFrequency': repeatFrequency,
  };
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _text(Object? value, {String fallback = ''}) {
  final String result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

DateTime? _date(Object? value) {
  final DateTime? parsed = DateTime.tryParse(_text(value));
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime? _dateTime(Object? value) => DateTime.tryParse(_text(value));

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
