import 'package:flutter_test/flutter_test.dart';
import 'package:money/data/services/auth_service.dart';

void main() {
  test('uses the permanent Money API domain by default', () {
    expect(AuthService.apiBaseUrl, 'https://moneyapp.site');
  });
}
