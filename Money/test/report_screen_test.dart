import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('página de relatórios exibe os dois cards no mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app(const ReportScreen()));
    await tester.pump();

    expect(find.text('Relatórios'), findsOneWidget);
    expect(
      find.text(
        'Consulte atividades da operação e gere arquivos completos em Excel.',
      ),
      findsNothing,
    );
    expect(find.text('Histórico de alterações'), findsOneWidget);
    expect(find.text('Exportar relatório geral'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image == const AssetImage(AppImages.excel),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('página de relatórios mantém os cards lado a lado no desktop', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_app(const ReportScreen(showAppBar: false)));
    await tester.pump();

    expect(find.text('Relatórios'), findsOneWidget);
    expect(
      find.text(
        'Consulte atividades da operação e gere arquivos completos em Excel.',
      ),
      findsOneWidget,
    );
    final Rect history = tester.getRect(find.text('Histórico de alterações'));
    final Rect general = tester.getRect(find.text('Exportar relatório geral'));
    expect((history.top - general.top).abs(), lessThan(2));
    expect(general.left, greaterThan(history.right));
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget home) => MaterialApp(
  theme: lightThemeData,
  locale: const Locale('pt'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppStrings.supportedLocales,
  home: home,
);
