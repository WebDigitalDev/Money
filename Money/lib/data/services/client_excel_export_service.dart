import 'dart:typed_data';

import 'package:money/data/models/app_client.dart';
import 'package:money/data/services/table_excel_export_service.dart';

typedef ClientExcelProgressCallback =
    void Function(double progress, String status);

final class AppClientExcelFile {
  final Uint8List bytes;
  final String fileName;

  const AppClientExcelFile({required this.bytes, required this.fileName});
}

final class ClientExcelExportService {
  static const List<AppExcelColumn> _columns = [
    AppExcelColumn('ID', width: 12, type: AppExcelColumnType.number),
    AppExcelColumn('Nome', width: 42),
    AppExcelColumn('CPF/CNPJ', width: 22),
    AppExcelColumn('Telefone', width: 22),
    AppExcelColumn('Região', width: 38),
    AppExcelColumn('Situação', width: 20),
  ];

  Future<AppClientExcelFile> create(
    List<AppClientSummary> clients, {
    ClientExcelProgressCallback? onProgress,
  }) async {
    final AppTableExcelFile file = await TableExcelExportService().create(
      items: clients,
      columns: _columns,
      rowBuilder: (client) => [
        client.id,
        client.name,
        client.document ?? '',
        client.primaryPhone ?? '',
        client.regionName,
        _status(client.status),
      ],
      sheetName: 'Clientes',
      filePrefix: 'clientes',
      itemLabel: 'cliente(s)',
      onProgress: onProgress,
    );
    return AppClientExcelFile(bytes: file.bytes, fileName: file.fileName);
  }

  String _status(AppClientStatus status) => switch (status) {
    AppClientStatus.active => 'Ativo',
    AppClientStatus.withoutLoans => 'Sem empréstimos',
    AppClientStatus.missing => 'Desaparecido',
  };
}
