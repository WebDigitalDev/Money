import 'dart:async';

import 'package:flutter/material.dart';

enum TutorialPhase {
  hidden,
  introduction,
  mobileNavigation,
  walkthrough,
  conclusion,
}

enum TutorialTarget {
  desktopLoansTab,
  desktopNewLoanButton,
  clientSearch,
  desktopNewClientButton,
  mobileCentralAction,
  mobileNewLoanOption,
  tutorialClient,
  clientNewLoanButton,
  desktopChatButton,
  mobileChatButton,
  mobileSidebarMenuButton,
}

class TutorialGuideController extends ChangeNotifier {
  static const String tutorialRegionName = 'TUTORIAL';
  static const String tutorialClientName = 'WEBDIGITAL DEVELOPMENT';

  static bool isTutorialRegionName(String value) {
    final String normalized = _normalizeRegionName(value);
    final String expected = _normalizeRegionName(tutorialRegionName);
    return normalized == expected;
  }

  static String _normalizeRegionName(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '');

  TutorialPhase _phase = TutorialPhase.hidden;
  Object? _homeOwner;
  VoidCallback? _openLoansPage;
  VoidCallback? _openClientsPage;
  VoidCallback? _openMobileQuickActions;
  VoidCallback? _selectMobileNewLoan;
  VoidCallback? _openMobileSidebar;
  VoidCallback? _closeMobileSidebar;
  Future<bool> Function()? _ensureTutorialClient;
  Future<bool> Function()? _openTutorialClient;
  Future<void> Function()? _returnToDashboard;
  bool _usesMobileNavigation = false;
  bool _introductionRequiresUserAction = false;

  TutorialPhase get phase => _phase;
  bool get active => _phase != TutorialPhase.hidden;
  bool get restrictData => active;
  bool get introductionRequiresUserAction => _introductionRequiresUserAction;

  final GlobalKey desktopLoansTabKey = GlobalKey(
    debugLabel: 'tutorial_desktop_loans_tab',
  );
  final GlobalKey desktopNewLoanButtonKey = GlobalKey(
    debugLabel: 'tutorial_desktop_new_loan',
  );
  final GlobalKey clientSearchKey = GlobalKey(
    debugLabel: 'tutorial_client_search',
  );
  final GlobalKey desktopNewClientButtonKey = GlobalKey(
    debugLabel: 'tutorial_desktop_new_client',
  );
  final GlobalKey mobileCentralActionKey = GlobalKey(
    debugLabel: 'tutorial_mobile_central_action',
  );
  final GlobalKey mobileNewLoanOptionKey = GlobalKey(
    debugLabel: 'tutorial_mobile_new_loan_option',
  );
  final GlobalKey tutorialClientKey = GlobalKey(
    debugLabel: 'tutorial_client_webdigital_development',
  );
  final GlobalKey clientRegionKey = GlobalKey(
    debugLabel: 'tutorial_client_region',
  );
  final GlobalKey clientNameKey = GlobalKey(debugLabel: 'tutorial_client_name');
  final GlobalKey clientPhoneKey = GlobalKey(
    debugLabel: 'tutorial_client_phone',
  );
  final GlobalKey clientNewLoanButtonKey = GlobalKey(
    debugLabel: 'tutorial_client_new_loan',
  );
  final GlobalKey desktopChatButtonKey = GlobalKey(
    debugLabel: 'tutorial_desktop_chat_button',
  );
  final GlobalKey mobileChatButtonKey = GlobalKey(
    debugLabel: 'tutorial_mobile_chat_button',
  );
  final GlobalKey mobileSidebarMenuButtonKey = GlobalKey(
    debugLabel: 'tutorial_mobile_sidebar_menu_button',
  );

  void showIntroduction({bool requireUserAction = false}) {
    if (_phase == TutorialPhase.introduction &&
        _introductionRequiresUserAction == requireUserAction) {
      return;
    }
    _introductionRequiresUserAction = requireUserAction;
    _phase = TutorialPhase.introduction;
    notifyListeners();
  }

  void beginWalkthrough({required bool useMobileNavigation}) {
    if (_phase != TutorialPhase.introduction) return;
    _usesMobileNavigation = useMobileNavigation;
    _phase = useMobileNavigation
        ? TutorialPhase.mobileNavigation
        : TutorialPhase.walkthrough;
    notifyListeners();
  }

