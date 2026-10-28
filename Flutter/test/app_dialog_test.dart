import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets(
    'dialog responsivo usa a mesma apresentação no mobile e desktop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> openDialogAt(Size size) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showAppDialog<void>(
                      context: context,
                      title: 'Cobrança PIX',
                      subtitle: 'Pagamento do contrato completo',
                      icon: Icons.qr_code_2_rounded,
                      builder: (_) => ListView(
                        shrinkWrap: true,
                        children: const [SizedBox(height: 320)],
                      ),
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
      }

      await openDialogAt(const Size(390, 844));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AppDialogPanel), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getSize(find.byType(AppDialogPanel)).width, 350);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      await openDialogAt(const Size(1440, 900));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AppDialogPanel), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getSize(find.byType(AppDialogPanel)).width, 680);
    },
  );

  testWidgets('dialog bloqueado só pode ser fechado após a conclusão', (
    tester,
  ) async {
    final ValueNotifier<bool> canClose = ValueNotifier<bool>(false);
    addTearDown(canClose.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                title: 'Exportar empréstimos',
                subtitle: 'Gerando arquivo Excel',
                icon: Icons.table_view_outlined,
                canCloseListenable: canClose,
                builder: (_) => const SizedBox(height: 160),
              ),
              child: const Text('Exportar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Exportar'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Aguarde a conclusão'), findsOneWidget);
    await tester.tap(find.byTooltip('Aguarde a conclusão'));
    await tester.tapAt(const Offset(4, 4));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    canClose.value = true;
    await tester.pump();
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
