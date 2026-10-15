import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('detalhe do cliente recebe o link do Google Maps', () {
    final AppClientDetail client = AppClientDetail.fromJson({
      'id': 10,
      'name': 'Cliente Teste',
      'type': 'FISICA',
      'enabled': true,
      'postalCode': 0,
      'googleMapsLink': 'https://maps.app.goo.gl/exemplo',
      'latitude': -15.601,
      'longitude': -56.097,
      'regionId': 2,
      'regionName': 'Região Central',
      'status': 'ACTIVE',
    });

    expect(client.googleMapsLink, 'https://maps.app.goo.gl/exemplo');
    expect(client.latitude, -15.601);
    expect(client.longitude, -56.097);
    expect(client.score.points, 100);
    expect(client.score.overdueDays, 0);
    expect(client.score.totalDebt, 0);
  });

  test('score do cliente interpreta métricas e limita valores inválidos', () {
    final AppClientDetail client = AppClientDetail.fromJson({
      'id': 11,
      'name': 'Cliente com histórico',
      'type': 'FISICA',
      'enabled': true,
      'postalCode': 0,
      'regionId': 2,
      'regionName': 'Região Central',
      'status': 'ACTIVE',
      'score': {'points': 130, 'overdueDays': 18, 'totalDebt': 734.56},
    });

    expect(client.score.points, 100);
    expect(client.score.overdueDays, 18);
    expect(client.score.totalDebt, 734.56);
  });

  test('cliente desaparecido sempre possui score zero no aplicativo', () {
    final AppClientDetail client = AppClientDetail.fromJson({
      'id': 12,
      'name': 'Cliente desaparecido',
      'type': 'FISICA',
      'enabled': true,
      'postalCode': 0,
      'regionId': 2,
      'regionName': 'Região Central',
      'status': 'MISSING',
      'score': {'points': 100, 'overdueDays': 0, 'totalDebt': 0},
    });

    expect(client.score.points, 0);
  });

  test('consulta empresarial interpreta os dados retornados pelo money2', () {
    final AppCompanyLookup company = AppCompanyLookup.fromJson({
      'document': '00000000000191',
      'legalName': 'BANCO DO BRASIL SA',
      'tradeName': 'DIRECAO GERAL',
      'primaryPhone': '6134939002',
      'postalCode': 70040912,
      'cityIbgeCode': 5300108,
      'cityName': 'BRASILIA',
      'state': 'DF',
      'address': 'QUADRA SAUN QUADRA 5 BLOCO B',
      'number': 'SN',
      'neighborhood': 'ASA NORTE',
    });

    expect(company.document, '00000000000191');
    expect(company.legalName, 'BANCO DO BRASIL SA');
    expect(company.postalCode, 70040912);
    expect(company.cityIbgeCode, 5300108);
  });
}