  void beginFinancialWalkthrough() {
    if (_phase != TutorialPhase.mobileNavigation) return;
    _phase = TutorialPhase.walkthrough;
    notifyListeners();
  }

  Future<void> beginConclusion() async {
    if (_phase != TutorialPhase.walkthrough) return;
    _phase = TutorialPhase.conclusion;
    notifyListeners();
    await _returnToDashboard?.call();
  }

  Future<void> restartWalkthrough() async {
    if (_phase != TutorialPhase.conclusion) return;
    _phase = _usesMobileNavigation
        ? TutorialPhase.mobileNavigation
        : TutorialPhase.walkthrough;
    notifyListeners();
    await _returnToDashboard?.call();
  }

  void complete() {
    if (_phase == TutorialPhase.hidden) return;
    _introductionRequiresUserAction = false;
    _phase = TutorialPhase.hidden;
    notifyListeners();
  }

  void hide() {
    if (_phase == TutorialPhase.hidden) return;
    _introductionRequiresUserAction = false;
    _phase = TutorialPhase.hidden;
    notifyListeners();
  }

  void attachHome({
    required Object owner,
    required VoidCallback openLoansPage,
    required VoidCallback openClientsPage,
    required VoidCallback openMobileQuickActions,
    required VoidCallback selectMobileNewLoan,
    required VoidCallback openMobileSidebar,
    required VoidCallback closeMobileSidebar,
    required Future<bool> Function() ensureTutorialClient,
    required Future<bool> Function() openTutorialClient,
    required Future<void> Function() returnToDashboard,
  }) {
    _homeOwner = owner;
    _openLoansPage = openLoansPage;
    _openClientsPage = openClientsPage;
    _openMobileQuickActions = openMobileQuickActions;
    _selectMobileNewLoan = selectMobileNewLoan;
    _openMobileSidebar = openMobileSidebar;
    _closeMobileSidebar = closeMobileSidebar;
    _ensureTutorialClient = ensureTutorialClient;
    _openTutorialClient = openTutorialClient;
    _returnToDashboard = returnToDashboard;
  }

  void detachHome(Object owner) {
    if (!identical(_homeOwner, owner)) return;
    _homeOwner = null;
    _openLoansPage = null;
    _openClientsPage = null;
    _openMobileQuickActions = null;
    _selectMobileNewLoan = null;
    _openMobileSidebar = null;
    _closeMobileSidebar = null;
    _ensureTutorialClient = null;
    _openTutorialClient = null;
    _returnToDashboard = null;
  }

  void openLoansPage() => _openLoansPage?.call();

  void openClientsPage() => _openClientsPage?.call();

  void openMobileQuickActions() => _openMobileQuickActions?.call();

  void selectMobileNewLoan() => _selectMobileNewLoan?.call();

  void openMobileSidebar() => _openMobileSidebar?.call();

  void closeMobileSidebar() => _closeMobileSidebar?.call();

  Future<bool> ensureTutorialClient() async =>
      await _ensureTutorialClient?.call() ?? false;

  Future<bool> openTutorialClient() async =>
      await _openTutorialClient?.call() ?? false;

  GlobalKey keyFor(TutorialTarget target) => switch (target) {
    TutorialTarget.desktopLoansTab => desktopLoansTabKey,
    TutorialTarget.desktopNewLoanButton => desktopNewLoanButtonKey,
    TutorialTarget.clientSearch => clientSearchKey,
    TutorialTarget.desktopNewClientButton => desktopNewClientButtonKey,
    TutorialTarget.mobileCentralAction => mobileCentralActionKey,
    TutorialTarget.mobileNewLoanOption => mobileNewLoanOptionKey,
    TutorialTarget.tutorialClient => tutorialClientKey,
    TutorialTarget.clientNewLoanButton => clientNewLoanButtonKey,
    TutorialTarget.desktopChatButton => desktopChatButtonKey,
    TutorialTarget.mobileChatButton => mobileChatButtonKey,
    TutorialTarget.mobileSidebarMenuButton => mobileSidebarMenuButtonKey,
  };

  List<GlobalKey> keysFor(TutorialTarget target) => [keyFor(target)];
}
