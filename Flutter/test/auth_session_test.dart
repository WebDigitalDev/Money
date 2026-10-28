import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('sessão reconhece troca obrigatória de senha', () {
    final AuthSession session = AuthSession.fromJson(const {
      'token': 'token-de-teste',
      'name': 'USUARIO',
      'userId': 10,
      'administrator': false,
      'canEdit': true,
      'collector': true,
      'forcePasswordChange': true,
    });

    expect(session.forcePasswordChange, isTrue);
    expect(session.canEdit, isTrue);
    expect(session.collector, isTrue);
    expect(session.canManageRegions, isFalse);
  });

  test('sessões antigas mantêm cobrador desativado por padrão', () {
    final AuthSession session = AuthSession.fromJson(const {
      'token': 'token-antigo',
      'name': 'USUARIO',
      'userId': 11,
      'administrator': false,
      'canEdit': true,
      'forcePasswordChange': false,
    });

    expect(session.collector, isFalse);
  });

  test('somente administrador pode gerenciar regiões', () {
    const AuthSession administrator = AuthSession(
      token: 'token-admin',
      name: 'ADMINISTRADOR',
      userId: 1,
      administrator: true,
      canEdit: true,
      forcePasswordChange: false,
    );
    const AuthSession commonEditor = AuthSession(
      token: 'token-editor',
      name: 'USUÁRIO COMUM',
      userId: 2,
      administrator: false,
      canEdit: true,
      forcePasswordChange: false,
    );

    expect(administrator.canManageRegions, isTrue);
    expect(commonEditor.canManageRegions, isFalse);
  });
}
