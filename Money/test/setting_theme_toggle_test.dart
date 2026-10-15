import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('preferência antiga de tema do sistema migra para tema claro', () async {
    SharedPreferences.setMockInitialValues({
      UserPrefsKeys.themeMode.name: ThemeMode.system.name,
    });

    final AppSettings settings = await SharedPreferencesService().getSettings();

    expect(settings.themeMode, ThemeMode.light);
    expect(
      SharedCubit(ThemeMode.system).state,
      const SharedInitial(themeMode: ThemeMode.light),
    );
  });

  testWidgets('tema alterna diretamente entre sol e lua sem bottom sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final SharedCubit sharedCubit = SharedCubit(ThemeMode.light);
    final SettingCubit settingCubit = _ReadySettingCubit(ThemeMode.light);
    addTearDown(sharedCubit.close);
    addTearDown(settingCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: sharedCubit),
          BlocProvider.value(value: settingCubit),
        ],
        child: const _ThemeTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Usar tema do dispositivo'), findsNothing);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(find.byType(ModalBottomSheet), findsNothing);

    await tester.tap(find.text('Tema'));
    await tester.pumpAndSettle();

    expect(find.text('Escuro'), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.byType(ModalBottomSheet), findsNothing);
    expect(
      Theme.of(tester.element(find.byType(SettingScreen))).brightness,
      Brightness.dark,
    );

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(UserPrefsKeys.themeMode.name),
      ThemeMode.dark.name,
    );

    await tester.tap(find.text('Tema'));
    await tester.pumpAndSettle();

    expect(find.text('Claro'), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(SettingScreen))).brightness,
      Brightness.light,
    );
  });

  testWidgets('compartilhar Money habilita Android, iOS e Web', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final SharedCubit sharedCubit = SharedCubit(ThemeMode.light);
    final SettingCubit settingCubit = _ReadySettingCubit(ThemeMode.light);
    addTearDown(sharedCubit.close);
    addTearDown(settingCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: sharedCubit),
          BlocProvider.value(value: settingCubit),
        ],
        child: const _ThemeTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    final Finder shareMoney = find.text('Compartilhar o Money');
    await tester.ensureVisible(shareMoney);
    await tester.tap(shareMoney);
    await tester.pumpAndSettle();

    expect(find.text('ANDROID'), findsOneWidget);
    expect(find.text('IOS'), findsOneWidget);
    expect(find.text('WEB'), findsOneWidget);
    expect(find.text('Em breve'), findsNothing);
    expect(find.text('Compartilhar'), findsNWidgets(3));
    expect(find.text('moneyapp.site'), findsOneWidget);

    final InkWell android = tester.widget(
      find.ancestor(of: find.text('ANDROID'), matching: find.byType(InkWell)),
    );
    final InkWell ios = tester.widget(
      find.ancestor(of: find.text('IOS'), matching: find.byType(InkWell)),
    );
    final InkWell web = tester.widget(
      find.ancestor(of: find.text('WEB'), matching: find.byType(InkWell)),
    );
    expect(android.onTap, isNotNull);
    expect(ios.onTap, isNotNull);
    expect(web.onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

class _ReadySettingCubit extends SettingCubit {
  _ReadySettingCubit(ThemeMode themeMode) {
    emit(
      SettingInitial(
        themeMode: themeMode,
        enableScreenshot: true,
        appLocked: false,
        canAuthenticate: false,
        packageInfo: PackageInfo(
          appName: 'Money',
          packageName: 'com.webdigital.money',
          version: '1.0.0',
          buildNumber: '1',
        ),
      ),
    );
  }
}

class _ThemeTestApp extends StatelessWidget {
  const _ThemeTestApp();

  @override
  Widget build(BuildContext context) {
    final SharedInitial state =
        context.watch<SharedCubit>().state as SharedInitial;
    return MaterialApp(
      theme: lightThemeData,
      darkTheme: darkThemeData,
      themeMode: state.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 160),
      themeAnimationCurve: Curves.easeOutCubic,
      locale: const Locale('pt'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppStrings.supportedLocales,
      home: const SettingScreen(showAppBar: false),
    );
  }
}
