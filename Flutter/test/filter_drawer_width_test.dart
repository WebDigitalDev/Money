import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('drawer de filtro ocupa 70% da largura no mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showAppSideDrawer<void>(
                context: context,
                maxWidth:
                    MediaQuery.sizeOf(context).width *
                    appMobileFilterDrawerWidthFactor,
                barrierDismissible: true,
                builder: (_) => const SizedBox.expand(
                  key: ValueKey('mobile_filter_drawer'),
                ),
              ),
              child: const Text('Abrir filtro'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir filtro'));
    await tester.pumpAndSettle();

    expect(appMobileFilterDrawerWidthFactor, .70);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_filter_drawer'))).width,
      301,
    );
    await tester.tapAt(const Offset(12, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_filter_drawer')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
