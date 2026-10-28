import 'package:money/data/models/app_chat.dart';
import 'package:money/data/services/table_excel_export_service.dart';

final class ChatLoanExcelExportService {
  static const List<AppExcelColumn> _columns = [
    AppExcelColumn('Contrato', width: 14, type: AppExcelColumnType.number),
    AppExcelColumn('Cliente', width: 40),
    AppExcelColumn('Região', width: 28),
    AppExcelColumn('Tipo', width: 22),
    AppExcelColumn('Status', width: 22),
    AppExcelColumn('Vencimento', width: 18),
    AppExcelColumn(
      'Parcelas vencidas',
      width: 19,
      type: AppExcelColumnType.number,
    ),
    AppExcelColumn('Valor', width: 20, type: AppExcelColumnType.currency),
  ];

  Future<AppTableExcelFile> create(List<AppChatLoan> loans) {
    final bool overdue = loans.any((loan) => loan.status == 'ATRASADO');
    return TableExcelExportService().create(
      items: loans,
      columns: _columns,
      rowBuilder: (loan) => [
        loan.loanId,
        loan.clientName,
        loan.regionName,
        loan.paymentType,
        overdue ? 'Atrasado' : 'Vencendo hoje',
        _date(loan.dueDate),
        loan.installmentCount,
        loan.amount,
      ],
      sheetName: overdue ? 'Empréstimos atrasados' : 'Vencimentos de hoje',
      filePrefix: overdue ? 'emprestimosAtrasados' : 'vencimentosDeHoje',
      itemLabel: 'empréstimo(s)',
    );
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
}
