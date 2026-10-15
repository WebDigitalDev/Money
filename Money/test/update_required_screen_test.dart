import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  testWidgets('shows mandatory update layout and update action', (
    WidgetTester tester,
  ) async {
    const RequiredAppUpdate update = RequiredAppUpdate(
      target: AppUpdateTarget.web,
      minimumBuild: 0,
      latestBuild: 0,
      version: '1.1.0',
      downloadUrl: '',
      installUrl: '',
      size: 0,
      sha256: '',
      releaseId: '2026.08.22.2',
    );

    await tester.pumpWidget(
      const MaterialApp(home: UpdateRequiredScreen(update: update)),
    );

    expect(find.text('ATUALIZAR'), findsOneWidget);
    expect(find.text('Versão 1.1.0 disponível'), findsOneWidget);
    expect(find.byType(PopScope<void>), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == AppImages.update,
      ),
      findsOneWidget,
    );
  });
}
