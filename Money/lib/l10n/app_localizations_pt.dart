// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get app_name => 'Money';

  @override
  String get sidebar_slogan => 'Gestão de Empréstimos Pessoais';

  @override
  String get ai => 'Chat Financeiro';

  @override
  String get desktop_home => 'Home';

  @override
  String get desktop_people => 'Pessoas';

  @override
  String get desktop_integrations => 'Integrações';

  @override
  String get profile => 'Perfil';

  @override
  String get notifications => 'Notificações';

  @override
  String get settings => 'Configurações';

  @override
  String get menu => 'Menu';

  @override
  String get sidebar_users => 'Usuários';

  @override
  String get sidebar_regions => 'Regiões';

  @override
  String get sidebar_clients => 'Clientes';

  @override
  String get sidebar_loans => 'Empréstimos';

  @override
  String get sidebar_financial_goals => 'Metas';

  @override
  String get sidebar_banking_api => 'API Sicredi';

  @override
  String get sidebar_whatsapp_api => 'API Whatsapp';

  @override
  String get sidebar_reports => 'Relatórios';

  @override
  String get sidebar_support => 'Suporte';

  @override
  String get sidebar_logout => 'Logout';

  @override
  String get new_loan => 'Novo Empréstimo';

  @override
  String get new_loan_description => 'Registre um novo empréstimo.';

  @override
  String get register_client => 'Cadastrar Cliente';

  @override
  String get register_client_description => 'Adicione um novo cliente.';

  @override
  String get theme_mode => 'Tema';

  @override
  String get app_preferences => 'Preferências do aplicativo';

  @override
  String get light_theme => 'Claro';

  @override
  String get dark_theme => 'Escuro';

  @override
  String get app_lock => 'Acesso com biometria';

  @override
  String app_lock_description(Object app_name) {
    return 'Use sua biometria para entrar com segurança no $app_name';
  }

  @override
  String lock_app_localized_reason(Object app_name) {
    return 'Confirme sua biometria para ativar o acesso rápido ao $app_name.';
  }

  @override
  String unlock_app_localized_reason(Object app_name) {
    return 'O acesso biométrico não será mais solicitado ao abrir o $app_name.';
  }

  @override
  String get screenshot => 'Capturas de tela';

  @override
  String get enable_screenshot_description =>
      'Permitir capturas de tela dentro do aplicativo.';

  @override
  String get enable_screenshot_localized_reason =>
      'Confirme sua identidade para permitir capturas de tela.';

  @override
  String get disable_screenshot_localized_reason =>
      'Confirme sua identidade para bloquear capturas de tela.';

  @override
  String get security => 'Segurança';

  @override
  String about_app(Object app_name) {
    return 'Sobre o $app_name';
  }

  @override
  String share_app(Object app_name) {
    return 'Compartilhar o $app_name';
  }

  @override
  String share_app_description(Object app_name, Object url) {
    return 'Simplifique a gestão de empréstimos com o $app_name. Organize clientes, contratos, parcelas, vencimentos e cobranças em um só lugar: $url';
  }

  @override
  String share_app_description_without_url(Object app_name) {
    return 'Conheça o $app_name, uma solução moderna para organizar clientes, contratos, parcelas, vencimentos e cobranças.';
  }

  @override
  String version(Object number) {
    return 'Versão $number';
  }

  @override
  String about_app_description_1(Object app_name) {
    return 'O $app_name é uma plataforma moderna de gestão de empréstimos pessoais, criada para organizar toda a operação em um só lugar. Cadastre clientes e acompanhe contratos, parcelas e vencimentos com clareza, desde a liberação do crédito até a quitação.';
  }

  @override
  String about_app_description_2(Object app_name) {
    return 'Com controle por regiões, gestão de cobranças, integração bancária e comunicação pelo WhatsApp, o $app_name ajuda sua equipe a reduzir atrasos, preservar o histórico de cada cliente e tomar decisões com informações confiáveis.';
  }

  @override
  String get about_app_description_3 =>
      'Empreste com controle. Cobre com eficiência. Cresça com segurança.';

  @override
  String get powered_by => 'Desenvolvido por';

  @override
  String get app_locked_description =>
      'O acesso ao aplicativo está bloqueado. Confirme sua identidade para continuar.';

  @override
  String get unlock => 'Desbloquear';

  @override
  String app_locked(Object app_name) {
    return '$app_name bloqueado';
  }
}
