import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('tabela desktop recebe largura finita e exibe paginação', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final ScrollController verticalController = ScrollController();
    final ScrollController horizontalController = ScrollController();
    addTearDown(verticalController.dispose);
    addTearDown(horizontalController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1164,
              height: 657,
              child: DesktopPaginatedDataTable(
                columns: const [
                  DataColumn(
                    label: SizedBox(width: 225, child: Text('CLIENTE')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 135, child: Text('CPF/CNPJ')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 245, child: Text('REGIÃO')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 125, child: Text('TELEFONE')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 90, child: Text('SITUAÇÃO')),
                  ),
                  DataColumn(label: SizedBox(width: 24)),
                ],
                rows: List<DataRow>.generate(
                  50,
                  (int index) => DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 225,
                          child: Text('Cliente ${index + 1}'),
                        ),
                      ),
                      const DataCell(SizedBox(width: 135, child: Text('—'))),
                      const DataCell(
                        SizedBox(width: 245, child: Text('Região Central')),
                      ),
                      const DataCell(SizedBox(width: 125, child: Text('—'))),
                      const DataCell(SizedBox(width: 90, child: Text('Ativo'))),
                      const DataCell(SizedBox(width: 24)),
                    ],
                  ),
                ),
                totalItems: 124,
                currentPage: 0,
                rowsPerPage: 50,
                onPageChanged: (_) {},
                verticalController: verticalController,
                horizontalController: horizontalController,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('CLIENTE'), findsWidgets);
    expect(find.text('1–50 de 124'), findsOneWidget);
    expect(find.text('50 por página'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
