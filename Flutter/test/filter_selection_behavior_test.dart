import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  const List<AppRegionOption> regions = [
    AppRegionOption(id: 1, name: 'Região A'),
    AppRegionOption(id: 2, name: 'Região B'),
    AppRegionOption(id: 3, name: 'Região C'),
  ];

  Future<void> setMobileViewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget testHost(Future<void> Function(BuildContext) onOpen) => MaterialApp(
    theme: lightThemeData,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => onOpen(context),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );

  testWidgets('filtro de empréstimos representa ausência de restrição', (
    tester,
  ) async {
    await setMobileViewport(tester);
    AppLoanFilters? result;
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showLoanFilterPanel(
                    context: hostContext,
                    initial: const AppLoanFilters(),
                    regions: regions,
                  );
                },
                child: const Text('Abrir'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Filtros de empréstimos'), findsOneWidget);
    final Finder statusBoxes = find.byType(CheckboxListTile);
    expect(statusBoxes, findsNWidgets(appLoanStatuses.length));
    expect(
      tester
          .widgetList<CheckboxListTile>(statusBoxes)
          .every((tile) => tile.value == false),
      isTrue,
    );
    final Container overdueColor = tester.widget<Container>(
      find.byKey(const ValueKey('loan_status_color_Em atraso')),
    );
    final Container paidColor = tester.widget<Container>(
      find.byKey(const ValueKey('loan_status_color_Quitado')),
    );
    expect(
      (overdueColor.decoration! as BoxDecoration).color,
      const Color(0xFFF57575),
    );
    expect(
      (paidColor.decoration! as BoxDecoration).color,
      const Color(0xFFB46FE2),
    );

    await tester.tap(statusBoxes.first);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(statusBoxes.first).value, isTrue);
    await tester.tap(find.text('APLICAR'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.regionIds, isEmpty);
    expect(result!.statuses, <String>{appLoanStatuses.first});
  });

  testWidgets('filtro de regiões representa ausência de restrição como todas', (
    tester,
  ) async {
    await setMobileViewport(tester);
    AppRegionFilters? result;
    await tester.pumpWidget(
      testHost((context) async {
        result = await showRegionFilterDrawer(
          context: context,
          initial: const AppRegionFilters(startDate: null, endDate: null),
          options: regions,
        );
      }),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Todas as regiões'), findsOneWidget);
    await tester.tap(find.text('Todas as regiões'));
    await tester.pumpAndSettle();

    final Finder boxes = find.byType(CheckboxListTile);
    expect(boxes, findsNWidgets(regions.length));
    expect(
      tester
          .widgetList<CheckboxListTile>(boxes)
          .every((tile) => tile.value == false),
      isTrue,
    );

    await tester.tap(find.text('APLICAR').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('APLICAR'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.regionIds, isEmpty);
  });
}
