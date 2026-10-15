import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  Future<void> pumpIdentification(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: const LoanDetailScreen.newLoan(
          clientId: 1,
          clientName: 'Cliente teste',
          regionId: 1,
          regionName: 'Região teste',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('identificação distribui os campos em duas colunas no mobile', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpIdentification(tester, const Size(390, 844));

    final Rect contractDate = tester.getRect(find.text('Data do empréstimo'));
    final Rect firstDueDate = tester.getRect(
      find.text('Data do primeiro pagamento'),
    );
    expect(firstDueDate.top, closeTo(contractDate.top, 1));
    expect(firstDueDate.left, greaterThan(contractDate.right));
    expect(find.text('Valor Juros'), findsOneWidget);
    expect(find.text('Valor do Negociado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identificação distribui os campos no desktop', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpIdentification(tester, const Size(980, 760));

    final Rect contractDate = tester.getRect(find.text('Data do empréstimo'));
    final Rect firstDueDate = tester.getRect(
      find.text('Data do primeiro pagamento'),
    );
    expect(firstDueDate.top, closeTo(contractDate.top, 1));
    expect(firstDueDate.left, greaterThan(contractDate.right));
    expect(find.text('Valor Juros'), findsOneWidget);
    expect(find.text('Valor do Negociado'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
