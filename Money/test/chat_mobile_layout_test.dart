import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

Future<AppCodexConnection> _connectedCodex() async => const AppCodexConnection(
  enabled: true,
  available: true,
  connected: true,
  connecting: false,
);

void main() {
  test('código ChatGPT preserva o hífen ao copiar', () {
    final AppCodexLoginChallenge challenge = AppCodexLoginChallenge(
      loginId: 'login-1',
      verificationUrl: Uri.parse(
        'https://auth.openai.com/codex/device?source=money',
      ),
      userCode: 'abCD-12345',
    );

    expect(challenge.clipboardCode, 'ABCD-12345');
    expect(challenge.prefilledVerificationUrl.queryParameters, {
      'source': 'money',
      'user_code': 'abCD-12345',
    });
  });

  testWidgets('exige conexão individual antes de liberar o chat', (
    tester,
  ) async {
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
        home: ChatScreen(
          codexStatus: () async => const AppCodexConnection(
            enabled: true,
            available: true,
            connected: false,
            connecting: false,
          ),
          codexConnect: () async => AppCodexLoginChallenge(
            loginId: 'login-1',
            verificationUrl: Uri.parse('https://chatgpt.com/device'),
            userCode: 'ABCD-EFGH',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conecte sua conta ChatGPT'), findsOneWidget);
    expect(find.text('CONECTAR CHATGPT'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('CONECTAR CHATGPT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Conectar ao ChatGPT'), findsOneWidget);
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('mostra uso da conta e troca enviar por interromper', (
    tester,
  ) async {
    final Completer<AppChatResponse> pending = Completer<AppChatResponse>();
    String? interruptedConversation;

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
        home: ChatScreen(
          showAppBar: false,
          compact: true,
          codexStatus: () async => const AppCodexConnection(
            enabled: true,
            available: true,
            connected: true,
            connecting: false,
            usage: AppCodexUsage(usedPercent: 63.5),
          ),
          codexInterrupt: (conversationId) async {
            interruptedConversation = conversationId;
          },
          query: ({
            required message,
            required conversationId,
            required mode,
            clientId,
            regionId,
          }) => pending.future,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Limite disponível'), findsOneWidget);
    expect(find.text('36.5%'), findsOneWidget);
    expect(find.byTooltip('Enviar'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Liste minhas regiões');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    expect(find.byTooltip('Interromper'), findsOneWidget);
    await tester.tap(find.byTooltip('Interromper'));
    await tester.pump();

    expect(interruptedConversation, isNotEmpty);
    expect(find.byTooltip('Enviar'), findsOneWidget);

    pending.complete(
      const AppChatResponse(
        message: 'Esta resposta deve ser ignorada após a interrupção.',
        mode: 'READY',
        suggestions: [],
        clients: [],
        summary: null,
        semanticSearch: false,
      ),
    );
    await tester.pump();
    expect(
      find.text('Esta resposta deve ser ignorada após a interrupção.'),
      findsNothing,
    );
  });

  testWidgets(
    'compositor fica acima da navegação e não exibe atalhos automáticos',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(384, 832);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

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
            extendBody: true,
            resizeToAvoidBottomInset: false,
            body: ChatScreen(codexStatus: _connectedCodex),
            floatingActionButton: const HomeFloatingActionButton(
              key: ValueKey('chat_layout_fab'),
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: HomeBottomNavigationBar(
              activeIndex: 2,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Rect composer = tester.getRect(find.byType(TextField));
      final Rect centralAction = tester.getRect(
        find.byKey(const ValueKey('chat_layout_fab')),
      );
      final double composerToCentralAction =
          centralAction.top - composer.bottom;
      expect(composerToCentralAction, greaterThanOrEqualTo(24));

      expect(find.text('CONSULTAR CLIENTE'), findsNothing);
      expect(find.text('VENCIMENTOS DE HOJE'), findsNothing);
      expect(find.text('EMPRÉSTIMOS ATRASADOS'), findsNothing);
      expect(find.text('RESUMO FINANCEIRO'), findsNothing);

      double previousOpeningBottom = composer.bottom;
      for (final double inset in const [40, 80, 160, 240, 300]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        final Rect composerDuringKeyboardOpen = tester.getRect(
          find.byType(TextField),
        );
        expect(
          composerDuringKeyboardOpen.bottom,
          lessThan(previousOpeningBottom),
        );
        expect(
          composerDuringKeyboardOpen.bottom,
          lessThanOrEqualTo(832 - inset),
        );
        previousOpeningBottom = composerDuringKeyboardOpen.bottom;
      }

      expect(find.text('CONSULTAR CLIENTE'), findsNothing);
      final Rect composerWithKeyboard = tester.getRect(find.byType(TextField));
      const double keyboardTop = 832 - 300;
      expect(composerWithKeyboard.bottom, lessThanOrEqualTo(keyboardTop));
      expect(keyboardTop - composerWithKeyboard.bottom, lessThanOrEqualTo(12));

      double previousBottom = composerWithKeyboard.bottom;
      for (final double inset in const [240, 160, 80]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        final Rect composerDuringKeyboardClose = tester.getRect(
          find.byType(TextField),
        );
        expect(composerDuringKeyboardClose.bottom, greaterThan(previousBottom));
        expect(composerDuringKeyboardClose.bottom, lessThan(composer.bottom));
        expect(
          composerDuringKeyboardClose.bottom,
          lessThanOrEqualTo(832 - inset),
        );
        previousBottom = composerDuringKeyboardClose.bottom;
      }

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      final Rect composerAfterKeyboardClose = tester.getRect(
        find.byType(TextField),
      );
      expect(composerAfterKeyboardClose.bottom, closeTo(composer.bottom, 0.1));
    },
  );

  testWidgets('envio mantém o teclado focado até a resposta financeira', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(384, 832);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    final Completer<AppChatResponse> response = Completer<AppChatResponse>();
    await tester.pumpWidget(
      _ChatTestApp(
        query: ({
          required message,
          required conversationId,
          required mode,
          clientId,
          regionId,
        }) => response.future,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Como está a região?');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    TextField field = tester.widget(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.enabled, isNot(false));
    expect(find.text('Como está a região?'), findsOneWidget);

    response.complete(_chatResponse('Retorno concluído.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    field = tester.widget(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);
    expect(find.text('Retorno concluído.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('balão enviado preserva margem e canto no lado direito', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(384, 832);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      _ChatTestApp(
        query: ({
          required message,
          required conversationId,
          required mode,
          clientId,
          regionId,
        }) async => _chatResponse('Resposta concluída.'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'CAPITALIZE');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    final Finder bubble = find.ancestor(
      of: find.text('CAPITALIZE'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient != null,
      ),
    );
    expect(bubble, findsOneWidget);
    final Container bubbleContainer = tester.widget<Container>(bubble);
    expect(
      bubbleContainer.margin,
      const EdgeInsets.only(bottom: 12, left: 48, right: 4),
    );
    final Finder paintedBubble = find.descendant(
      of: bubble,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).gradient != null,
      ),
    );
    expect(paintedBubble, findsOneWidget);
    expect(tester.getRect(paintedBubble).right, lessThanOrEqualTo(384 - 16));

    final BoxDecoration decoration =
        bubbleContainer.decoration! as BoxDecoration;
    final BorderRadius radius = decoration.borderRadius! as BorderRadius;
    expect(radius.bottomLeft.x, 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'última mensagem acompanha o teclado e posição antiga é preservada',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(384, 832);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      int responseNumber = 0;
      await tester.pumpWidget(
        _ChatTestApp(
          query: ({
            required message,
            required conversationId,
            required mode,
            clientId,
            regionId,
          }) async => _chatResponse('Resposta financeira ${++responseNumber}'),
        ),
      );
      await tester.pumpAndSettle();

      for (int index = 1; index <= 8; index++) {
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Consulta $index');
        await tester.tap(find.byTooltip('Enviar'));
        await tester.pumpAndSettle();
      }

      final ListView messageList = tester.widget(find.byType(ListView).first);
      final ScrollController controller = messageList.controller!;
      expect(controller.position.maxScrollExtent, greaterThan(160));
      expect(
        controller.position.maxScrollExtent - controller.offset,
        lessThanOrEqualTo(16.5),
      );

      await tester.tap(find.byType(TextField));
      for (final double inset in const [60, 140, 220, 300]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        await tester.pump();
      }
      final Rect lastResponse = tester.getRect(
        find.text('Resposta financeira 8'),
      );
      final Rect composer = tester.getRect(find.byType(TextField));
      expect(lastResponse.bottom, lessThanOrEqualTo(composer.top));

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      tester.widget<TextField>(find.byType(TextField)).focusNode!.unfocus();
      await tester.pump();

      final double oldPosition = controller.position.maxScrollExtent - 140;
      controller.jumpTo(oldPosition);
      await tester.pump();
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pump();
      await tester.pump();

      expect(controller.offset, closeTo(oldPosition, .1));
      expect(
        controller.position.maxScrollExtent - controller.offset,
        greaterThan(140),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resposta do Codex ignora sugestões legadas e formata negrito', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(384, 832);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      _ChatTestApp(
        query:
            ({
              required message,
              required conversationId,
              required mode,
              clientId,
              regionId,
            }) async {
              return _regionSelectionResponse();
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Liste as regiões cadastradas',
    );
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_region_selector')), findsNothing);
    expect(find.text('SELECIONE UMA REGIÃO'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.textContaining('**', findRichText: true), findsNothing);

    final RichText responseText = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('14 regiões cadastradas'),
      ),
    );
    final TextSpan root = responseText.text as TextSpan;
    expect(_containsBoldText(root, '14 regiões cadastradas'), isTrue);

    expect(tester.takeException(), isNull);
  });

  testWidgets('cliente longo não causa overflow e o card não é repetido', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    int calls = 0;
    await tester.pumpWidget(
      _ChatTestApp(
        query:
            ({
              required message,
              required conversationId,
              required mode,
              clientId,
              regionId,
            }) async => calls++ == 0
            ? _clientDetailResponse()
            : _clientFollowUpResponse(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Kamila Delcidia');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    const ValueKey<String> clientCard = ValueKey('chat_client_card_91');
    expect(find.byKey(clientCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Último pagamento');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(find.byKey(clientCard), findsOneWidget);
    expect(find.textContaining('último pagamento foi em'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'ÚLTIMO PAGAMENTO'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'contrato não repete card e histórico abre lista rolável no balão',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(384, 832);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        _ChatTestApp(
          query:
              ({
                required message,
                required conversationId,
                required mode,
                clientId,
                regionId,
              }) async => message.toLowerCase().contains('histórico')
              ? _contractResponse('CONTRACT_HISTORY')
              : _contractResponse('CONTRACT_CONTEXT'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '46409');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      const ValueKey<String> contractCard = ValueKey(
        'chat_contract_card_46409',
      );
      expect(find.byKey(contractCard), findsOneWidget);
      expect(find.text('ATIVIDADE RECENTE'), findsNothing);
      expect(find.textContaining('Criado por'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'HISTÓRICO'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'OUTRO ASSUNTO'),
        findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'SALDO DO CONTRATO'),
        findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'PRÓXIMO VENCIMENTO'),
        findsNothing,
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Histórico');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      expect(find.byKey(contractCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_contract_history_46409')),
        findsOneWidget,
      );
      final Finder historyList = find.byKey(
        const ValueKey('chat_contract_history_list_46409'),
      );
      final ScrollController historyController = tester
          .widget<ListView>(historyList)
          .controller!;
      expect(historyController.position.maxScrollExtent, greaterThan(0));
      await tester.drag(historyList, const Offset(0, -100));
      await tester.pump();
      expect(historyController.offset, greaterThan(0));
      expect(find.widgetWithText(OutlinedButton, 'HISTÓRICO'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

AppChatResponse _chatResponse(String message) => AppChatResponse(
  message: message,
  mode: 'READY',
  suggestions: const [],
  clients: const [],
  summary: null,
  semanticSearch: false,
);

AppChatResponse _regionSelectionResponse() => AppChatResponse.fromJson({
  'message': 'Encontrei **14 regiões cadastradas**. Selecione uma abaixo para continuar.',
  'mode': 'SUMMARY_REGION',
  'semanticSearch': false,
  'clients': const [],
  'suggestions': List.generate(
    14,
    (index) => {
      'label': 'REGIÃO ${index + 1}',
      'message': 'REGIÃO ${index + 1}',
      'regionId': index + 1,
    },
  ),
});

AppChatResponse _clientDetailResponse() => AppChatResponse.fromJson({
  'message': 'Cliente encontrado.',
  'mode': 'CLIENT_CONTEXT',
  'semanticSearch': true,
  'suggestions': _clientSuggestions,
  'clients': [
    {
      'id': 91,
      'name': 'KAMILA DELCIDIA CAMPOS TIBURCIO',
      'document': '03994792100',
      'phone': '65999163643',
      'regionId': 12,
      'regionName': 'CASH - CHINAYDER - (65) 99345-6245',
      'openLoans': 1,
      'loaned': 4500,
      'received': 4560,
      'receivable': 1500,
      'overdue': 0,
      'dueToday': 0,
    },
  ],
});

AppChatResponse _clientFollowUpResponse() => AppChatResponse.fromJson({
  'message': 'O último pagamento foi em 14/08/2026, no valor de R\$ 132,00.',
  'mode': 'CLIENT_CONTEXT',
  'semanticSearch': true,
  'suggestions': _clientSuggestions,
  'clients': const [],
});

const List<Map<String, Object>> _clientSuggestions = [
  {'label': 'Último pagamento', 'message': 'Qual foi o último pagamento?'},
  {'label': 'Próximo vencimento', 'message': 'Quando vence a próxima parcela?'},
  {'label': 'Saldo atual', 'message': 'Quanto ainda está devendo?'},
  {'label': 'Outro cliente', 'message': 'Consultar cliente'},
];

AppChatResponse _contractResponse(String mode) => AppChatResponse.fromJson({
  'message': mode == 'CONTRACT_HISTORY'
      ? 'Encontrei o histórico do contrato #46409.'
      : 'Encontrei o contrato #46409. Organizei os dados atuais abaixo.',
  'mode': mode,
  'semanticSearch': true,
  'suggestions': const [
    {'label': 'Histórico', 'message': 'Mostre o histórico de alterações'},
    {'label': 'Outro assunto', 'message': 'Outro assunto'},
  ],
  'clients': const [],
  'contract': {
    'loanId': 46409,
    'clientId': 91,
    'clientName': 'ALAN MALONE CARVALHO',
    'regionId': 12,
    'regionName': 'CBA',
    'contractDate': '2026-08-04',
    'paymentType': 'Diário',
    'installmentCount': 20,
    'paidInstallments': 11,
    'openInstallments': 9,
    'overdueInstallments': 0,
    'loanedAmount': 400,
    'totalAmount': 640,
    'receivedAmount': 352,
    'receivableAmount': 288,
    'profitAmount': 0,
    'status': 'Vence hoje',
    'approvalStatus': 'APROVADO',
    'lastPaymentDate': '2026-08-20',
    'lastPaymentAmount': 32,
    'nextDueDate': '2026-08-20',
    'nextDueAmount': 32,
    'createdBy': 'MARCIO BR',
    'approvedBy': 'MARCIO BR',
    'history': List.generate(
      8,
      (index) => {
        'category': index == 0 ? 'APROVACAO' : 'EMPRESTIMO',
        'operation': index == 0 ? 'APROVADO' : 'alterarEmprestimo',
        'description': 'Alteração financeira número ${index + 1}.',
        'username': 'OPERADOR ${index + 1}',
        'occurredAt':
            '2026-08-${(20 - index).toString().padLeft(2, '0')}T10:00:00',
      },
    ),
  },
});

class _ChatTestApp extends StatelessWidget {
  final ChatQueryCallback query;

  const _ChatTestApp({required this.query});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        extendBody: true,
        resizeToAvoidBottomInset: false,
        body: ChatScreen(query: query),
        floatingActionButton: const HomeFloatingActionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: HomeBottomNavigationBar(
          activeIndex: 2,
          onTap: (_) {},
        ),
      ),
    );
  }
}

bool _containsBoldText(TextSpan span, String text) {
  if (span.text == text && span.style?.fontWeight == FontWeight.w700) {
    return true;
  }
  return span.children?.whereType<TextSpan>().any(
        (child) => _containsBoldText(child, text),
      ) ??
      false;
}
