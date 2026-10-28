import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('perfil é somente leitura e possui duas abas', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(499, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final AppUserDetail profile = AppUserDetail(
      id: 3,
      firstName: 'Matheus',
      lastName: 'Silva',
      name: 'Matheus Silva',
      username: 'MATHEUS',
      email: 'matheus@example.com',
      enabled: true,
      locked: false,
      expired: false,
      credentialsExpired: false,
      forcePasswordChange: false,
      administrator: true,
      canEdit: true,
      lastAccess: DateTime(2026, 8, 10, 10, 30),
      regions: const [
        AppUserRegion(id: 1, name: 'Região Central', assigned: true),
        AppUserRegion(id: 32, name: '', assigned: true),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        locale: const Locale('pt'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: ProfileScreen(initialProfile: profile),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Informações'), findsOneWidget);
    expect(find.text('Regiões'), findsOneWidget);
    expect(find.text('Matheus Silva'), findsWidgets);
    expect(find.text('Alterar senha'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Alterar senha'));
    await tester.pumpAndSettle();
    expect(find.text('Nova senha numérica'), findsOneWidget);
    expect(find.text('Confirmar nova senha'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Regiões'));
    await tester.pumpAndSettle();

    expect(find.text('Região Central'), findsOneWidget);
    expect(find.text('Região #32'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
