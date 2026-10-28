import 'package:money/data/models/app_financial_goal.dart';

final class AppDashboardRegion {
  final int id;
  final String name;

  const AppDashboardRegion({required this.id, required this.name});

  factory AppDashboardRegion.fromJson(Map<String, dynamic> json) =>
      AppDashboardRegion(id: _int(json['id']), name: _text(json['name']));

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

final class AppDashboardMetrics {
  final int overdueClients;
  final int overdueLoans;
  final double overdueAmount;
  final double receivedTodayAmount;
  final int receivedTodayPayments;
  final double profitTodayAmount;
  final int settledTodayLoans;
  final int renewedTodayLoans;
  final int overdueInstallments;
  final int oldestOverdueDays;
  final int dueTodayLoans;
  final int dueTodayInstallments;
  final double dueTodayAmount;

  const AppDashboardMetrics({
    required this.overdueClients,
    required this.overdueLoans,
    required this.overdueAmount,
    required this.receivedTodayAmount,
    required this.receivedTodayPayments,
    required this.profitTodayAmount,
    required this.settledTodayLoans,
    required this.renewedTodayLoans,
    required this.overdueInstallments,
    required this.oldestOverdueDays,
    required this.dueTodayLoans,
    required this.dueTodayInstallments,
    required this.dueTodayAmount,
  });

  factory AppDashboardMetrics.fromJson(Map<String, dynamic> json) =>
      AppDashboardMetrics(
        overdueClients: _int(json['overdueClients']),
        overdueLoans: _int(json['overdueLoans'] ?? json['overdueClients']),
        overdueAmount: _double(json['overdueAmount']),
        receivedTodayAmount: _double(json['receivedTodayAmount']),
        receivedTodayPayments: _int(json['receivedTodayPayments']),
        profitTodayAmount: _double(json['profitTodayAmount']),
        settledTodayLoans: _int(json['settledTodayLoans']),
        renewedTodayLoans: _int(json['renewedTodayLoans']),
        overdueInstallments: _int(json['overdueInstallments']),
        oldestOverdueDays: _int(json['oldestOverdueDays']),
        dueTodayLoans: _int(
          json['dueTodayLoans'] ?? json['dueTodayInstallments'],
        ),
        dueTodayInstallments: _int(json['dueTodayInstallments']),
        dueTodayAmount: _double(json['dueTodayAmount']),
      );

  Map<String, dynamic> toJson() => {
    'overdueClients': overdueClients,
    'overdueLoans': overdueLoans,
    'overdueAmount': overdueAmount,
    'receivedTodayAmount': receivedTodayAmount,
    'receivedTodayPayments': receivedTodayPayments,
    'profitTodayAmount': profitTodayAmount,
    'settledTodayLoans': settledTodayLoans,
    'renewedTodayLoans': renewedTodayLoans,
    'overdueInstallments': overdueInstallments,
    'oldestOverdueDays': oldestOverdueDays,
    'dueTodayLoans': dueTodayLoans,
    'dueTodayInstallments': dueTodayInstallments,
    'dueTodayAmount': dueTodayAmount,
  };
}

final class AppDashboardFinancialPoint {
  final DateTime date;
  final double loanedAmount;
  final double receivedAmount;
  final double overdueAmount;
  final double profitAmount;

  const AppDashboardFinancialPoint({
    required this.date,
    required this.loanedAmount,
    required this.receivedAmount,
    required this.overdueAmount,
    required this.profitAmount,
  });

  factory AppDashboardFinancialPoint.fromJson(Map<String, dynamic> json) =>
      AppDashboardFinancialPoint(
        date: DateTime.tryParse(_text(json['date'])) ?? DateTime.now(),
        loanedAmount: _double(json['loanedAmount']),
        receivedAmount: _double(json['receivedAmount']),
        overdueAmount: _double(json['overdueAmount']),
        profitAmount: _double(json['profitAmount']),
      );

  Map<String, dynamic> toJson() => {
    'date': _date(date),
    'loanedAmount': loanedAmount,
    'receivedAmount': receivedAmount,
    'overdueAmount': overdueAmount,
    'profitAmount': profitAmount,
  };
}

final class AppDashboardFinancialSummary {
  final double loanedAmount;
  final double receivedAmount;
  final double overdueAmount;
  final double profitAmount;
  final List<AppDashboardFinancialPoint> points;

  const AppDashboardFinancialSummary({
    required this.loanedAmount,
    required this.receivedAmount,
    required this.overdueAmount,
    required this.profitAmount,
    required this.points,
  });

