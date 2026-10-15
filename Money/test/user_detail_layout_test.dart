import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('perfil do usuário ocupa corretamente a área mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(499, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final AppUserDetail user = AppUserDetail(
      id: 1,
      firstName: 'Administrador',
      lastName: '',
      name: 'Administrador',
      username: 'ADMINISTRADOR',
      email: '',
      enabled: true,
      locked: false,
      expired: false,
      credentialsExpired: false,
      forcePasswordChange: false,
      administrator: true,
      canEdit: true,
      lastAccess: DateTime(2026, 8, 10, 9, 36),
      regions: const [
        AppUserRegion(id: 1, name: 'Região Central', assigned: true),
        AppUserRegion(id: 2, name: 'Região Norte', assigned: false),
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
        home: Scaffold(
          body: UserDetailScreen(
            initialUser: user,
            showAppBar: false,
            embedded: true,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Administrador'), findsWidgets);
    expect(find.text('Identificação'), findsOneWidget);
    expect(find.text('Regiões'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Primeiro nome'), findsOneWidget);
    expect(find.text('Salvar alterações'), findsNothing);
    expect(find.text('VOLTAR'), findsOneWidget);
    final double backButtonY = tester.getRect(find.text('VOLTAR')).center.dy;
    expect(
      backButtonY,
      greaterThan(830),
      reason: 'O botão VOLTAR deve permanecer no rodapé do conteúdo.',
    );

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    final double activeY = tester.getCenter(find.text('Usuário ativo')).dy;
    final double administratorY = tester
        .getCenter(find.text('Administrador').last)
        .dy;
    final double canEditY = tester
        .getCenter(find.text('Permitir edições nas rotinas'))
        .dy;
    final double collectorY = tester.getCenter(find.text('Cobrador')).dy;
    final double forcePasswordY = tester
        .getCenter(find.text('Solicitar troca de senha'))
        .dy;
    expect(activeY, lessThan(administratorY));
    expect(administratorY, lessThan(canEditY));
    expect(canEditY, lessThan(collectorY));
    expect(collectorY, lessThan(forcePasswordY));
    expect(tester.takeException(), isNull);
  });
}
