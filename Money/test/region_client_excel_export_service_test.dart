import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('gera planilha de regiões com as colunas financeiras legadas', () async {
    final AppRegionExcelFile file = await RegionExcelExportService().create([
      const AppRegionSummary(
        id: 7,
        description: 'ALPHACRED',
        responsiblePeople: 'DANIEL',
        activeClients: 65,
        missingClients: 2,
        currentClients: 40,
        overdueClients: 23,
        overdueAmount: 1200,
        receivedAmount: 800,
        dueTodayAmount: 300,
        receivableAmount: 5000,
        missingAmount: 250,
        profitAmount: 600,
        loanedAmount: 4000,
      ),
    ]);

    expect(file.fileName, startsWith('regioesResumidas_'));
    final String worksheet = _worksheet(file.bytes);
    expect(worksheet, contains('Descrição'));
    expect(worksheet, contains('Valor recebido hoje'));
    expect(worksheet, contains('ALPHACRED - DANIEL'));
    expect(worksheet, contains('<autoFilter ref="A1:L2"/>'));
  });

  test('gera uma linha por cliente com os dados da listagem', () async {
    final AppClientExcelFile file = await ClientExcelExportService().create([
      const AppClientSummary(
        id: 15,
        name: 'MARIA & FILHOS',
        document: '123.456.789-00',
        primaryPhone: '(65) 99999-0000',
        regionId: 7,
        regionName: 'ALPHACRED',
        status: AppClientStatus.withoutLoans,
      ),
    ]);

    expect(file.fileName, startsWith('clientes_'));
    final String worksheet = _worksheet(file.bytes);
    expect(worksheet, contains('CPF/CNPJ'));
    expect(worksheet, contains('MARIA &amp; FILHOS'));
    expect(worksheet, contains('Sem empréstimos'));
    expect(worksheet, contains('<autoFilter ref="A1:F2"/>'));
  });
}

String _worksheet(List<int> bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  final ArchiveFile? worksheet = archive.find('xl/worksheets/sheet1.xml');
  expect(worksheet, isNotNull);
  return utf8.decode(worksheet!.readBytes()!);
}
