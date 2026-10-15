import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets(
    'conferências troca a aba somente após a animação, como clientes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 820);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final List<AppConferenceCategory> requests = [];
      final AppConferenceListData response = AppConferenceListData(
        items: const [],
        total: 0,
        counts: const {'PAYMENT': 3, 'LOAN': 2, 'NEGOTIATION': 1, 'CLOSURE': 4},
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          home: ConferencesScreen(
            showAppBar: false,
            administrator: true,
            fetchRegions: () async => const [],
            fetch:
                ({
                  required category,
                  required query,
                  required regionIds,
                }) async {
                  requests.add(category);
                  return response;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(requests, [AppConferenceCategory.payment]);
      expect(find.byType(TabBarView), findsNothing);
      expect(find.text('Tudo conferido'), findsOneWidget);

      await tester.tap(find.text('Empréstimos (2)'));
      await tester.pump(const Duration(milliseconds: 120));

      expect(requests, [AppConferenceCategory.payment]);
      expect(find.text('Tudo conferido'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(requests, [
        AppConferenceCategory.payment,
        AppConferenceCategory.loan,
      ]);
      expect(find.text('Tudo conferido'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(TabBar), const Offset(220, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagamentos (3)'));
      await tester.pumpAndSettle();

      expect(requests, [
        AppConferenceCategory.payment,
        AppConferenceCategory.loan,
        AppConferenceCategory.payment,
      ]);
    },
  );
}
