import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'dashboard reutiliza cache recente e atualização forçada busca novamente',
    () async {
      SharedPreferences.setMockInitialValues({});
      int requests = 0;
      final List<String?> validators = [];
      final List<String?> cacheControls = [];
      final MockClient client = MockClient((http.Request request) async {
        requests++;
        validators.add(request.headers['If-None-Match']);
        cacheControls.add(request.headers['Cache-Control']);
        final double overdue = requests == 1 ? 100 : 250;
        return http.Response(
          jsonEncode(_dashboardEnvelope(overdue)),
          200,
          headers: {'etag': requests == 1 ? 'W/"painel-v1"' : 'W/"painel-v2"'},
        );
      });
      final DashboardService service = DashboardService.forTesting(client);

      final AppDashboardData first = await service.fetchDashboard(regionId: 33);
      final AppDashboardData reused = await service.fetchDashboard(
        regionId: 33,
      );
      final AppDashboardData refreshed = await service.fetchDashboard(
        regionId: 33,
        forceRefresh: true,
      );

      expect(first.metrics.overdueAmount, 100);
      expect(reused, same(first));
      expect(refreshed.metrics.overdueAmount, 250);
      expect(requests, 2);
      expect(validators, [null, null]);
      expect(cacheControls, ['no-cache', 'no-cache']);
      expect(service.cachedDashboard(regionId: 33), same(refreshed));
    },
  );

  test('dashboard compartilha requisições idênticas em andamento', () async {
    SharedPreferences.setMockInitialValues({});
    int requests = 0;
    final Completer<void> release = Completer<void>();
    final MockClient client = MockClient((http.Request request) async {
      requests++;
      await release.future;
      return http.Response(jsonEncode(_dashboardEnvelope(125)), 200);
    });
    final DashboardService service = DashboardService.forTesting(client);

    final Future<AppDashboardData> first = service.fetchDashboard(
      regionIds: const [33, 41],
      forceRefresh: true,
    );
    final Future<AppDashboardData> second = service.fetchDashboard(
      regionIds: const [41, 33],
      forceRefresh: true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(requests, 1);
    release.complete();
    final List<AppDashboardData> results = await Future.wait([first, second]);
    expect(results[0], same(results[1]));
  });

  test('dashboard do tutorial usa rota e cache exclusivos', () async {
    SharedPreferences.setMockInitialValues({});
    final List<Uri> requests = <Uri>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request.url);
      final bool tutorial = request.url.queryParameters['tutorial'] == 'true';
      return http.Response(
        jsonEncode(_dashboardEnvelope(tutorial ? 9 : 90)),
        200,
      );
    });
    final DashboardService service = DashboardService.forTesting(client);

    final AppDashboardData normal = await service.fetchDashboard(regionId: 33);
    final AppDashboardData tutorial = await service.fetchDashboard(
      regionId: 33,
      tutorialMode: true,
    );

    expect(normal.metrics.overdueAmount, 90);
    expect(tutorial.metrics.overdueAmount, 9);
    expect(service.cachedDashboard(regionId: 33), same(normal));
    expect(
      service.cachedDashboard(regionId: 33, tutorialMode: true),
      same(tutorial),
    );
    expect(requests.last.queryParameters['tutorial'], 'true');
  });
}

Map<String, Object?> _dashboardEnvelope(double overdueAmount) => {
  'responseBody': {
    'userName': 'Administrador',
    'date': '2026-08-20',
    'selectedRegionId': 33,
    'selectedRegionName': 'ALPHACRED',
    'regions': [
      {'id': 33, 'name': 'ALPHACRED'},
    ],
    'metrics': {
      'overdueClients': 1,
      'overdueLoans': 1,
      'overdueAmount': overdueAmount,
      'receivedTodayAmount': 0,
      'receivedTodayPayments': 0,
      'profitTodayAmount': 0,
      'settledTodayLoans': 0,
      'renewedTodayLoans': 0,
      'overdueInstallments': 1,
      'oldestOverdueDays': 1,
      'dueTodayLoans': 0,
      'dueTodayInstallments': 0,
      'dueTodayAmount': 0,
    },
    'financial': {
      'loanedAmount': 0,
      'receivedAmount': 0,
      'overdueAmount': overdueAmount,
      'profitAmount': 0,
      'points': const [],
    },
    'dueToday': const [],
  },
};
