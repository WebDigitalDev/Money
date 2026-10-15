import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:money/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistentCacheService().initialize();
    await PersistentCacheService().clearAll();
    PersistentCacheService().resumeWrites();
  });

  test('cache permanece no armazenamento e é removido no logout', () async {
    final PersistentCacheService cache = PersistentCacheService();
    await cache.write(
      'users',
      '0||0|30',
      etag: 'W/"persistente"',
      data: {
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
    );

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getKeys().where(
        (key) => key.startsWith('money.read_cache.v1.'),
      ),
      isNotEmpty,
    );

    final UserService restored = UserService.forTesting(
      MockClient((_) async => throw StateError('A rede não deve ser usada.')),
    );
    expect(restored.cachedUsers()?.items.single.username, 'ADMINISTRADOR');

    await cache.clearAll(suspendWrites: true);
    await cache.write('users', 'resposta-atrasada', data: const {'items': []});
    expect(
      preferences.getKeys().where(
        (key) => key.startsWith('money.read_cache.v1.'),
      ),
      isEmpty,
    );
  });
}
