import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  for (final double width in [360, 499]) {
    testWidgets('card de score cabe no cliente com largura ${width.toInt()}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: ClientScoreCard(
                score: AppClientScore(
                  points: 55,
                  overdueDays: 37,
                  totalDebt: 1234.56,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Score do cliente'), findsOneWidget);
      expect(find.byKey(const ValueKey('client-score-points')), findsOneWidget);
      expect(find.text('55 pontos'), findsOneWidget);
      expect(find.text('37 dias'), findsOneWidget);
      final Text debt = tester.widget<Text>(
        find.byKey(const ValueKey('client-score-metric-Dívida total atual')),
      );
      expect(debt.data?.replaceAll(RegExp(r'\s'), ''), r'R$1.234,56');
      expect(tester.takeException(), isNull);
    });
  }
}
