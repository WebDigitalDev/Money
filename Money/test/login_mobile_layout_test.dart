import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Money',
      packageName: 'com.webdigital.money',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('ícones do login preenchem o campo e versão some com teclado', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: LoginScreen(onAuthenticated: () async {}),
      ),
    );
    await tester.pump();

    expect(find.text('Versão 1.0.0'), findsOneWidget);
    final Rect usernameBeforeKeyboard = tester.getRect(
      find.byKey(const ValueKey('login_username_field')),
    );
    for (final String field in const ['username', 'password']) {
      final Finder outer = find.byKey(ValueKey('login_${field}_field'));
      final Finder iconBackground = find.byKey(
        ValueKey('login_${field}_icon_background'),
      );
      expect(outer, findsOneWidget);
      expect(iconBackground, findsOneWidget);
      expect(tester.widget<Container>(outer).clipBehavior, Clip.antiAlias);
      final Rect outerRect = tester.getRect(outer);
      final Rect iconRect = tester.getRect(iconBackground);
      expect(iconRect.left - outerRect.left, closeTo(1, .1));
      expect(iconRect.top - outerRect.top, closeTo(1, .1));
      expect(outerRect.bottom - iconRect.bottom, closeTo(1, .1));
    }

    await tester.tap(find.byType(TextField).last);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.text('Versão 1.0.0'), findsNothing);
    final Rect usernameWithKeyboard = tester.getRect(
      find.byKey(const ValueKey('login_username_field')),
    );
    final Rect passwordWithKeyboard = tester.getRect(
      find.byKey(const ValueKey('login_password_field')),
    );
    final Rect enterWithKeyboard = tester.getRect(
      find.widgetWithText(FilledButton, 'ENTRAR'),
    );
    const double keyboardTop = 844 - 300;
    expect(usernameWithKeyboard.top, lessThan(usernameBeforeKeyboard.top));
    expect(passwordWithKeyboard.bottom, lessThanOrEqualTo(keyboardTop));
    expect(enterWithKeyboard.bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump();
    expect(find.text('Versão 1.0.0'), findsOneWidget);
  });
}
