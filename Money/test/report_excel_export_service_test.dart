import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('identifica pagamento distribuído pelo número do contrato', () {
    final AppAuditHistoryItem item = AppAuditHistoryItem(
      id: 1,
      entityName: 'PAGAMENTO',
      username: 'CHINAYDER',
      entityId: 47597,
      operation: 'lancarPagamentoContrato',
      description: 'Pagamento de 150.00 distribuído entre as parcelas.',
      timestamp: DateTime(2026, 9, 11),
      regionId: 1,
      regionDescription: 'CAPITALIZE',
      value: '150.00',
    );

    expect(item.displayEntityName, 'CONTRATO');
  });

  test('gera o histórico com as nove colunas da aplicação antiga', () async {
    final AppReportExcelFile file = await AuditHistoryExcelExportService()
        .create([
          AppAuditHistoryItem(
            id: 932,
            entityName: 'PAGAMENTO',
            username: 'admin',
            entityId: 47128,
            operation: 'adicionaPagamento',
            description: 'Adicionado pagamento no valor de R\$ 1.300,00 do cliente RONALDO & SILVA.',
            timestamp: DateTime(2026, 8, 17, 9, 57),
            regionId: 7,
            regionDescription: 'ALPHACRED',
            value: r'R$ 1.300,00',
          ),
        ]);

    expect(file.fileName, startsWith('historicoAlteracoes_'));
    final Archive archive = ZipDecoder().decodeBytes(file.bytes);
    final String worksheet = _xml(archive, 'xl/worksheets/sheet1.xml');

    expect(worksheet, contains('ID da Entidade'));
    expect(worksheet, contains('Data e Hora'));
    expect(worksheet, contains('RONALDO &amp; SILVA'));
    expect(worksheet, contains(r'R$ 1.300,00'));
    expect(worksheet, contains('<autoFilter ref="A1:I2"/>'));
  });

  test('gera relatório geral com regiões, empréstimos e penhoras', () async {
    final AppReportExcelFile file = await GeneralReportExcelExportService()
        .create(
          regions: [
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
          ],
          loans: [
            _loan(id: 47128, client: 'CONTRATO NORMAL'),
            _loan(
              id: 47129,
              client: 'CONTRATO COM PENHORA',
              color: '#40e0d0',
              collateral: 'Honda Biz 2024',
            ),
          ],
        );

    expect(file.fileName, startsWith('relatorio_geral_moneyapp_'));
    final Archive archive = ZipDecoder().decodeBytes(file.bytes);
    final String workbook = _xml(archive, 'xl/workbook.xml');
    final String regions = _xml(archive, 'xl/worksheets/sheet1.xml');
    final String loans = _xml(archive, 'xl/worksheets/sheet2.xml');
    final String collateral = _xml(archive, 'xl/worksheets/sheet3.xml');

    expect(workbook, contains('name="Regiões"'));
    expect(workbook, contains('name="Empréstimos"'));
    expect(workbook, contains('name="Penhoras"'));
    expect(regions, contains('Desaparecidos'));
    expect(regions, contains('ALPHACRED - DANIEL'));
    expect(loans, contains('CONTRATO NORMAL'));
    expect(loans, contains('CONTRATO COM PENHORA'));
    expect(collateral, isNot(contains('CONTRATO NORMAL')));
    expect(collateral, contains('CONTRATO COM PENHORA'));
    expect(collateral, contains('Honda Biz 2024'));
  });
}

AppLoanSummary _loan({
  required int id,
  required String client,
  String color = '#76B475',
  String? collateral,
}) => AppLoanSummary(
  id: id,
  clientName: client,
  regionId: 7,
  regionName: 'ALPHACRED',
  cityName: 'Várzea Grande',
  nextDueDate: DateTime(2026, 8, 20),
  createdAt: DateTime(2026, 7, 17),
  status: 'Em dia',
  statusColor: color,
  receivableAmount: 1300,
  receivedAmount: 200,
  loanedAmount: 1000,
  profitAmount: 300,
  paymentType: 'Diário',
  negotiated: false,
  installmentProgress: '2/13',
  collateral: collateral,
);

String _xml(Archive archive, String path) {
  final ArchiveFile? file = archive.find(path);
  expect(file, isNotNull);
  return utf8.decode(file!.readBytes()!);
}
