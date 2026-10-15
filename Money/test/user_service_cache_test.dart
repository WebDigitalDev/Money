import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';

void main() {
  test('usuários usam ETag e reaproveitam a página no 304', () async {
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
                'name': 'Administrador',
                'username': 'ADMINISTRADOR',
                'enabled': true,
                'administrator': true,
                'canEdit': true,
              },
            ],
            'page': 0,
            'size': 30,
            'totalItems': 1,
            'totalPages': 1,
            'hasNext': false,
          },
        }),
        200,
        headers: {'etag': 'W/"usuarios-v1"'},
      );
    });
    final UserService service = UserService.forTesting(client);

    final AppUserPage first = await service.fetchUsers();
    final AppUserPage second = await service.fetchUsers();

    expect(first.items.single.username, 'ADMINISTRADOR');
    expect(second, same(first));
    expect(validators, [null, 'W/"usuarios-v1"']);
    expect(service.cachedUsers(), same(first));
  });

  test('limpeza do cache remove também o validador HTTP', () async {
    final List<String?> validators = [];
    final MockClient client = MockClient((http.Request request) async {
      validators.add(request.headers['If-None-Match']);
      return http.Response(
        jsonEncode({
          'responseBody': {
            'items': const [],
            'page': 0,
            'size': 30,
            'totalItems': 0,
            'totalPages': 0,
            'hasNext': false,
          },
        }),
        200,
        headers: {'etag': 'W/"vazio-v1"'},
      );
    });
    final UserService service = UserService.forTesting(client);

    await service.fetchUsers();
    service.clearCache();
    expect(service.cachedUsers(), isNull);
    await service.fetchUsers();

    expect(validators, [null, null]);
  });
}
