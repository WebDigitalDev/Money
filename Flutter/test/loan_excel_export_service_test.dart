import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test(
    'gera planilha XLSX de empréstimos com colunas e valores legados',
    () async {
      double progress = 0;
      final AppLoanExcelFile file = await LoanExcelExportService().create([
        AppLoanSummary(
          id: 47128,
          clientName: 'RONALDO & SILVA',
          regionId: 7,
          regionName: 'ALPHACRED',
          cityName: 'Várzea Grande',
          nextDueDate: DateTime(2026, 8, 17),
          createdAt: DateTime(2026, 7, 17),
          status: 'Em dia',
          statusColor: '#76B475',
          receivableAmount: 1300,
          receivedAmount: 200,
          loanedAmount: 1000,
          profitAmount: 300,
          paymentType: 'Diário',
          negotiated: false,
          installmentProgress: '2/13',
          collateral: null,
        ),
      ], onProgress: (value, _) => progress = value);

      expect(file.fileName, startsWith('exportarEmprestimos_'));
      expect(file.fileName, endsWith('.xlsx'));
      expect(file.bytes.take(2), [0x50, 0x4b]);
      expect(progress, 1);

      final Archive archive = ZipDecoder().decodeBytes(file.bytes);
      final ArchiveFile? worksheet = archive.find('xl/worksheets/sheet1.xml');
      final ArchiveFile? styles = archive.find('xl/styles.xml');
      expect(worksheet, isNotNull);
      expect(styles, isNotNull);

      final String worksheetXml = utf8.decode(worksheet!.readBytes()!);
      expect(worksheetXml, contains('Próximo vencimento'));
      expect(worksheetXml, contains('RONALDO &amp; SILVA'));
      expect(worksheetXml, contains('17/08/2026'));
      expect(worksheetXml, contains('<v>1300.0</v>'));
      expect(worksheetXml, contains('<autoFilter ref="A1:I2"/>'));

      final String stylesXml = utf8.decode(styles!.readBytes()!);
      expect(stylesXml, contains(r'formatCode="R$ #,##0.00"'));
      expect(stylesXml, contains('FF76B475'));
    },
  );
}
