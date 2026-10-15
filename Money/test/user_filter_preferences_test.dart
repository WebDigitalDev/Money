import 'package:flutter_test/flutter_test.dart';
import 'package:money/data/services/shared_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('salva filtros por tela e por usuário', () async {
    final SharedPreferencesService service = SharedPreferencesService();

    await service.saveUserFilters(
      scope: 'conferences',
      userId: 7,
      filters: <String, Object?>{
        'regionIds': <int>[12, 25],
      },
    );
    await service.saveUserFilters(
      scope: 'conferences',
      userId: 9,
      filters: <String, Object?>{
        'regionIds': <int>[31],
      },
    );

    expect(
      await service.getUserFilters(scope: 'conferences', userId: 7),
      <String, Object?>{
        'regionIds': <Object?>[12, 25],
      },
    );
    expect(
      await service.getUserFilters(scope: 'conferences', userId: 9),
      <String, Object?>{
        'regionIds': <Object?>[31],
      },
    );
  });

  test('mantém a chave já usada pelos filtros de empréstimos', () async {
    final SharedPreferencesService service = SharedPreferencesService();
    await service.saveUserFilters(
      scope: 'loans',
      userId: 42,
      filters: <String, Object?>{
        'statuses': <String>['Em atraso'],
      },
    );

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('loans.filters.user.42'), isTrue);
  });

  test('ignora cache inválido sem interromper a tela', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'clients.filters.user.5': '{invalido',
    });

    expect(
      await SharedPreferencesService().getUserFilters(
        scope: 'clients',
        userId: 5,
      ),
      isNull,
    );
  });
}
