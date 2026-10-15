import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';

void main() {
  test('regiões usam ETag sem perder os totais monetários', () async {
    int requests = 0;
    final List<String?> validators = [];
    final MockClient client = MockClient((http.Request request) async {
      requests++;
      validators.add(request.headers['If-None-Match']);
      if (requests == 2) return http.Response('', 304);

      return http.Response(
        jsonEncode({
          'responseBody': {
            'items': [
              {
                'id': 7,
                'description': 'Centro',
                'responsiblePeople': 'Daniel',
                'activeClients': 12,
                'missingClients': 1,
                'currentClients': 9,
                'overdueClients': 3,
                'overdueAmount': 315.25,
                'receivedAmount': 950.50,
                'dueTodayAmount': 80.00,
                'receivableAmount': 1230.75,
                'missingAmount': 50.00,
                'profitAmount': 220.30,
                'loanedAmount': 1000.00,
              },
            ],
            'totals': {
              'regions': 1,
              'activeClients': 12,
              'missingClients': 1,
              'currentClients': 9,
              'overdueClients': 3,
              'overdueAmount': 315.25,
              'receivedAmount': 950.50,
              'dueTodayAmount': 80.00,
              'receivableAmount': 1230.75,
              'missingAmount': 50.00,
              'profitAmount': 220.30,
              'loanedAmount': 1000.00,
            },
            'startDate': '2026-07-11',
            'endDate': '2026-08-10',
          },
        }),
        200,
        headers: {'etag': 'W/"regioes-v1"'},
      );
    });
    final RegionService service = RegionService.forTesting(client);
    final AppRegionFilters filters = AppRegionFilters(
      startDate: DateTime(2026, 7, 11),
      endDate: DateTime(2026, 8, 10),
    );

    final AppRegionListData first = await service.fetchRegions(
      query: '',
      filters: filters,
    );
    final AppRegionListData second = await service.fetchRegions(
      query: '',
      filters: filters,
    );

    expect(first.items.single.displayName, 'Centro - Daniel');
    expect(first.totals.receivableAmount, 1230.75);
    expect(second, same(first));
    expect(validators, [null, 'W/"regioes-v1"']);
    expect(service.cachedRegions(query: '', filters: filters), same(first));
  });

  test(
    'opções do tutorial usam rota isolada e não contaminam o cache normal',
    () async {
      final List<Uri> requests = <Uri>[];
      final MockClient client = MockClient((http.Request request) async {
        requests.add(request.url);
        final bool tutorial = request.url.queryParameters['tutorial'] == 'true';
        return http.Response(
          jsonEncode({
            'responseBody': [
              {
                'id': tutorial ? 1000000001 : 7,
                'name': tutorial ? 'TUTORIAL' : 'ALPHACRED - DANIEL',
              },
            ],
          }),
          200,
        );
      });
      final RegionService service = RegionService.forTesting(client);

      final List<AppRegionOption> normal = await service.fetchOptions(
        force: true,
      );
      final List<AppRegionOption> tutorial = await service.fetchOptions(
        tutorialMode: true,
      );
      final List<AppRegionOption> cachedNormal = await service.fetchOptions();

      expect(normal.single.name, 'ALPHACRED - DANIEL');
      expect(tutorial.single.name, 'TUTORIAL');
      expect(cachedNormal.single.name, 'ALPHACRED - DANIEL');
      expect(requests, hasLength(2));
      expect(requests.last.queryParameters, {'tutorial': 'true'});
    },
  );
}
