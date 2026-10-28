import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:money/data/services/notification_preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('novo dispositivo começa desativado e mantém a escolha local', () async {
    final store = NotificationPreferencesStore();
    expect(await store.read(1), isEmpty);
    await store.write(1, {'payments': true, 'goals': false});
    expect((await NotificationPreferencesStore().read(1))['payments'], isTrue);
    expect(await store.read(2), isEmpty);
    SharedPreferences.setMockInitialValues({});
    expect(await NotificationPreferencesStore().read(1), isEmpty);
  });

  test('preferência corrompida não ativa alertas', () async {
    SharedPreferences.setMockInitialValues({
      'money.deviceNotifications.v1.1': 'invalid',
    });
    expect(await NotificationPreferencesStore().read(1), isEmpty);
  });
}
