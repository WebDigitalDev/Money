import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('card desktop mantém valores dentro dos 116 pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 318,
              height: 116,
              child: DashboardMetricCard(
                icon: Icons.person_off_outlined,
                label: 'Valor em atraso',
                value: 'R\$ 8.755,98',
                detail: '35 Empréstimos',
                loading: false,
                detailLoads: true,
                accentColor: Colors.red,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('35 Empréstimos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card de métrica adapta o conteúdo sem overflow vertical', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(620, 800);
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
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 85,
              child: DashboardMetricCard(
                icon: Icons.person_off_outlined,
                label: 'Valor em atraso',
                value: 'R\$ 8.755,98',
                detail: '35 Empréstimos',
                loading: false,
                detailLoads: true,
                accentColor: Colors.red,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('35 Empréstimos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
