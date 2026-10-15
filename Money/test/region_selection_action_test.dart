import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  const List<AppRegionOption> regions = [
    AppRegionOption(id: 1, name: 'ALPHACRED - DANIEL'),
    AppRegionOption(id: 2, name: 'APEX FINANCE - BEATRIZ'),
  ];

  testWidgets('seletor compartilhado usa botões iguais e texto sem quebra', (
    tester,
  ) async {
    await _openHost(
      tester,
      (context) => showRegionSelectionDialog(
        context: context,
        options: regions,
        selected: const {},
      ),
    );

    _expectEqualActions(tester);
  });

  testWidgets('seletor de empréstimos usa botões iguais e texto sem quebra', (
    tester,
  ) async {
    await _openHost(
      tester,
      (context) => showLoanFilterPanel(
        context: context,
        initial: const AppLoanFilters(),
        regions: regions,
      ),
    );

    await tester.tap(find.text('Todas as regiões'));
    await tester.pumpAndSettle();
    expect(find.text('Selecionar regiões'), findsOneWidget);
    _expectEqualActions(tester);
  });
}

Future<void> _openHost(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) open,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => open(context),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void _expectEqualActions(WidgetTester tester) {
  final Finder dialog = find.byType(Dialog);
  final Finder cancel = find.descendant(
    of: dialog,
    matching: find.widgetWithText(OutlinedButton, 'CANCELAR'),
  );
  final Finder apply = find.descendant(
    of: dialog,
    matching: find.widgetWithText(FilledButton, 'APLICAR'),
  );
  expect(cancel, findsOneWidget);
  expect(apply, findsOneWidget);
  expect(tester.getSize(cancel).width, tester.getSize(apply).width);
  expect(
    tester
        .widget<Text>(
          find.descendant(of: cancel, matching: find.text('CANCELAR')),
        )
        .maxLines,
    1,
  );
  expect(
    tester
        .widget<Text>(
          find.descendant(of: apply, matching: find.text('APLICAR')),
        )
        .maxLines,
    1,
  );
  expect(tester.takeException(), isNull);
}
