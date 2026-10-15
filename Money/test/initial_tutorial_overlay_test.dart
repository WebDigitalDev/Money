import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  Future<void> setViewport(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Widget buildApp() {
    bool tutorialVisible = true;
    return MaterialApp(
      theme: lightThemeData,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: false),
        child: child!,
      ),
      home: StatefulBuilder(
        builder: (context, setState) {
          return Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                FilledButton(
                  onPressed: () {},
                  child: const Text('AÇÃO DA HOME'),
                ),
                if (tutorialVisible)
                  InitialTutorialOverlay(
                    playAudio: false,
                    onStart: () => setState(() => tutorialVisible = false),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  testWidgets('tutorial mobile mostra roteiro e bloqueia a Home', (
    tester,
  ) async {
    await setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Money'), findsOneWidget);
    expect(find.text('COMEÇAR'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InitialTutorialOverlay),
        matching: find.byType(ModalBarrier),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image == const AssetImage(AppImages.virtualAssistant),
      ),
      findsOneWidget,
    );
    final Rect image = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image == const AssetImage(AppImages.virtualAssistant),
      ),
    );
    final Rect panel = tester.getRect(
      find.byKey(const ValueKey('tutorial_dialogue_panel')),
    );
    expect(panel.height, 238);
    expect(image.center.dx, greaterThan(195));
    expect(image.bottom, greaterThan(panel.top));
    expect(find.text('AÇÃO DA HOME').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('botão começar fecha a demonstração', (tester) async {
    await setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.byKey(const ValueKey('tutorial_start_button')));
    await tester.pump();

    expect(find.byType(InitialTutorialOverlay), findsNothing);
    expect(find.text('AÇÃO DA HOME').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repetir fala oculta os controles até o próximo término', (
    tester,
  ) async {
    await setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 800));

    final Finder replayButton = find.byKey(
      const ValueKey('tutorial_audio_button'),
    );
    expect(replayButton, findsOneWidget);
    expect(
      find.descendant(of: replayButton, matching: find.byType(CustomPaint)),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: replayButton,
        matching: find.byIcon(Icons.volume_up_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(replayButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('tutorial_audio_button')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('tutorial_start_button')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('tutorial_completed_controls_hidden')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('personagem e painel possuem surgimento animado', (tester) async {
    await setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(buildApp());

    final Opacity initialPanel = tester.widget(
      find.byKey(const ValueKey('tutorial_panel_entrance')),
    );
    final Opacity initialCharacter = tester.widget(
      find.byKey(const ValueKey('tutorial_character_entrance')),
    );
    expect(initialPanel.opacity, 0);
    expect(initialCharacter.opacity, 0);

    await tester.pump(const Duration(milliseconds: 3900));

    final Opacity delayedPanel = tester.widget(
      find.byKey(const ValueKey('tutorial_panel_entrance')),
    );
    final Opacity delayedCharacter = tester.widget(
      find.byKey(const ValueKey('tutorial_character_entrance')),
    );
    expect(delayedPanel.opacity, 0);
    expect(delayedCharacter.opacity, 0);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 800));

    final Opacity visiblePanel = tester.widget(
      find.byKey(const ValueKey('tutorial_panel_entrance')),
    );
    final Opacity visibleCharacter = tester.widget(
      find.byKey(const ValueKey('tutorial_character_entrance')),
    );
    expect(visiblePanel.opacity, 1);
    expect(visibleCharacter.opacity, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tutorial web usa composição ampla de desktop', (tester) async {
    await setViewport(tester, width: 1440, height: 900);
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 800));

    final Rect image = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image == const AssetImage(AppImages.virtualAssistant),
      ),
    );
    final Rect panel = tester.getRect(
      find.byKey(const ValueKey('tutorial_dialogue_panel')),
    );
    final Positioned characterPosition = tester.widget(
      find.byKey(const ValueKey('tutorial_desktop_character_position')),
    );

    expect(image.center.dx, greaterThan(720));
    expect(characterPosition.right, closeTo(80, 0.01));
    expect(panel.width, lessThanOrEqualTo(780));
    expect(panel.height, 216);
    expect(panel.bottom, lessThan(900));
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);

  testWidgets('áudio do tutorial é carregado com segurança na web', (
    tester,
  ) async {
    await setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: InitialTutorialOverlay(onStart: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(const ValueKey('tutorial_audio_button')), findsNothing);
    expect(find.byKey(const ValueKey('tutorial_start_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('tutorial_completed_controls_hidden')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);

  testWidgets(
    'sessão restaurada aguarda ação e mantém apresentação no início',
    (tester) async {
      await setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          home: InitialTutorialOverlay(requireUserAction: true, onStart: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        find.byKey(const ValueKey('tutorial_manual_audio_button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tutorial_start_button')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('tutorial_visible_text')))
            .data,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );

  test('controlador preserva exigência de ação na introdução restaurada', () {
    final TutorialGuideController controller = TutorialGuideController();
    addTearDown(controller.dispose);

    controller.showIntroduction(requireUserAction: true);
    expect(controller.phase, TutorialPhase.introduction);
    expect(controller.introductionRequiresUserAction, isTrue);

    controller.hide();
    expect(controller.phase, TutorialPhase.hidden);
    expect(controller.introductionRequiresUserAction, isFalse);
  });
}
