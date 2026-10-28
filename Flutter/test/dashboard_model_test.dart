import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('métricas do dashboard preservam lucro e quitados do dia', () {
    final AppDashboardMetrics metrics = AppDashboardMetrics.fromJson({
      'overdueClients': 2,
      'overdueLoans': 4,
      'overdueAmount': 150,
      'receivedTodayAmount': 700,
      'receivedTodayPayments': 4,
      'profitTodayAmount': 200,
      'settledTodayLoans': 3,
      'renewedTodayLoans': 2,
      'overdueInstallments': 5,
      'oldestOverdueDays': 10,
      'dueTodayLoans': 8,
      'dueTodayInstallments': 6,
      'dueTodayAmount': 900,
    });

    expect(metrics.profitTodayAmount, 200);
    expect(metrics.overdueLoans, 4);
    expect(metrics.dueTodayLoans, 8);
    expect(metrics.settledTodayLoans, 3);
    expect(metrics.renewedTodayLoans, 2);
    expect(metrics.toJson()['profitTodayAmount'], 200);
    expect(metrics.toJson()['settledTodayLoans'], 3);
    expect(metrics.toJson()['renewedTodayLoans'], 2);
  });

  test('cache anterior assume zero para as novas métricas', () {
    final AppDashboardMetrics metrics = AppDashboardMetrics.fromJson({
      'overdueClients': 5,
      'dueTodayInstallments': 9,
    });

    expect(metrics.overdueLoans, 5);
    expect(metrics.dueTodayLoans, 9);
    expect(metrics.profitTodayAmount, 0);
    expect(metrics.settledTodayLoans, 0);
    expect(metrics.renewedTodayLoans, 0);
  });

  test('resumo financeiro preserva o lucro diário do gráfico', () {
    final AppDashboardFinancialSummary summary =
        AppDashboardFinancialSummary.fromJson({
          'loanedAmount': 1000,
          'receivedAmount': 700,
          'overdueAmount': 50,
          'profitAmount': 200,
          'points': [
            {
              'date': '2026-08-14',
              'loanedAmount': 1000,
              'receivedAmount': 700,
              'overdueAmount': 50,
              'profitAmount': 200,
            },
          ],
        });

    expect(summary.profitAmount, 200);
    expect(summary.points.single.profitAmount, 200);
    expect(summary.toJson()['profitAmount'], 200);
    expect((summary.toJson()['points'] as List).single['profitAmount'], 200);
  });

  test('cache anterior assume lucro zero no resumo financeiro', () {
    final AppDashboardFinancialSummary summary =
        AppDashboardFinancialSummary.fromJson({
          'loanedAmount': 1000,
          'receivedAmount': 700,
          'overdueAmount': 50,
          'points': [
            {
              'date': '2026-08-14',
              'loanedAmount': 1000,
              'receivedAmount': 700,
              'overdueAmount': 50,
            },
          ],
        });

    expect(summary.profitAmount, 0);
    expect(summary.points.single.profitAmount, 0);
  });

  test('dashboard interpreta as metas financeiras em andamento', () {
    final AppDashboardData dashboard = AppDashboardData.fromJson({
      'userName': 'Administrador',
      'date': '2026-08-28',
      'selectedRegionId': 7,
      'selectedRegionName': 'ATLAS CRED',
      'selectedRegionIds': [7],
      'regions': <Object>[],
      'metrics': <String, Object>{},
      'financial': <String, Object>{},
      'activeGoals': [
        {
          'id': 11,
          'regionId': 7,
          'regionName': 'ATLAS CRED',
          'type': 'LUCRO',
          'targetAmount': 5000,
          'achievedAmount': 1250,
          'remainingAmount': 3750,
          'percentage': 25,
          'startDate': '2026-08-01',
          'endDate': '2026-08-31',
          'status': 'ATIVA',
          'canManage': false,
        },
      ],
      'dueToday': <Object>[],
    });

    expect(dashboard.activeGoals, hasLength(1));
    expect(dashboard.activeGoals.single.type, AppFinancialGoalType.profit);
    expect(dashboard.toJson()['activeGoals'], hasLength(1));
  });
}
