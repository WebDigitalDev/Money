import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';

void main() {
  test('reativação envia o novo estado e devolve o cliente ativo', () async {
    late http.Request sentRequest;
    final ClientService service = ClientService.forTesting(
      MockClient((request) async {
        sentRequest = request;
        return http.Response(
          jsonEncode({
            'responseBody': {
              'id': 6307,
              'name': 'FELIPE GONÇALO DA SILVA CAMPOS',
              'enabled': true,
              'regionId': 33,
              'regionName': 'ALPHACRED',
              'status': 'INACTIVE',
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final AppClientDetail client = await service.setClientEnabled(6307, true);

    expect(sentRequest.method, 'PATCH');
    expect(sentRequest.url.path, '/api/v2/clients/6307/enabled');
    expect(jsonDecode(sentRequest.body), {'enabled': true});
    expect(client.enabled, isTrue);
  });
}
