import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';

void main() {
  test('duplicação lista regiões válidas e envia a região escolhida', () async {
    final List<http.Request> requests = [];
    final ClientService service = ClientService.forTesting(
      MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'responseBody': [
                {'id': 8, 'name': 'CASH - CHINAYDER'},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'responseBody': {
              'id': 99,
              'name': 'CLIENTE TESTE',
              'regionId': 8,
              'regionName': 'CASH - CHINAYDER',
              'status': 'ACTIVE',
            },
          }),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final List<AppRegionOption> regions = await service.fetchDuplicateRegions(
      7,
    );
    final AppClientDetail copy = await service.duplicateClient(7, 8);

    expect(regions.single.id, 8);
    expect(requests.first.url.path, '/api/v2/clients/7/duplicate-regions');
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/v2/clients/7/duplicate');
    expect(jsonDecode(requests.last.body), {'regionId': 8});
    expect(copy.id, 99);
    expect(copy.regionId, 8);
  });
}
