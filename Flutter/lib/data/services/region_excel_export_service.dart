import 'dart:typed_data';

import 'package:money/data/models/app_region.dart';
import 'package:money/data/services/table_excel_export_service.dart';

typedef RegionExcelProgressCallback =
    void Function(double progress, String status);

final class AppRegionExcelFile {
  final Uint8List bytes;
  final String fileName;

  const AppRegionExcelFile({required this.bytes, required this.fileName});
}

final class RegionExcelExportService {
  static const List<AppExcelColumn> _columns = [
    AppExcelColumn('ID', width: 12, type: AppExcelColumnType.number),
    AppExcelColumn('Descrição', width: 42),
    AppExcelColumn('Ativos', width: 14, type: AppExcelColumnType.number),
    AppExcelColumn('Em dia', width: 14, type: AppExcelColumnType.number),
    AppExcelColumn('Inadimplentes', width: 17, type: AppExcelColumnType.number),
    AppExcelColumn('Desaparecidos', width: 17, type: AppExcelColumnType.number),
    AppExcelColumn(
      'Valor a receber',
      width: 21,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor vencidos',
      width: 21,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor desaparecido',
      width: 22,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor a receber hoje',
      width: 24,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor recebido hoje',
      width: 24,
      type: AppExcelColumnType.currency,
    ),
    AppExcelColumn(
      'Valor do lucro',
      width: 21,
      type: AppExcelColumnType.currency,
    ),
  ];

  Future<AppRegionExcelFile> create(
    List<AppRegionSummary> regions, {
    RegionExcelProgressCallback? onProgress,
  }) async {
    final AppTableExcelFile file = await TableExcelExportService().create(
      items: regions,
      columns: _columns,
      rowBuilder: (region) => [
        region.id,
        region.displayName,
        region.activeClients,
        region.currentClients,
        region.overdueClients,
        region.missingClients,
        region.receivableAmount,
        region.overdueAmount,
        region.missingAmount,
        region.dueTodayAmount,
        region.receivedAmount,
        region.profitAmount,
      ],
      sheetName: 'Regiões',
      filePrefix: 'regioesResumidas',
      itemLabel: 'região(ões)',
      onProgress: onProgress,
    );
    return AppRegionExcelFile(bytes: file.bytes, fileName: file.fileName);
  }
}
