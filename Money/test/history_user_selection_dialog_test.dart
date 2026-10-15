import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('filtro do histórico permite selecionar vários usuários', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Set<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showHistoryUserSelectionDialog(
                  context: context,
                  users: const ['admin', 'beatriz', 'daniel'],
                  selected: const {},
                );
              },
              child: const Text('Abrir usuários'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir usuários'));
    await tester.pumpAndSettle();

    final Finder boxes = find.byType(CheckboxListTile);
    expect(boxes, findsNWidgets(3));
    expect(
      tester
          .widgetList<CheckboxListTile>(boxes)
          .every((tile) => tile.value == false),
      isTrue,
    );

    await tester.tap(find.text('admin'));
    await tester.tap(find.text('daniel'));
    await tester.pump();

    expect(find.text('2 usuário(s) marcado(s)'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('APLICAR'));
    await tester.pumpAndSettle();

    expect(result, {'admin', 'daniel'});
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
