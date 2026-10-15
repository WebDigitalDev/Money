import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: true,
    );
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });
  test('meta financeira interpreta progresso e limita o círculo a 100%', () {
    final AppFinancialGoal goal = AppFinancialGoal.fromJson({
      'id': 8,
      'regionId': 3,
      'regionName': 'ATLAS CRED - DANIEL',
      'type': 'RECEBIDO',
      'targetAmount': 1000,
      'achievedAmount': 1250,
      'remainingAmount': 0,
      'percentage': 125,
      'startDate': '2026-08-01',
      'endDate': '2026-08-31',
      'status': 'ATIVA',
      'canManage': true,
    });

    expect(goal.type, AppFinancialGoalType.received);
    expect(goal.percentage, 125);
    expect(goal.displayPercentage, 100);
    expect(goal.progress, 1);
    expect(goal.canManage, isTrue);
  });

  test('metas encerradas somem ao completar 48 horas', () {
    for (final String type in const ['RECEBIDO', 'CLIENTES_EM_DIA']) {
      final AppFinancialGoal goal = AppFinancialGoal.fromJson({
        'id': 8,
        'regionId': 3,
        'regionName': 'ATLAS CRED',
        'type': type,
        'targetAmount': 100,
        'achievedAmount': 90,
        'remainingAmount': 10,
        'percentage': 90,
        'startDate': '2026-09-20',
        'endDate': '2026-09-25',
        'status': 'ENCERRADA',
        'canManage': true,
      });

      expect(
        goal.isVisibleInGoalsAt(DateTime(2026, 9, 27, 23, 59, 59)),
        isTrue,
      );
      expect(goal.isVisibleInGoalsAt(DateTime(2026, 9, 28)), isFalse);
    }
  });

  test(
    'serviço descarta metas antigas antes de renderizar e salvar cache',
    () async {
      final FinancialGoalService service = FinancialGoalService.forTesting(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'responseBody': [
                {
                  'id': 19,
                  'regionId': 3,
                  'regionName': 'ATLAS CRED',
                  'type': 'RECEBIDO',
                  'targetAmount': 1000,
                  'achievedAmount': 900,
                  'remainingAmount': 100,
                  'percentage': 90,
                  'startDate': '2025-01-01',
                  'endDate': '2025-01-31',
                  'status': 'ENCERRADA',
                  'canManage': true,
                },
                {
                  'id': 20,
                  'regionId': 3,
                  'regionName': 'ATLAS CRED',
                  'type': 'CLIENTES_EM_DIA',
                  'targetAmount': 80,
                  'achievedAmount': 75,
                  'remainingAmount': 5,
                  'percentage': 93.75,
                  'startDate': '2025-01-01',
                  'endDate': '2025-01-31',
                  'status': 'ENCERRADA',
                  'canManage': true,
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );

      expect(await service.fetchGoals(), isEmpty);
    },
  );

  test('serviço envia o cadastro no formato esperado pela API', () async {
    late http.Request sent;
    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'responseBody': {
              'id': 12,
              'regionId': 4,
              'regionName': 'CASH - CHINAYDER',
              'type': 'LUCRO',
              'targetAmount': 5000,
              'achievedAmount': 0,
              'remainingAmount': 5000,
              'percentage': 0,
              'startDate': '2026-08-18',
              'endDate': '2026-09-18',
              'status': 'ATIVA',
              'canManage': true,
            },
          }),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final AppFinancialGoal created = await service.createGoal(
      AppFinancialGoalDraft(
        regionIds: const [4, 7],
        type: AppFinancialGoalType.profit,
        targetAmount: 5000,
        startDate: DateTime(2026, 8, 18),
        endDate: DateTime(2026, 9, 18),
      ),
    );

    final Map<String, dynamic> payload = jsonDecode(sent.body);
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v2/financial-goals');
    expect(payload['regionId'], 4);
    expect(payload['regionIds'], [4, 7]);
    expect(payload['type'], 'LUCRO');
    expect(payload['startDate'], '2026-08-18');
    expect(payload['endDate'], '2026-09-18');
    expect(payload['repeatFrequency'], isFalse);
    expect(created.id, 12);
  });

  test('meta de clientes envia e interpreta repetição de frequência', () async {
    late http.Request sent;
    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'responseBody': {
              'id': 20,
              'regionId': 4,
              'regionName': 'CASH',
              'type': 'CLIENTES_EM_DIA',
              'targetAmount': 70,
              'achievedAmount': 0,
              'remainingAmount': 70,
              'percentage': 0,
              'startDate': '2026-09-21',
              'endDate': '2026-09-21',
              'status': 'ATIVA',
              'canManage': true,
              'repeatFrequency': true,
            },
          }),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final AppFinancialGoal created = await service.createGoal(
      AppFinancialGoalDraft(
        regionIds: const [4],
        type: AppFinancialGoalType.onTimeClients,
        targetAmount: 70,
        startDate: DateTime(2026, 9, 21),
        endDate: DateTime(2026, 9, 21),
        repeatFrequency: true,
      ),
    );

    final Map<String, dynamic> payload = jsonDecode(sent.body);
    expect(payload['repeatFrequency'], isTrue);
    expect(created.repeatFrequency, isTrue);
  });

  test('serviço exclui a meta pelo identificador', () async {
    late http.Request sent;
    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient((request) async {
        sent = request;
        return http.Response('', 204);
      }),
    );

    await service.deleteGoal(12);

    expect(sent.method, 'DELETE');
    expect(sent.url.path, '/api/v2/financial-goals/12');
  });

  testWidgets('card financeiro cabe no celular e exibe valores e percentual', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final AppFinancialGoal goal = AppFinancialGoal.fromJson({
      'id': 8,
      'regionId': 3,
      'regionName': 'BLACK CRED - MICAELLEN / CLEBSON - (65) 99999-9999',
      'type': 'EMPRESTADO',
      'targetAmount': 10000,
      'achievedAmount': 6500,
      'remainingAmount': 3500,
      'percentage': 65,
      'startDate': '2026-08-01',
      'endDate': '2026-08-31',
      'status': 'ATIVA',
      'canManage': true,
    });

    int editCount = 0;
    int deleteCount = 0;
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
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 242,
              child: FinancialGoalCard(
                goal: goal,
                compact: true,
                onEdit: () => editCount++,
                onDelete: () => deleteCount++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Valor da meta'), findsOneWidget);
    expect(find.text('Valor alcançado'), findsOneWidget);
    expect(find.text('65%'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('financial_goal_edit_8')));
    expect(editCount, 1);
    await tester.tap(find.byKey(const ValueKey('financial_goal_delete_8')));
    expect(deleteCount, 1);
    final CustomPaint progressArc = tester.widget(
      find.byKey(const ValueKey('financial_goal_progress_arc')),
    );
    final FinancialGoalProgressPainter painter =
        progressArc.painter! as FinancialGoalProgressPainter;
    expect(painter.progress, closeTo(.65, .001));
    expect(painter.endColor, painter.color);
    expect(painter.startColor, Color.lerp(painter.color, Colors.white, .55));
    expect(
      painter.startColor.computeLuminance(),
      greaterThan(painter.endColor.computeLuminance()),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('financial_goal_progress_arc')))
          .shortestSide,
      88,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('meta financeira encerrada permanece visível na lista', (
    tester,
  ) async {
    final DateTime today = DateTime.now();
    final DateTime endDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'responseBody': [
              {
                'id': 19,
                'regionId': 3,
                'regionName': 'ATLAS CRED',
                'type': 'RECEBIDO',
                'targetAmount': 1000,
                'achievedAmount': 900,
                'remainingAmount': 100,
                'percentage': 90,
                'startDate': _isoDate(
                  endDate.subtract(const Duration(days: 30)),
                ),
                'endDate': _isoDate(endDate),
                'status': 'ENCERRADA',
                'canManage': true,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: FinancialGoalsScreen(
          showAppBar: false,
          service: service,
          administrator: true,
          fetchRegions: ({required bool force}) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ATLAS CRED'), findsOneWidget);
    expect(find.text('Período encerrado'), findsOneWidget);
    expect(find.byKey(const ValueKey('financial_goal_edit_19')), findsNothing);
    expect(
      find.byKey(const ValueKey('financial_goal_delete_19')),
      findsOneWidget,
    );
  });

  testWidgets('meta de clientes encerrada permanece visível na lista', (
    tester,
  ) async {
    final DateTime today = DateTime.now();
    final DateTime endDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'responseBody': [
              {
                'id': 20,
                'regionId': 3,
                'regionName': 'ATLAS CRED',
                'type': 'CLIENTES_EM_DIA',
                'targetAmount': 90,
                'achievedAmount': 80,
                'remainingAmount': 10,
                'percentage': 88.89,
                'startDate': _isoDate(
                  endDate.subtract(const Duration(days: 30)),
                ),
                'endDate': _isoDate(endDate),
                'status': 'ENCERRADA',
                'canManage': true,
                'clients': {
                  'active': 10,
                  'onTime': 8,
                  'overdue': 2,
                  'newClients': 1,
                },
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: FinancialGoalsScreen(
          showAppBar: false,
          service: service,
          administrator: true,
          fetchRegions: ({required bool force}) async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();

    expect(find.text('ATLAS CRED'), findsOneWidget);
    expect(find.textContaining('Encerrada •'), findsOneWidget);
    expect(find.byKey(const ValueKey('financial_goal_edit_20')), findsNothing);
  });

  testWidgets('cards financeiros ficam baixos e retangulares no desktop', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final List<Map<String, Object>> goals = List.generate(3, (index) {
      final int id = index + 1;
      return {
        'id': id,
        'regionId': id,
        'regionName': index == 0
            ? 'GRUPO DE REGIÕES'
            : 'ALPHACRED - DANIEL / (65) 9 9990-7305',
        if (index == 0) 'regionIds': [1, 2],
        if (index == 0)
          'regionNames': ['ALPHACRED - DANIEL', 'CASH - CHINAYDER'],
        'type': index == 0
            ? 'RECEBIDO'
            : index == 1
            ? 'EMPRESTADO'
            : 'LUCRO',
        'targetAmount': 10000,
        'achievedAmount': 3500,
        'remainingAmount': 6500,
        'percentage': 35,
        'startDate': '2026-08-20',
        'endDate': '2026-09-19',
        'status': 'ATIVA',
        'canManage': false,
      };
    });
    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'responseBody': goals}),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: FinancialGoalsScreen(
          showAppBar: false,
          service: service,
          administrator: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (int id = 1; id <= 3; id++) {
      final Size cardSize = tester.getSize(
        find.byKey(ValueKey('financial_goal_card_$id')),
      );
      expect(cardSize.height, closeTo(218, .1));
      expect(cardSize.width / cardSize.height, greaterThan(1.8));
    }
    expect(find.text('GRUPO DE REGIÕES'), findsOneWidget);
    expect(find.text('ALPHACRED - DANIEL • CASH - CHINAYDER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modal de meta usa dimensões compactas no desktop', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'responseBody': <Object>[]}),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    final FinancialGoalsScreenController controller =
        FinancialGoalsScreenController();

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: FinancialGoalsScreen(
          showAppBar: false,
          controller: controller,
          service: service,
          administrator: true,
          fetchRegions: ({required bool force}) async => const [
            AppRegionOption(id: 3, name: 'ALPHACRED - DANIEL'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.openCreate();
    await tester.pumpAndSettle();

    final Size modalSize = tester.getSize(find.byType(AppDialogPanel));
    expect(modalSize.width, closeTo(520, .1));
    expect(modalSize.height, closeTo(430, .1));
    expect(find.text('Nova meta financeira'), findsOneWidget);
    expect(find.text('Regiões'), findsOneWidget);
    expect(find.text('Período da meta'), findsOneWidget);
    expect(find.text('CANCELAR'), findsOneWidget);
    expect(find.text('SALVAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modal de meta de clientes exibe repetição abaixo do período', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'responseBody': <Object>[]}),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    final FinancialGoalsScreenController controller =
        FinancialGoalsScreenController();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: FinancialGoalsScreen(
          showAppBar: false,
          controller: controller,
          service: service,
          administrator: true,
          fetchRegions: ({required bool force}) async => const [
            AppRegionOption(id: 3, name: 'ALPHACRED - DANIEL'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();

    controller.openCreate();
    await tester.pumpAndSettle();

    expect(find.text('Nova meta de clientes'), findsOneWidget);
    expect(find.text('Repetir frequência'), findsOneWidget);
    expect(
      find.text('Criar o próximo período automaticamente.'),
      findsOneWidget,
    );
    expect(find.byType(Switch), findsOneWidget);
    expect(
      tester.getSize(find.byType(AppDialogPanel)).height,
      closeTo(485, .1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('seletor de região mobile abre compacto e com rolagem', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'responseBody': <Object>[]}),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    final FinancialGoalsScreenController controller =
        FinancialGoalsScreenController();
    final List<AppRegionOption> regions = List.generate(
      15,
      (index) => AppRegionOption(
        id: index + 1,
        name: 'REGIÃO FINANCEIRA ${index + 1}',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: FinancialGoalsScreen(
          showAppBar: false,
          controller: controller,
          service: service,
          administrator: true,
          fetchRegions: ({required bool force}) async => regions,
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.openCreate();
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AppDialogPanel)).height,
      closeTo(455, .1),
    );
    final Finder regionsButton = find.byKey(
      const ValueKey('financial_goal_regions_button'),
    );

    await tester.tap(regionsButton);
    await tester.pumpAndSettle();

    expect(find.text('Regiões da meta'), findsOneWidget);
    expect(find.text('Pesquisar região'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.text('REGIÃO FINANCEIRA 1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('última meta sobe inteira acima da navegação mobile', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final List<Map<String, Object>> goals = List.generate(4, (index) {
      final int id = index + 1;
      return {
        'id': id,
        'regionId': id,
        'regionName': 'REGIÃO FINANCEIRA $id',
        'type': 'EMPRESTADO',
        'targetAmount': 10000,
        'achievedAmount': 3500,
        'remainingAmount': 6500,
        'percentage': 35,
        'startDate': '2026-08-20',
        'endDate': '2026-09-19',
        'status': 'ATIVA',
        'canManage': false,
      };
    });
    final FinancialGoalService service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'responseBody': goals}),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
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
          extendBody: true,
          body: FinancialGoalsScreen(service: service),
          bottomNavigationBar: const SizedBox(
            key: ValueKey('test_bottom_navigation'),
            height: 80,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder listFinder = find.byKey(
      const ValueKey('financial_goals_mobile_list'),
    );
    final ListView list = tester.widget<ListView>(listFinder);
    expect((list.padding! as EdgeInsets).bottom, greaterThan(130));

    await tester.drag(listFinder, const Offset(0, -2000));
    await tester.pumpAndSettle();

    final double lastCardBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('financial_goal_card_4')))
        .dy;
    final double navigationTop = tester
        .getTopLeft(find.byKey(const ValueKey('test_bottom_navigation')))
        .dy;
    expect(lastCardBottom, lessThan(navigationTop));
    expect(tester.takeException(), isNull);
  });
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
