import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('painel do empréstimo usa modal compacta no desktop web', (
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
            body: Center(
              child: FilledButton(
                onPressed: () => showAppBottomSheet<void>(
                  context: context,
                  title: 'Parcela',
                  subtitle: 'Dados financeiros',
                  icon: Icons.payments_outlined,
                  desktopDialog: true,
                  builder: (_) => const SizedBox.expand(),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Parcela'), findsOneWidget);
    expect(find.byType(AppBottomSheet), findsOneWidget);
  }, skip: !kIsWeb);
}
