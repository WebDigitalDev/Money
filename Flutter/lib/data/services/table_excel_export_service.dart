import 'dart:typed_data';

import 'package:archive/archive.dart';

typedef TableExcelProgressCallback =
    void Function(double progress, String status);

enum AppExcelColumnType { text, number, currency }

final class AppExcelColumn {
  final String label;
  final double width;
  final AppExcelColumnType type;

  const AppExcelColumn(
    this.label, {
    this.width = 20,
    this.type = AppExcelColumnType.text,
  });
}

final class AppExcelSheet {
  final String name;
  final List<AppExcelColumn> columns;
  final List<List<Object?>> rows;
  final String itemLabel;

  const AppExcelSheet({
    required this.name,
    required this.columns,
    required this.rows,
    this.itemLabel = 'registro(s)',
  });
}

final class AppTableExcelFile {
  final Uint8List bytes;
  final String fileName;

  const AppTableExcelFile({required this.bytes, required this.fileName});
}

final class TableExcelExportService {
  Future<AppTableExcelFile> create<T>({
    required List<T> items,
    required List<AppExcelColumn> columns,
    required List<Object?> Function(T item) rowBuilder,
    required String sheetName,
    required String filePrefix,
    String itemLabel = 'registro(s)',
    TableExcelProgressCallback? onProgress,
  }) => createWorkbook(
    sheets: [
      AppExcelSheet(
        name: sheetName,
        columns: columns,
        rows: items.map(rowBuilder).toList(growable: false),
        itemLabel: itemLabel,
      ),
    ],
    filePrefix: filePrefix,
    onProgress: onProgress,
  );

  Future<AppTableExcelFile> createWorkbook({
    required List<AppExcelSheet> sheets,
    required String filePrefix,
    TableExcelProgressCallback? onProgress,
  }) async {
    if (sheets.isEmpty) {
      throw ArgumentError.value(sheets, 'sheets', 'Informe as planilhas.');
    }
    for (final AppExcelSheet sheet in sheets) {
      if (sheet.columns.isEmpty) {
        throw ArgumentError.value(
          sheet.columns,
          'columns',
          'Informe as colunas de ${sheet.name}.',
        );
      }
    }

    onProgress?.call(0, 'Preparando a planilha...');
    final int totalRows = sheets.fold<int>(
      0,
      (total, sheet) => total + sheet.rows.length,
    );
    int completedRows = 0;
    final List<String> worksheets = [];

    for (final AppExcelSheet sheet in sheets) {
      worksheets.add(
        await _buildWorksheet(
          sheet,
          completedRows: completedRows,
          totalRows: totalRows,
          onProgress: onProgress,
        ),
      );
      completedRows += sheet.rows.length;
    }

    onProgress?.call(.88, 'Finalizando o arquivo Excel...');
    await Future<void>.delayed(Duration.zero);
    final Archive archive = Archive()
      ..add(
        ArchiveFile.string('[Content_Types].xml', _contentTypes(sheets.length)),
      )
      ..add(ArchiveFile.string('_rels/.rels', _rootRelationships))
      ..add(ArchiveFile.string('docProps/app.xml', _appProperties))
      ..add(ArchiveFile.string('docProps/core.xml', _coreProperties()))
      ..add(
        ArchiveFile.string(
          'xl/workbook.xml',
          _workbook(sheets.map((sheet) => sheet.name).toList()),
        ),
      )
      ..add(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          _workbookRelationships(sheets.length),
        ),
      )
      ..add(ArchiveFile.string('xl/styles.xml', _styles));

    for (int index = 0; index < worksheets.length; index++) {
      archive.add(
        ArchiveFile.string(
          'xl/worksheets/sheet${index + 1}.xml',
          worksheets[index],
        ),
      );
    }

