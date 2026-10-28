import 'dart:typed_data';

import 'package:money/data/models/app_loan.dart';
import 'package:money/data/services/table_excel_export_service.dart';

typedef LoanExcelProgressCallback =
    void Function(double progress, String status);

final class AppLoanExcelFile {
  final Uint8List bytes;
  final String fileName;

  const AppLoanExcelFile({required this.bytes, required this.fileName});
}

final class LoanExcelExportService {
  static const List<AppExcelColumn> _columns = [
    AppExcelColumn('ID', width: 12, type: AppExcelColumnType.number),
    AppExcelColumn('Nome', width: 42),
    AppExcelColumn('Tipo', width: 22),
    AppExcelColumn('Status', width: 22),
    AppExcelColumn('Próximo vencimento', width: 22),
    AppExcelColumn(
      'Valor emprestado',
      width: 21,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor recebido',
      width: 21,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor a receber',
      width: 21,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor do lucro',
      width: 21,
      type: AppExcelColumnType.currency,
    ),
  ];

  Future<AppLoanExcelFile> create(
    List<AppLoanSummary> loans, {
    LoanExcelProgressCallback? onProgress,
  }) async {
    final AppTableExcelFile file = await TableExcelExportService().create(
      items: loans,
      columns: _columns,
      rowBuilder: (loan) => [
        loan.id,
        loan.clientName,
        loan.paymentType,
        loan.status,
        _date(loan.nextDueDate),
        loan.loanedAmount,
        loan.receivedAmount,
        loan.receivableAmount,
        loan.profitAmount,
      ],
      sheetName: 'Empréstimos',
      filePrefix: 'exportarEmprestimos',
      itemLabel: 'empréstimo(s)',
      onProgress: onProgress,
    );
    return AppLoanExcelFile(bytes: file.bytes, fileName: file.fileName);
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
}