  factory AppDashboardFinancialSummary.fromJson(Map<String, dynamic> json) =>
      AppDashboardFinancialSummary(
        loanedAmount: _double(json['loanedAmount']),
        receivedAmount: _double(json['receivedAmount']),
        overdueAmount: _double(json['overdueAmount']),
        profitAmount: _double(json['profitAmount']),
        points: _maps(json['points'])
            .map(AppDashboardFinancialPoint.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'loanedAmount': loanedAmount,
    'receivedAmount': receivedAmount,
    'overdueAmount': overdueAmount,
    'profitAmount': profitAmount,
    'points': points.map((point) => point.toJson()).toList(growable: false),
  };
}

final class AppDashboardDueTodayLoan {
  final int loanId;
  final String clientName;
  final String regionName;
  final String paymentType;
  final double amount;

  const AppDashboardDueTodayLoan({
    required this.loanId,
    required this.clientName,
    required this.regionName,
    required this.paymentType,
    required this.amount,
  });

  factory AppDashboardDueTodayLoan.fromJson(Map<String, dynamic> json) =>
      AppDashboardDueTodayLoan(
        loanId: _int(json['loanId']),
        clientName: _text(json['clientName']),
        regionName: _text(json['regionName']),
        paymentType: _text(json['paymentType']),
        amount: _double(json['amount']),
      );

  Map<String, dynamic> toJson() => {
    'loanId': loanId,
    'clientName': clientName,
    'regionName': regionName,
    'paymentType': paymentType,
    'amount': amount,
  };
}

final class AppDashboardData {
  final String userName;
  final DateTime date;
  final int selectedRegionId;
  final String selectedRegionName;
  final List<int> selectedRegionIds;
  final List<AppDashboardRegion> regions;
  final AppDashboardMetrics metrics;
  final AppDashboardFinancialSummary financial;
  final List<AppFinancialGoal> activeGoals;
  final List<AppDashboardDueTodayLoan> dueToday;

  const AppDashboardData({
    required this.userName,
    required this.date,
    required this.selectedRegionId,
    required this.selectedRegionName,
    this.selectedRegionIds = const [],
    required this.regions,
    required this.metrics,
    required this.financial,
    this.activeGoals = const [],
    required this.dueToday,
  });

  factory AppDashboardData.fromJson(Map<String, dynamic> json) {
    final int selectedRegionId = _int(json['selectedRegionId']);
    final List<int> selectedRegionIds = json['selectedRegionIds'] is List
        ? (json['selectedRegionIds'] as List)
              .map(_int)
              .where((id) => id > 0)
              .toList(growable: false)
        : <int>[selectedRegionId];
    return AppDashboardData(
      userName: _text(json['userName']),
      date: DateTime.tryParse(_text(json['date'])) ?? DateTime.now(),
      selectedRegionId: selectedRegionId,
      selectedRegionName: _text(json['selectedRegionName']),
      selectedRegionIds: selectedRegionIds.isEmpty
          ? <int>[selectedRegionId]
          : selectedRegionIds,
      regions: _maps(json['regions'])
          .map(AppDashboardRegion.fromJson)
          .toList(growable: false),
      metrics: AppDashboardMetrics.fromJson(_map(json['metrics'])),
      financial: AppDashboardFinancialSummary.fromJson(_map(json['financial'])),
      activeGoals: _maps(json['activeGoals'])
          .map(AppFinancialGoal.fromJson)
          .toList(growable: false),
      dueToday: _maps(json['dueToday'])
          .map(AppDashboardDueTodayLoan.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'userName': userName,
    'date': _date(date),
    'selectedRegionId': selectedRegionId,
    'selectedRegionName': selectedRegionName,
    'selectedRegionIds': selectedRegionIds,
    'regions': regions.map((region) => region.toJson()).toList(growable: false),
    'metrics': metrics.toJson(),
    'financial': financial.toJson(),
    'activeGoals': activeGoals
        .map(
          (goal) => {
            'id': goal.id,
            'regionId': goal.regionId,
            'regionName': goal.regionName,
            'regionIds': goal.regionIds,
            'regionNames': goal.regionNames,
            'type': goal.type.code,
            'targetAmount': goal.targetAmount,
            'achievedAmount': goal.achievedAmount,
            'remainingAmount': goal.remainingAmount,
            'percentage': goal.percentage,
            'startDate': _date(goal.startDate),
            'endDate': _date(goal.endDate),
            'status': goal.status.code,
            'createdAt': goal.createdAt?.toIso8601String(),
            'updatedAt': goal.updatedAt?.toIso8601String(),
            'canManage': goal.canManage,
            'repeatFrequency': goal.repeatFrequency,
            if (goal.type.isClient)
              'clients': {
                'active': goal.activeClients,
                'onTime': goal.onTimeClients,
                'overdue': goal.overdueClients,
                'newClients': goal.newClients,
              },
          },
        )
        .toList(growable: false),
    'dueToday': dueToday.map((loan) => loan.toJson()).toList(growable: false),
  };
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
    : const <Map<String, dynamic>>[];

String _text(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value)) ?? 0;

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(_text(value)) ?? 0;

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
