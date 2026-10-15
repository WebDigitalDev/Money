import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('drawer abre à direita sem remover o conteúdo anterior', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('Modal do empréstimo aberta'),
                FilledButton(
                  onPressed: () => showAppSideDrawer<void>(
                    context: context,
                    builder: (_) => const SizedBox.expand(
                      key: ValueKey('drawer-content'),
                      child: Center(child: Text('Editando parcela')),
                    ),
                  ),
                  child: const Text('Abrir parcela'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir parcela'));
    await tester.pumpAndSettle();

    expect(find.text('Modal do empréstimo aberta'), findsOneWidget);
    expect(find.text('Editando parcela'), findsOneWidget);
    final Rect drawer = tester.getRect(
      find.byKey(const ValueKey('drawer-content')),
    );
    expect(drawer.right, closeTo(1440, 1));
    expect(drawer.width, inInclusiveRange(480, 560));
    expect(tester.takeException(), isNull);
  });
}
