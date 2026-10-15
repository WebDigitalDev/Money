import 'dart:typed_data';

import 'package:money/data/models/app_loan.dart';
import 'package:money/data/models/app_region.dart';
import 'package:money/data/models/app_report.dart';
import 'package:money/data/services/table_excel_export_service.dart';

typedef ReportExcelProgressCallback =
    void Function(double progress, String status);

final class AppReportExcelFile {
  final Uint8List bytes;
  final String fileName;

  const AppReportExcelFile({required this.bytes, required this.fileName});
}

final class AuditHistoryExcelExportService {
  static const List<AppExcelColumn> _columns = [
    AppExcelColumn('ID', width: 12, type: AppExcelColumnType.number),
    AppExcelColumn('Usuário', width: 20),
    AppExcelColumn('Data e Hora', width: 22),
    AppExcelColumn('Operação', width: 22),
    AppExcelColumn('Descrição', width: 80),
    AppExcelColumn('Valor', width: 18),
    AppExcelColumn('Região', width: 24),
    AppExcelColumn('Entidade', width: 20),
    AppExcelColumn(
      'ID da Entidade',
      width: 16,
      type: AppExcelColumnType.number,
    ),
  ];

  Future<AppReportExcelFile> create(
    List<AppAuditHistoryItem> history, {
    ReportExcelProgressCallback? onProgress,
  }) async {
    final AppTableExcelFile file = await TableExcelExportService().create(
      items: history,
      columns: _columns,
      rowBuilder: (item) => [
        item.id,
        item.username,
        _dateTime(item.timestamp),
        item.operation,
        item.description,
        item.value,
        item.regionDescription ?? '',
        item.entityName,
        item.entityId,
      ],
      sheetName: 'Historico',
      filePrefix: 'historicoAlteracoes',
      itemLabel: 'alteração(ões)',
      onProgress: onProgress,
    );
    return AppReportExcelFile(bytes: file.bytes, fileName: file.fileName);
  }
}

final class GeneralReportExcelExportService {
  static const List<AppExcelColumn> _regionColumns = [
    AppExcelColumn('ID', width: 12, type: AppExcelColumnType.number),
    AppExcelColumn('Região', width: 42),
    AppExcelColumn('Ativos', width: 14, type: AppExcelColumnType.number),
    AppExcelColumn('Em dia', width: 14, type: AppExcelColumnType.number),
    AppExcelColumn('Atrasados', width: 15, type: AppExcelColumnType.number),
    AppExcelColumn('Desaparecidos', width: 17, type: AppExcelColumnType.number),
    AppExcelColumn('Emprestado', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('Recebido', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('A receber', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('Vencidos', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('Lucro', width: 20, type: AppExcelColumnType.currency),
  ];

  static const List<AppExcelColumn> _loanColumns = [
    AppExcelColumn('ID', width: 12, type: AppExcelColumnType.number),
    AppExcelColumn('Cliente', width: 42),
    AppExcelColumn('Tipo', width: 22),
    AppExcelColumn('Status', width: 22),
    AppExcelColumn('Próximo vencimento', width: 22),
    AppExcelColumn('Emprestado', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('Recebido', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('A receber', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('Lucro', width: 20, type: AppExcelColumnType.currency),
    AppExcelColumn('Penhora', width: 28),
  ];

  Future<AppReportExcelFile> create({
    required List<AppRegionSummary> regions,
    required List<AppLoanSummary> loans,
    ReportExcelProgressCallback? onProgress,
  }) async {
    final List<AppLoanSummary> collateralLoans = loans
        .where(_hasCollateral)
        .toList(growable: false);
    final AppTableExcelFile file = await TableExcelExportService()
        .createWorkbook(
          sheets: [
            AppExcelSheet(
              name: 'Regiões',
              columns: _regionColumns,
              rows: regions.map(_regionRow).toList(growable: false),
              itemLabel: 'região(ões)',
            ),
            AppExcelSheet(
              name: 'Empréstimos',
              columns: _loanColumns,
              rows: loans.map(_loanRow).toList(growable: false),
              itemLabel: 'empréstimo(s)',
            ),
            AppExcelSheet(
              name: 'Penhoras',
              columns: _loanColumns,
              rows: collateralLoans.map(_loanRow).toList(growable: false),
              itemLabel: 'penhora(s)',
            ),
          ],
          filePrefix: 'relatorio_geral_moneyapp',
          onProgress: onProgress,
        );
    return AppReportExcelFile(bytes: file.bytes, fileName: file.fileName);
  }

  List<Object?> _regionRow(AppRegionSummary region) => [
    region.id,
    region.displayName,
    region.activeClients,
    region.currentClients,
    region.overdueClients,
    region.missingClients,
    region.loanedAmount,
    region.receivedAmount,
    region.receivableAmount,
    region.overdueAmount,
    region.profitAmount,
  ];

  List<Object?> _loanRow(AppLoanSummary loan) => [
    loan.id,
    loan.clientName,
    loan.paymentType,
    loan.status,
    _date(loan.nextDueDate),
    loan.loanedAmount,
    loan.receivedAmount,
    loan.receivableAmount,
    loan.profitAmount,
    _collateralText(loan),
  ];

  bool _hasCollateral(AppLoanSummary loan) {
    final String color = loan.statusColor.trim().toLowerCase();
    return color == '#40e0d0' || color == '#e393b9';
  }

  String _collateralText(AppLoanSummary loan) {
    final String value = loan.collateral?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return _hasCollateral(loan) ? 'Sim' : 'Não';
  }
}

String _date(DateTime? value) {
  if (value == null) return '';
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _dateTime(DateTime? value) {
  if (value == null) return '';
  return '${_date(value)} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
