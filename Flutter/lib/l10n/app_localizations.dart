import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('pt')];

  /// No description provided for @app_name.
  ///
  /// In pt, this message translates to:
  /// **'Money'**
  String get app_name;

  /// No description provided for @sidebar_slogan.
  ///
  /// In pt, this message translates to:
  /// **'Gestão de Empréstimos Pessoais'**
  String get sidebar_slogan;

  /// No description provided for @ai.
  ///
  /// In pt, this message translates to:
  /// **'Chat Financeiro'**
  String get ai;

  /// No description provided for @desktop_home.
  ///
  /// In pt, this message translates to:
  /// **'Home'**
  String get desktop_home;

  /// No description provided for @desktop_people.
  ///
  /// In pt, this message translates to:
  /// **'Pessoas'**
  String get desktop_people;

  /// No description provided for @desktop_integrations.
  ///
  /// In pt, this message translates to:
  /// **'Integrações'**
  String get desktop_integrations;

  /// No description provided for @profile.
  ///
  /// In pt, this message translates to:
  /// **'Perfil'**
  String get profile;

  /// No description provided for @notifications.
  ///
  /// In pt, this message translates to:
  /// **'Notificações'**
  String get notifications;

  /// No description provided for @settings.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get settings;

  /// No description provided for @menu.
  ///
  /// In pt, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @sidebar_users.
  ///
  /// In pt, this message translates to:
  /// **'Usuários'**
  String get sidebar_users;

  /// No description provided for @sidebar_regions.
  ///
  /// In pt, this message translates to:
  /// **'Regiões'**
  String get sidebar_regions;

  /// No description provided for @sidebar_clients.
  ///
  /// In pt, this message translates to:
  /// **'Clientes'**
  String get sidebar_clients;

  /// No description provided for @sidebar_loans.
  ///
  /// In pt, this message translates to:
  /// **'Empréstimos'**
  String get sidebar_loans;

  /// No description provided for @sidebar_financial_goals.
  ///
  /// In pt, this message translates to:
  /// **'Metas'**
  String get sidebar_financial_goals;

  /// No description provided for @sidebar_banking_api.
  ///
  /// In pt, this message translates to:
  /// **'API Sicredi'**
  String get sidebar_banking_api;

  /// No description provided for @sidebar_whatsapp_api.
  ///
  /// In pt, this message translates to:
  /// **'API Whatsapp'**
  String get sidebar_whatsapp_api;

  /// No description provided for @sidebar_reports.
  ///
  /// In pt, this message translates to:
  /// **'Relatórios'**
  String get sidebar_reports;

  /// No description provided for @sidebar_support.
  ///
  /// In pt, this message translates to:
  /// **'Suporte'**
  String get sidebar_support;

  /// No description provided for @sidebar_logout.
  ///
  /// In pt, this message translates to:
  /// **'Logout'**
  String get sidebar_logout;

  /// No description provided for @new_loan.
  ///
  /// In pt, this message translates to:
  /// **'Novo Empréstimo'**
  String get new_loan;

  /// No description provided for @new_loan_description.
  ///
  /// In pt, this message translates to:
  /// **'Registre um novo empréstimo.'**
  String get new_loan_description;

  /// No description provided for @register_client.
  ///
  /// In pt, this message translates to:
  /// **'Cadastrar Cliente'**
  String get register_client;

  /// No description provided for @register_client_description.
  ///
  /// In pt, this message translates to:
  /// **'Adicione um novo cliente.'**
  String get register_client_description;

  /// No description provided for @theme_mode.
  ///
  /// In pt, this message translates to:
  /// **'Tema'**
  String get theme_mode;

  /// No description provided for @app_preferences.
  ///
  /// In pt, this message translates to:
  /// **'Preferências do aplicativo'**
  String get app_preferences;

  /// No description provided for @light_theme.
  ///
  /// In pt, this message translates to:
  /// **'Claro'**
  String get light_theme;

  /// No description provided for @dark_theme.
  ///
  /// In pt, this message translates to:
  /// **'Escuro'**
  String get dark_theme;

  /// No description provided for @app_lock.
  ///
  /// In pt, this message translates to:
  /// **'Acesso com biometria'**
  String get app_lock;

  /// No description provided for @app_lock_description.
  ///
  /// In pt, this message translates to:
  /// **'Use sua biometria para entrar com segurança no {app_name}'**
  String app_lock_description(Object app_name);

  /// No description provided for @lock_app_localized_reason.
  ///
  /// In pt, this message translates to:
  /// **'Confirme sua biometria para ativar o acesso rápido ao {app_name}.'**
  String lock_app_localized_reason(Object app_name);

  /// No description provided for @unlock_app_localized_reason.
  ///
  /// In pt, this message translates to:
  /// **'O acesso biométrico não será mais solicitado ao abrir o {app_name}.'**
  String unlock_app_localized_reason(Object app_name);

  /// No description provided for @screenshot.
  ///
  /// In pt, this message translates to:
  /// **'Capturas de tela'**
  String get screenshot;

  /// No description provided for @enable_screenshot_description.
  ///
  /// In pt, this message translates to:
  /// **'Permitir capturas de tela dentro do aplicativo.'**
  String get enable_screenshot_description;

  /// No description provided for @enable_screenshot_localized_reason.
  ///
  /// In pt, this message translates to:
  /// **'Confirme sua identidade para permitir capturas de tela.'**
  String get enable_screenshot_localized_reason;

  /// No description provided for @disable_screenshot_localized_reason.
  ///
  /// In pt, this message translates to:
  /// **'Confirme sua identidade para bloquear capturas de tela.'**
  String get disable_screenshot_localized_reason;

  /// No description provided for @security.
  ///
  /// In pt, this message translates to:
  /// **'Segurança'**
  String get security;

  /// No description provided for @about_app.
  ///
  /// In pt, this message translates to:
  /// **'Sobre o {app_name}'**
  String about_app(Object app_name);

  /// No description provided for @share_app.
  ///
  /// In pt, this message translates to:
  /// **'Compartilhar o {app_name}'**
  String share_app(Object app_name);

  /// No description provided for @share_app_description.
  ///
  /// In pt, this message translates to:
  /// **'Simplifique a gestão de empréstimos com o {app_name}. Organize clientes, contratos, parcelas, vencimentos e cobranças em um só lugar: {url}'**
  String share_app_description(Object app_name, Object url);

  /// No description provided for @share_app_description_without_url.
  ///
  /// In pt, this message translates to:
  /// **'Conheça o {app_name}, uma solução moderna para organizar clientes, contratos, parcelas, vencimentos e cobranças.'**
  String share_app_description_without_url(Object app_name);

  /// No description provided for @version.
  ///
  /// In pt, this message translates to:
  /// **'Versão {number}'**
  String version(Object number);

  /// No description provided for @about_app_description_1.
  ///
  /// In pt, this message translates to:
  /// **'O {app_name} é uma plataforma moderna de gestão de empréstimos pessoais, criada para organizar toda a operação em um só lugar. Cadastre clientes e acompanhe contratos, parcelas e vencimentos com clareza, desde a liberação do crédito até a quitação.'**
  String about_app_description_1(Object app_name);

  /// No description provided for @about_app_description_2.
  ///
  /// In pt, this message translates to:
  /// **'Com controle por regiões, gestão de cobranças, integração bancária e comunicação pelo WhatsApp, o {app_name} ajuda sua equipe a reduzir atrasos, preservar o histórico de cada cliente e tomar decisões com informações confiáveis.'**
  String about_app_description_2(Object app_name);

  /// No description provided for @about_app_description_3.
  ///
  /// In pt, this message translates to:
  /// **'Empreste com controle. Cobre com eficiência. Cresça com segurança.'**
  String get about_app_description_3;

  /// No description provided for @powered_by.
  ///
  /// In pt, this message translates to:
  /// **'Desenvolvido por'**
  String get powered_by;

  /// No description provided for @app_locked_description.
  ///
  /// In pt, this message translates to:
  /// **'O acesso ao aplicativo está bloqueado. Confirme sua identidade para continuar.'**
  String get app_locked_description;

  /// No description provided for @unlock.
  ///
  /// In pt, this message translates to:
  /// **'Desbloquear'**
  String get unlock;

  /// No description provided for @app_locked.
  ///
  /// In pt, this message translates to:
  /// **'{app_name} bloqueado'**
  String app_locked(Object app_name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