    onProgress?.call(.94, 'Compactando o arquivo Excel...');
    await Future<void>.delayed(Duration.zero);
    final Uint8List bytes = ZipEncoder().encodeBytes(archive);
    onProgress?.call(1, 'Arquivo Excel gerado com sucesso.');
    return AppTableExcelFile(
      bytes: bytes,
      fileName: '${filePrefix}_${_timestamp()}.xlsx',
    );
  }

  Future<String> _buildWorksheet(
    AppExcelSheet sheet, {
    required int completedRows,
    required int totalRows,
    TableExcelProgressCallback? onProgress,
  }) async {
    final StringBuffer rows = StringBuffer();
    rows.write('<row r="1" ht="24" customHeight="1">');
    for (int column = 0; column < sheet.columns.length; column++) {
      rows.write(
        _textCell(_cellReference(column, 1), sheet.columns[column].label, 1),
      );
    }
    rows.write('</row>');

    for (int index = 0; index < sheet.rows.length; index++) {
      final List<Object?> values = sheet.rows[index];
      if (values.length != sheet.columns.length) {
        throw StateError(
          'A linha ${index + 1} de ${sheet.name} possui ${values.length} '
          'valores para ${sheet.columns.length} colunas.',
        );
      }
      final int row = index + 2;
      rows.write('<row r="$row">');
      for (int column = 0; column < sheet.columns.length; column++) {
        final String reference = _cellReference(column, row);
        final Object? value = values[column];
        switch (sheet.columns[column].type) {
          case AppExcelColumnType.text:
            rows.write(_textCell(reference, value?.toString() ?? '', 2));
          case AppExcelColumnType.number:
            rows.write(_numberOrEmptyCell(reference, value, 2));
          case AppExcelColumnType.currency:
            rows.write(_numberOrEmptyCell(reference, value, 3));
        }
      }
      rows.write('</row>');

      if ((index + 1) % 250 == 0 || index + 1 == sheet.rows.length) {
        final int processed = completedRows + index + 1;
        final double progress = totalRows == 0
            ? .82
            : (processed / totalRows) * .82;
        onProgress?.call(
          progress,
          'Montando ${sheet.name} (${index + 1} de ${sheet.rows.length} ${sheet.itemLabel})...',
        );
        await Future<void>.delayed(Duration.zero);
      }
    }

    final int lastRow = sheet.rows.length + 1;
    final String lastColumn = _columnName(sheet.columns.length - 1);
    final StringBuffer widths = StringBuffer();
    for (int index = 0; index < sheet.columns.length; index++) {
      final int position = index + 1;
      widths.write(
        '<col min="$position" max="$position" width="${sheet.columns[index].width}" customWidth="1"/>',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<dimension ref="A1:$lastColumn$lastRow"/>'
        '<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>'
        '<sheetFormatPr defaultRowHeight="18"/>'
        '<cols>$widths</cols>'
        '<sheetData>$rows</sheetData>'
        '<autoFilter ref="A1:$lastColumn$lastRow"/>'
        '</worksheet>';
  }

  String _textCell(String reference, String value, int style) =>
      '<c r="$reference" s="$style" t="inlineStr"><is><t xml:space="preserve">'
      '${_xml(value)}</t></is></c>';

  String _numberOrEmptyCell(String reference, Object? value, int style) {
    final num? number = value is num ? value : num.tryParse('$value');
    if (number == null || !number.isFinite) {
      return _textCell(reference, '', style == 3 ? 2 : style);
    }
    return '<c r="$reference" s="$style"><v>$number</v></c>';
  }

  String _cellReference(int column, int row) => '${_columnName(column)}$row';

  String _columnName(int column) {
    int value = column + 1;
    final StringBuffer result = StringBuffer();
    while (value > 0) {
      final int remainder = (value - 1) % 26;
      result.writeCharCode(65 + remainder);
      value = (value - 1) ~/ 26;
    }
    return result.toString().split('').reversed.join();
  }

  String _timestamp() {
    final DateTime now = DateTime.now();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  String _xml(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String _coreProperties() {
    final String timestamp = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties '
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>Money</dc:creator><cp:lastModifiedBy>Money</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$timestamp</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$timestamp</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _workbook(List<String> sheetNames) {
    final String sheets = [
      for (int index = 0; index < sheetNames.length; index++)
        '<sheet name="${_xml(sheetNames[index])}" sheetId="${index + 1}" r:id="rId${index + 1}"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$sheets</sheets></workbook>';
  }

  String _contentTypes(int sheetCount) {
    final String sheetTypes = [
      for (int index = 1; index <= sheetCount; index++)
        '<Override PartName="/xl/worksheets/sheet$index.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '$sheetTypes'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>';
  }

  String _workbookRelationships(int sheetCount) {
    final String worksheets = [
      for (int index = 1; index <= sheetCount; index++)
        '<Relationship Id="rId$index" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$index.xml"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '$worksheets'
        '<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>';
  }

  static const String _rootRelationships =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';

  static const String _appProperties =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
      '<Application>Money</Application><AppVersion>1.0</AppVersion>'
      '</Properties>';

  static const String _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="R\$ #,##0.00"/></numFmts>'
      '<fonts count="2">'
      '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
      '</fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF76B475"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left style="thin"><color rgb="FFDADADA"/></left>'
      '<right style="thin"><color rgb="FFDADADA"/></right>'
      '<top style="thin"><color rgb="FFDADADA"/></top>'
      '<bottom style="thin"><color rgb="FFDADADA"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="4">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}
