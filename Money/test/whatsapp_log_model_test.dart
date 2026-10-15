import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('log do WhatsApp preserva região e telefone do destinatário', () {
    final AppWhatsappLog log = AppWhatsappLog.fromJson({
      'id': 45,
      'deviceId': 3,
      'deviceName': 'EVOLUTION',
      'clientId': 27,
      'loanId': 46806,
      'installmentId': 910,
      'type': 'VENCE_HOJE',
      'phone': '5565999907305',
      'clientName': 'CLIENTE TESTE',
      'regionName': 'ALPHACRED',
      'status': 'SUCESSO',
      'message': 'Mensagem',
      'createdAt': '2026-08-12T10:35:00',
    });

    expect(log.regionName, 'ALPHACRED');
    expect(log.phone, '5565999907305');
    expect(log.status, 'SUCESSO');
    expect(log.type, 'VENCE_HOJE');
  });
}
