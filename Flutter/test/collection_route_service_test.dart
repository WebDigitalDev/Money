import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';

void main() {
  test('rotas adicionadas enviam o filtro de cobrador', () async {
    late http.Request sentRequest;
    final CollectionRouteService service = CollectionRouteService.forTesting(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'responseBody': {
              'items': <Object>[],
              'page': 0,
              'size': 50,
              'totalItems': 0,
              'totalPages': 0,
              'hasNext': false,
              'totalDebt': 0,
              'totalOverdueDebt': 0,
            },
          }),
          200,
        );
      }),
    );

    await service.fetchRoutes(
      regionIds: const {3},
      collectorId: 17,
      cityId: 3142,
      force: true,
    );

    expect(sentRequest.url.path, '/api/v2/routes');
    expect(sentRequest.url.queryParameters['collectorId'], '17');
    expect(sentRequest.url.queryParameters['regionIds'], '3');
    expect(sentRequest.url.queryParameters['cityId'], '3142');
  });

  test('candidatos usa endpoint separado com filtros da criação', () async {
    late http.Request sentRequest;
    final CollectionRouteService service = CollectionRouteService.forTesting(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'responseBody': {
              'items': <Object>[],
              'page': 1,
              'size': 50,
              'totalItems': 0,
              'totalPages': 0,
              'hasNext': false,
              'totalDebt': 0,
              'totalOverdueDebt': 0,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await service.fetchCandidates(
      regionIds: const {9, 3},
      cityId: 3142,
      city: 'Goiânia',
      sort: AppCollectionRouteSort.overdueAmount,
      query: 'Maria',
      page: 1,
    );

    expect(sentRequest.url.path, '/api/v2/routes/candidates');
    expect(sentRequest.url.queryParameters['regionIds'], '3,9');
    expect(sentRequest.url.queryParameters['cityId'], '3142');
    expect(sentRequest.url.queryParameters['city'], 'Goiânia');
    expect(sentRequest.url.queryParameters['sort'], 'OVERDUE_AMOUNT');
    expect(sentRequest.url.queryParameters['query'], 'Maria');
    expect(sentRequest.url.queryParameters['page'], '1');
  });

  test('atribuição envia cobrador e clientes selecionados', () async {
    late http.Request sentRequest;
    final CollectionRouteService service = CollectionRouteService.forTesting(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'responseBody': {'assignedClients': 2},
          }),
          201,
        );
      }),
    );

    final int assigned = await service.assignRoutes(
      collectorId: 17,
      clientIds: const {42, 51},
    );

    expect(assigned, 2);
    expect(sentRequest.method, 'POST');
    expect(sentRequest.url.path, '/api/v2/routes/assignments');
    final Map<String, dynamic> body = jsonDecode(sentRequest.body);
    expect(body['collectorId'], 17);
    expect((body['clientIds'] as List).toSet(), {42, 51});
  });

  test('cidades de rotas respeitam lista, pesquisa e regiões atuais', () async {
    late http.Request sentRequest;
    final CollectionRouteService service = CollectionRouteService.forTesting(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'responseBody': [
              {
                'id': 3142,
                'ibgeCode': 5208707,
                'name': 'Goiânia',
                'state': 'GO',
                'displayName': 'Goiânia - GO',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final List<AppCityOption> cities = await service.fetchAvailableCities(
      regionIds: const {9, 3},
      query: 'Maria',
      assignedOnly: false,
    );

    expect(sentRequest.url.path, '/api/v2/routes/cities');
    expect(sentRequest.url.queryParameters['regionIds'], '3,9');
    expect(sentRequest.url.queryParameters['query'], 'Maria');
    expect(sentRequest.url.queryParameters['assignedOnly'], 'false');
    expect(cities.single.displayName, 'Goiânia - GO');
  });

  test('cobradores disponíveis vêm somente das rotas da lista atual', () async {
    late http.Request sentRequest;
    final CollectionRouteService service = CollectionRouteService.forTesting(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'responseBody': [
              {'id': 17, 'name': 'Matheus', 'username': 'MATHEUS'},
            ],
          }),
          200,
        );
      }),
    );

    final collectors = await service.fetchAssignedCollectors(
      regionIds: const {9, 3},
      cityId: 3142,
      query: 'Maria',
    );

    expect(sentRequest.url.path, '/api/v2/routes/assigned-collectors');
    expect(sentRequest.url.queryParameters['regionIds'], '3,9');
    expect(sentRequest.url.queryParameters['cityId'], '3142');
    expect(sentRequest.url.queryParameters['query'], 'Maria');
    expect(collectors.single.name, 'Matheus');
  });

  test('remoção apaga somente a atribuição da rota', () async {
    late http.Request sentRequest;
    final CollectionRouteService service = CollectionRouteService.forTesting(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(jsonEncode({'responseBody': true}), 200);
      }),
    );

    await service.removeRoute(42);

    expect(sentRequest.method, 'DELETE');
    expect(sentRequest.url.path, '/api/v2/routes/42/assignment');
  });
}
