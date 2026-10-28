import 'package:flutter_test/flutter_test.dart';
import 'package:money/data/models/app_integration.dart';

void main() {
  group('Status do dispositivo WhatsApp', () {
    test('dispositivo conectado sempre exibe CONECTADO', () {
      final device = AppWhatsappDevice.fromJson(const {
        'id': 1,
        'status': 'open',
        'connected': true,
      });

      expect(device.connected, isTrue);
      expect(device.status, 'CONECTADO');
    });

    test('status close exibe DESCONECTADO', () {
      final device = AppWhatsappDevice.fromJson(const {
        'id': 2,
        'status': 'close',
        'connected': false,
      });

      expect(device.connected, isFalse);
      expect(device.status, 'DESCONECTADO');
    });
  });
}
