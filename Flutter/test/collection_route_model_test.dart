import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('rota interpreta dívida, prioridade e status realizado', () {
    final AppCollectionRoutePage page = AppCollectionRoutePage.fromJson(const {
      'items': [
        {
          'clientId': 42,
          'clientName': 'CLIENTE TESTE',
          'regionId': 7,
          'regionName': 'REGIÃO CENTRAL',
          'totalDebt': 950.50,
          'overdueDebt': 300.25,
          'overdueDays': 18,
          'overdueLoans': 2,
          'address': 'Rua Teste, 100',
          'status': 'COMPLETED',
          'collectionCount': 3,
          'lastCollectionAt': '2026-09-11T08:30:00',
          'routeId': 91,
          'collectorId': 12,
          'collectorName': 'COBRADOR TESTE',
          'assignedAt': '2026-09-12T09:00:00',
        },
      ],
      'page': 0,
      'size': 50,
      'totalItems': 1,
      'totalPages': 1,
      'hasNext': false,
      'totalDebt': 950.50,
      'totalOverdueDebt': 300.25,
    });

    expect(page.items.single.status, AppCollectionRouteStatus.completed);
    expect(page.items.single.status.label, 'Realizado');
    expect(page.items.single.overdueDays, 18);
    expect(page.items.single.totalDebt, 950.50);
    expect(page.items.single.collectionCount, 3);
    expect(page.items.single.routeId, 91);
    expect(page.items.single.collectorId, 12);
    expect(page.items.single.collectorName, 'COBRADOR TESTE');
  });

  test('status ausente permanece em execução', () {
    final AppCollectionRouteItem item = AppCollectionRouteItem.fromJson(const {
      'clientId': 5,
    });

    expect(item.status, AppCollectionRouteStatus.inProgress);
    expect(item.status.label, 'Em execução');
  });
}
