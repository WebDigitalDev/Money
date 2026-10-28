import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('rota Cupertino abre com animação curta e escala discreta', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showAppCupertinoDialog<void>(
              context: context,
              builder: (dialogContext) => CupertinoAlertDialog(
                title: const Text('Confirmação'),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            child: const Text('Abrir confirmação'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir confirmação'));
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      appCupertinoDialogTransitionDuration,
      const Duration(milliseconds: 180),
    );
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);

    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aquecimento do diálogo sai da árvore após os primeiros frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoDialogRenderingWarmUp(
          child: ColoredBox(color: CupertinoColors.systemBackground),
        ),
      ),
    );

    expect(find.text('Inteligência financeira'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 121));
    expect(find.text('Inteligência financeira'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('campo Cupertino pode ser editado e cancelado sem exceção', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => showAppCupertinoTextInputDialog(
              context: context,
              title: 'Novo registro',
              placeholder: 'Nome',
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'Teste');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
