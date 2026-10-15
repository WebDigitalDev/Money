import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('exportação mobile usa dialog menor e apenas compartilhar', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _openCompletedExport(tester);

    expect(tester.getSize(find.byType(AppDialogPanel)).height, 300);
    expect(find.text('COMPARTILHAR'), findsOneWidget);
    expect(find.text('DOWNLOAD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exportação desktop exibe apenas download', (tester) async {
    await _setViewport(tester, const Size(1440, 900));
    await _openCompletedExport(tester);

    expect(tester.getSize(find.byType(AppDialogPanel)).height, 360);
    expect(find.text('DOWNLOAD'), findsOneWidget);
    expect(find.text('COMPARTILHAR'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _openCompletedExport(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showAppExcelExportFlow(
              context: context,
              title: 'Exportar relatório',
              confirmationMessage: 'Deseja gerar o arquivo?',
              generate: (onProgress) async {
                onProgress(.75, 'Gerando...');
                return AppGeneratedExcelFile(
                  bytes: Uint8List.fromList([1, 2, 3]),
                  fileName: 'relatorio.xlsx',
                  successMessage: 'Arquivo pronto.',
                );
              },
            ),
            child: const Text('Iniciar exportação'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Iniciar exportação'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Exportar'));
  await tester.pumpAndSettle();
}
