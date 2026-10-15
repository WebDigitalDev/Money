import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';
import 'package:money/data/services/app_notification_service.dart';

void main() {
  test('cache do dashboard preserva contagens das metas de clientes', () {
    final dashboard = AppDashboardData.fromJson({
      'activeGoals': [
        {
          'id': 1,
          'type': 'CLIENTES_EM_DIA',
          'clients': {'active': 10, 'onTime': 8, 'overdue': 2, 'newClients': 3},
        },
      ],
    });
    final restored = AppDashboardData.fromJson(dashboard.toJson())
        .activeGoals
        .single;
    expect(restored.activeClients, 10);
    expect(restored.onTimeClients, 8);
    expect(restored.overdueClients, 2);
    expect(restored.newClients, 3);
  });
  testWidgets('abas de metas permitem mudar por deslize', (tester) async {
    final service = FinancialGoalService.forTesting(
      MockClient(
        (_) async => http.Response(jsonEncode({'responseBody': []}), 200),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: FinancialGoalsScreen(
          showAppBar: false,
          administrator: false,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    await tester.drag(find.byType(TabBarView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma meta de clientes criada'), findsOneWidget);
    await tester.drag(find.byType(TabBarView), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma meta financeira criada'), findsOneWidget);
  });
  test('notificação expira exatamente ao completar 24 horas', () {
    final created = DateTime.utc(2026, 9, 17, 10);
    final item = AppNotification.fromJson({
      'id': 1,
      'kind': 'PAYMENT',
      'title': 'PIX',
      'body': 'Teste',
      'createdAt': created.toIso8601String(),
      'expiresAt': created.add(const Duration(hours: 24)).toIso8601String(),
    });
    expect(
      item.visibleAt(created.add(const Duration(hours: 23, minutes: 59))),
      isTrue,
    );
    expect(item.visibleAt(created.add(const Duration(hours: 24))), isFalse);
  });
  test('notificações são desativadas por padrão', () {
    expect(AppNotificationService.instance.payments, isFalse);
    expect(AppNotificationService.instance.goals, isFalse);
  });
  testWidgets(
    'meta de atraso exibe contagens e progresso horizontal no celular',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final goal = AppFinancialGoal.fromJson({
        'id': 1,
        'regionId': 1,
        'regionName': 'Região de teste',
        'type': 'CLIENTES_ATRASO',
        'targetAmount': 20,
        'achievedAmount': 20,
        'remainingAmount': 0,
        'percentage': 100,
        'startDate': '2026-09-17',
        'endDate': '2026-09-17',
        'status': 'ATIVA',
        'canManage': false,
        'clients': {'active': 10, 'onTime': 8, 'overdue': 2, 'newClients': 3},
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('pt', 'BR')],
          locale: const Locale('pt', 'BR'),
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: FinancialGoalCard(
                goal: goal,
                onEdit: null,
                onDelete: null,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Clientes ativos: 10'), findsOneWidget);
      expect(find.text('Clientes em dia: 8 — 80%'), findsOneWidget);
      expect(find.text('Clientes em atraso: 2 — 20%'), findsOneWidget);
      expect(find.text('Novos clientes no período: 3'), findsOneWidget);
      expect(find.text('Meta alcançada • 100%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
