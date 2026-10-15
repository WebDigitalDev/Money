import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:money/money.dart';
import 'package:money/presentation/screens/notifications_screen.dart';

void main() {
  Widget buildApp() {
    return BlocProvider(
      create: (_) => HomeCubit(),
      child: MaterialApp(
        theme: lightThemeData,
        locale: const Locale('pt'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: HomeScreen(onLogout: () async {}),
      ),
    );
  }

  Widget buildDesktopApp({bool administrator = true}) {
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
      home: DesktopHomeLayout(
        activeDestination: DesktopDestination.home,
        onDestinationSelected: (_) {},
        onLogout: () async {},
        administrator: administrator,
      ),
    );
  }

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

  testWidgets('web compacta mantém navegação mobile', (tester) async {
    await setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(DesktopHomeLayout), findsNothing);
    expect(find.byType(HomeBottomNavigationBar), findsOneWidget);
    expect(find.byType(AppSidebarMenu), findsOneWidget);

    final ZoomDrawer drawer = tester.widget(find.byType(ZoomDrawer));
    expect(drawer.showShadow, isTrue);
    expect(drawer.moveMenuScreen, isFalse);
    expect(drawer.shadowLayer1Color, isNotNull);
    expect(drawer.shadowLayer2Color, isNotNull);
    expect(drawer.menuBackgroundColor, Colors.transparent);
    expect(drawer.drawerShadowsBackgroundColor, Colors.transparent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modo offline permanece dentro da navegação mobile', (
    tester,
  ) async {
    NetworkStatusService().setStatusForTesting(NetworkStatus.offline);
    addTearDown(
      () => NetworkStatusService().setStatusForTesting(NetworkStatus.online),
    );
    await setViewport(tester, width: 499, height: 900);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(OfflineScreen), findsOneWidget);
    expect(find.text('RECONECTAR'), findsOneWidget);
    expect(find.byType(HomeBottomNavigationBar), findsOneWidget);
    expect(find.byType(AppSidebarMenu), findsOneWidget);

    final HomeBottomNavigationBar navigation = tester.widget(
      find.byType(HomeBottomNavigationBar),
    );
    navigation.onTap(1);
    await tester.pump();

    expect(find.byType(OfflineScreen), findsOneWidget);
    expect(find.byType(HomeBottomNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notificações usam menu lateral e navbar sem botão voltar', (
    tester,
  ) async {
    await setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.tap(find.byTooltip('Notificações').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(HomeBottomNavigationBar), findsOneWidget);
    expect(find.byType(AppSidebarMenuButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('VOLTAR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voltar em uma página interna retorna para a Home', (
    tester,
  ) async {
    await setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final HomeBottomNavigationBar navigation = tester.widget(
      find.byType(HomeBottomNavigationBar),
    );
    navigation.onTap(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TransactionScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(TransactionScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('botão central assume a ação de novo usuário no mobile', (
    tester,
  ) async {
    await setViewport(tester, width: 499, height: 900);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final AppSidebarMenu sidebar = tester.widget(find.byType(AppSidebarMenu));
    sidebar.onOpenUsers();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final HomeFloatingActionButton centralButton = tester.widget(
      find.byType(HomeFloatingActionButton),
    );
    expect(centralButton.iconData, Icons.person_add_alt_1_rounded);
    expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);

    centralButton.onPressed!.call();
    await tester.pump();

    expect(find.text('Novo usuário'), findsOneWidget);
    expect(find.byType(HomeBottomNavigationBar), findsNothing);
    expect(find.byType(HomeFloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('perfil abre dentro do conteúdo e mantém o navbottom', (
    tester,
  ) async {
    await setViewport(tester, width: 499, height: 900);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Perfil'));
    await tester.pump();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(HomeBottomNavigationBar), findsOneWidget);
    final HomeBottomNavigationBar navigation = tester.widget(
      find.byType(HomeBottomNavigationBar),
    );
    expect(navigation.activeIndex, -1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat mantém o botão central e a navegação', (tester) async {
    await setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final HomeBottomNavigationBar navigation = tester.widget(
      find.byType(HomeBottomNavigationBar),
    );
    navigation.onTap(2);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final Finder centralButton = find.byType(HomeFloatingActionButton);
    final Finder bottomNavigation = find.byType(HomeBottomNavigationBar);

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(centralButton, findsOneWidget);
    expect(bottomNavigation, findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen troca para o layout desktop na web', (tester) async {
    await setViewport(tester, width: 1440, height: 900);
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(DesktopHomeLayout), findsOneWidget);
    expect(find.byType(HomeBottomNavigationBar), findsNothing);
    expect(find.byType(AppSidebarMenu), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);

  testWidgets('web desktop usa menu horizontal e abre submenus', (
    tester,
  ) async {
    await setViewport(tester, width: 1920, height: 900);
    await tester.pumpWidget(buildDesktopApp());
    await tester.pump();

    expect(find.byType(DesktopHomeLayout), findsOneWidget);
    expect(find.byType(HomeBottomNavigationBar), findsNothing);
    expect(find.byType(AppSidebarMenu), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Pessoas'), findsOneWidget);
    expect(find.text('Integrações'), findsOneWidget);
    expect(find.byTooltip('Conferências'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final Finder logo = find.byWidgetPredicate(
      (widget) =>
          widget is Image && widget.image == const AssetImage(AppImages.money),
    );
    final Finder page = find.byType(DashboardScreen);
    final Finder profileIcon = find.byIcon(Icons.person_rounded);
    final Finder firstMenuIcon = find.byIcon(Icons.home_outlined);
    final Finder firstMenuItem = find.text('Home');
    final Finder lastMenuItem = find.text('Configurações');
    final Finder navigationViewport = find.byType(SingleChildScrollView);

    expect(logo, findsOneWidget, reason: 'A logo desktop deve ser única.');
    expect(page, findsOneWidget, reason: 'A página deve estar montada.');
    expect(
      profileIcon,
      findsOneWidget,
      reason: 'O ícone de perfil desktop deve ser único.',
    );
    expect(firstMenuItem, findsOneWidget);
    expect(firstMenuIcon, findsOneWidget);
    expect(lastMenuItem, findsOneWidget);
    expect(navigationViewport, findsOneWidget);

    final Rect pageBounds = tester.getRect(page);
    final Rect logoBounds = tester.getRect(logo);
    final Rect profileIconBounds = tester.getRect(profileIcon);
    final Rect firstMenuIconBounds = tester.getRect(firstMenuIcon);
    final Rect navigationBounds = tester.getRect(navigationViewport);

    expect(
      pageBounds.width,
      closeTo(1400, 0.1),
      reason: 'A página deve respeitar a largura máxima desktop.',
    );
    expect(
      pageBounds.center.dx,
      closeTo(960, 0.1),
      reason: 'A página deve permanecer centralizada na viewport.',
    );
    expect(
      logoBounds.left,
      closeTo(pageBounds.left, 0.1),
      reason: 'A logo deve começar no mesmo limite da página.',
    );
    expect(
      profileIconBounds.right,
      lessThanOrEqualTo(pageBounds.right),
      reason: 'As ações não podem ultrapassar o limite da página.',
    );
    expect(
      navigationBounds.left,
      closeTo(pageBounds.left, 0.1),
      reason: 'Menu e página devem iniciar no mesmo limite.',
    );
    expect(
      navigationBounds.right,
      closeTo(pageBounds.right, 0.1),
      reason: 'O menu e a página devem compartilhar os mesmos limites.',
    );
    expect(
      firstMenuIconBounds.left,
      closeTo(pageBounds.left + 15, 0.1),
      reason: 'O primeiro item deve começar no limite esquerdo do conteúdo.',
    );

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Pessoas')));
    await tester.pumpAndSettle();

    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Usuários'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat desktop abre como painel flutuante compacto', (
    tester,
  ) async {
    await setViewport(tester, width: 1440, height: 900);
    await tester.pumpWidget(buildDesktopApp());
    await tester.pump();

    final Finder chatButton = find.byKey(const ValueKey('desktop_chat_button'));
    final Finder chatPanel = find.byKey(const ValueKey('desktop_chat_panel'));
    final Finder profileImage = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image == const AssetImage('assets/images/profile.png'),
    );

    expect(chatButton, findsOneWidget);
    expect(profileImage, findsOneWidget);
    expect(chatPanel, findsNothing);
    expect(find.byTooltip('Abrir assistente financeira'), findsOneWidget);

    final Rect buttonBounds = tester.getRect(chatButton);
    expect(buttonBounds.right, closeTo(1424, 0.1));
    expect(buttonBounds.bottom, closeTo(884, 0.1));

    await tester.tap(chatButton);
    await tester.pump();

    expect(chatPanel, findsOneWidget);
    expect(find.byType(ChatScreen), findsOneWidget);
    final Rect panelBounds = tester.getRect(chatPanel);
    expect(panelBounds.width, closeTo(410, 0.1));
    expect(panelBounds.height, closeTo(590, 0.1));
    expect(panelBounds.right, closeTo(1416, 0.1));
    expect(panelBounds.bottom, closeTo(808, 0.1));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('desktop_chat_close_button')));
    await tester.pump();

    expect(chatPanel, findsNothing);
    expect(find.byTooltip('Abrir assistente financeira'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu de usuários fica oculto para não administradores', (
    tester,
  ) async {
    await setViewport(tester, width: 1440, height: 900);
    await tester.pumpWidget(buildDesktopApp(administrator: false));
    await tester.pump();

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Pessoas')));
    await tester.pumpAndSettle();

    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Usuários'), findsNothing);

    expect(find.text('Integrações'), findsNothing);
    expect(find.text('Metas'), findsOneWidget);
    expect(find.text('API Sicredi'), findsNothing);
    expect(find.text('API Whatsapp'), findsNothing);
    expect(find.byTooltip('Conferências'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sino de conferências aparece somente para administradores', (
    tester,
  ) async {
    await setViewport(tester, width: 1440, height: 900);
    await tester.pumpWidget(buildDesktopApp(administrator: true));
    await tester.pump();

    expect(find.byTooltip('Conferências'), findsOneWidget);

    await tester.pumpWidget(buildDesktopApp(administrator: false));
    await tester.pump();

    expect(find.byTooltip('Conferências'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
