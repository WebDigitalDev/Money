import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:money/money.dart';
import 'package:money/data/services/app_notification_service.dart';

class HomeScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  final TutorialGuideController? tutorialController;

  const HomeScreen({
    super.key,
    required this.onLogout,
    this.tutorialController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _desktopBreakpoint = 1024;

  final ZoomDrawerController _sidebarController = ZoomDrawerController();
  final UsersScreenController _usersController = UsersScreenController();
  final RegionsScreenController _regionsController = RegionsScreenController();
  final ClientsScreenController _clientsController = ClientsScreenController();
  final BankingApiScreenController _bankingApiController =
      BankingApiScreenController();
  final ReportScreenController _reportController = ReportScreenController();
  final FinancialGoalsScreenController _financialGoalsController =
      FinancialGoalsScreenController();
  final RoutesScreenController _routesController = RoutesScreenController();
  DesktopDestination _desktopDestination = DesktopDestination.home;
  bool _mobileSubpageOpen = false;
  bool _reportHistoryOpen = false;
  bool _desktopProfileDialogOpen = false;
  BuildContext? _tutorialQuickActionsContext;
  bool _tutorialQuickActionsOpening = false;
  StreamSubscription<AppNotification>? _notificationSubscription;
  OverlayEntry? _notificationToast;
  Timer? _notificationToastTimer;

  void _showNotificationToast(AppNotification event) {
    if (!mounted) return;
    _notificationToastTimer?.cancel();
    _notificationToast?.remove();
    final desktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    final colors = context.colors;
    _notificationToast = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.paddingOf(overlayContext).top + 12,
        left: desktop ? null : 12,
        right: desktop ? 18 : 12,
        width: desktop ? 350 : null,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Material(
              color: colors.surface,
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  _notificationToast?.remove();
                  _notificationToast = null;
                  _selectSidebarDestination(DesktopDestination.notifications);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    children: [
                      Icon(
                        event.kind == 'PAYMENT'
                            ? Icons.pix
                            : Icons.flag_outlined,
                        size: 23,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              event.title,
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              event.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        icon: const Icon(Icons.close, size: 17),
                        onPressed: () {
                          _notificationToast?.remove();
                          _notificationToast = null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_notificationToast!);
    _notificationToastTimer = Timer(const Duration(seconds: 6), () {
      _notificationToast?.remove();
      _notificationToast = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _attachTutorialController(widget.tutorialController);
    _notificationSubscription = AppNotificationService.instance.alerts.listen(
      _showNotificationToast,
    );
    unawaited(AppNotificationService.instance.start());
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tutorialController == widget.tutorialController) return;
    _detachTutorialController(oldWidget.tutorialController);
    _attachTutorialController(widget.tutorialController);
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _notificationToastTimer?.cancel();
    _notificationToast?.remove();
    AppNotificationService.instance.stop();
    _detachTutorialController(widget.tutorialController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop:
          _desktopDestination == DesktopDestination.home &&
          !_mobileSubpageOpen &&
          !_reportHistoryOpen,
      onPopInvokedWithResult: _handleSystemBack,
      child: BlocBuilder<HomeCubit, HomeState>(
        buildWhen: (previous, current) => current.runtimeType == HomeInitial,
        builder: (BuildContext context, HomeState state) {
          if (state is HomeInitial) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final bool useDesktopLayout =
                    kIsWeb && constraints.maxWidth >= _desktopBreakpoint;

                if (useDesktopLayout) {
                  return AppSidebarScope(
                    openMenu: _openMenu,
                    openProfile: _openProfile,
                    openConferences: _openConferences,
                    openClient: _openClient,
                    openNotifications: () => _selectDesktopDestination(
                      DesktopDestination.notifications,
                    ),
                    backFromNotifications: () =>
                        _selectDesktopDestination(DesktopDestination.home),
                    child: DesktopHomeLayout(
                      activeDestination: _desktopDestination,
                      onDestinationSelected: _selectDesktopDestination,
                      onLogout: widget.onLogout,
                      tutorialController: widget.tutorialController,
                      tutorialMode:
                          widget.tutorialController?.restrictData == true,
                      clientsController: _clientsController,
                      routesController: _routesController,
                      onClientsDetailChanged: _onSubpageChanged,
                      onLoanCreated: _handleLoanCreated,
                    ),
                  );
                }

                return ZoomDrawer(
                  controller: _sidebarController,
                  angle: 0,
                  borderRadius: 40,
                  menuScreenWidth: MediaQuery.sizeOf(context).width,
                  slideWidth: MediaQuery.sizeOf(context).width * 0.72,
                  mainScreenScale: 0.18,
                  showShadow: true,
                  moveMenuScreen: false,
                  shadowLayer1Color: Colors.black.withValues(alpha: 0.18),
                  shadowLayer2Color: Colors.black.withValues(alpha: 0.10),
                  menuBackgroundColor: Colors.transparent,
                  drawerShadowsBackgroundColor: Colors.transparent,
                  duration: const Duration(milliseconds: 180),
                  reverseDuration: const Duration(milliseconds: 180),
                  openCurve: Curves.easeOutCubic,
                  closeCurve: Curves.easeInOutCubic,
                  isRtl: context.isRtl,
                  menuScreen: AppSidebarMenu(
                    onOpenUsers: () =>
                        _selectSidebarDestination(DesktopDestination.users),
                    onOpenRegions: () =>
                        _selectSidebarDestination(DesktopDestination.regions),
                    onOpenClients: () =>
                        _selectSidebarDestination(DesktopDestination.clients),
                    onOpenLoans: () =>
                        _selectSidebarDestination(DesktopDestination.loans),
                    onOpenFinancialGoals: () => _selectSidebarDestination(
                      DesktopDestination.financialGoals,
                    ),
                    onOpenRoutes: () =>
                        _selectSidebarDestination(DesktopDestination.routes),
                    onOpenReports: () =>
                        _selectSidebarDestination(DesktopDestination.reports),
                    onOpenBankingApi: () => _selectSidebarDestination(
                      DesktopDestination.bankingApi,
                    ),
                    onOpenWhatsappApi: () => _selectSidebarDestination(
                      DesktopDestination.whatsappApi,
                    ),
                    onLogout: widget.onLogout,
                  ),
                  mainScreen: AppSidebarScope(
                    openMenu: _openMenu,
                    openProfile: _openProfile,
                    openConferences: _openConferences,
                    openNotifications: () => _selectSidebarDestination(
                      DesktopDestination.notifications,
                    ),
                    backFromNotifications: () => _selectMobileDestination(0),
                    openClient: _openClient,
                    child: Scaffold(
                      extendBody: true,
                      resizeToAvoidBottomInset: false,
                      body: NetworkAwareContent(
                        showAppBar: true,
                        child: HomePageView(
                          destination: _desktopDestination,
                          usersController: _usersController,
                          onUsersDetailChanged: _onUsersDetailChanged,
                          regionsController: _regionsController,
                          onRegionsDetailChanged: _onSubpageChanged,
                          clientsController: _clientsController,
                          bankingApiController: _bankingApiController,
                          reportController: _reportController,
                          financialGoalsController: _financialGoalsController,
                          routesController: _routesController,
                          tutorialController: widget.tutorialController,
                          tutorialMode:
                              widget.tutorialController?.restrictData == true,
                          onReportHistoryChanged: _onReportHistoryChanged,
                          onClientsDetailChanged: _onSubpageChanged,
                          onLoanCreated: _handleLoanCreated,
                          onLogout: widget.onLogout,
                        ),
                      ),
                      floatingActionButton: _mobileSubpageOpen
                          ? null
                          : _buildCentralAction(),
                      floatingActionButtonLocation:
                          FloatingActionButtonLocation.centerDocked,
                      bottomNavigationBar: _mobileSubpageOpen
                          ? null
                          : HomeBottomNavigationBar(
                              activeIndex:
                                  _desktopDestination ==
                                      DesktopDestination.profile
                                  ? -1
                                  : state.activeIndex,
                              onTap: _selectMobileDestination,
                              chatButtonKey:
                                  widget.tutorialController?.active == true
                                  ? widget
                                        .tutorialController!
                                        .mobileChatButtonKey
                                  : null,
                            ),
                    ),
                  ),
                );
              },
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  void _openMenu() {
    _sidebarController.toggle?.call();
  }

  void _openProfile() {
    _selectSidebarDestination(DesktopDestination.profile);
  }

  void _openConferences() {
    _selectSidebarDestination(DesktopDestination.conferences);
  }

  void _openClient(int clientId) {
    _selectSidebarDestination(DesktopDestination.clients);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _clientsController.openDetail(clientId);
    });
  }

  Widget? _buildCentralAction() {
    if (_desktopDestination == DesktopDestination.reports &&
        _reportHistoryOpen) {
      return HomeFloatingActionButton(
        key: const ValueKey('export_history'),
        onPressed: _reportController.exportCurrent,
        iconData: Icons.file_download_outlined,
      );
    }

    if (_desktopDestination == DesktopDestination.financialGoals) {
      if (AuthService().currentSession?.administrator != true) return null;
      return HomeFloatingActionButton(
        key: const ValueKey('create_financial_goal'),
        onPressed: _financialGoalsController.openCreate,
        iconData: Icons.add_task_rounded,
      );
    }

    if (_desktopDestination == DesktopDestination.routes) {
      final AuthSession? session = AuthService().currentSession;
      if (session?.collector == true &&
          session?.administrator != true &&
          session?.canEdit != true) {
        return null;
      }
      return HomeFloatingActionButton(
        key: const ValueKey('create_collection_route'),
        onPressed: _routesController.openCreate,
        iconData: Icons.add_road_rounded,
      );
    }

    if (_desktopDestination == DesktopDestination.users) {
      return HomeFloatingActionButton(
        key: const ValueKey('create_user'),
        onPressed: _usersController.openCreate,
        iconData: Icons.person_add_alt_1_rounded,
      );
    }

    final AuthSession? session = AuthService().currentSession;
    if (_desktopDestination == DesktopDestination.regions &&
        session?.canManageRegions == true) {
      return HomeFloatingActionButton(
        key: const ValueKey('create_region'),
        onPressed: _regionsController.openCreate,
        iconData: Icons.add_location_alt_rounded,
      );
    }

    if (_desktopDestination == DesktopDestination.clients &&
        (session?.administrator == true || session?.canEdit == true)) {
      return HomeFloatingActionButton(
        key: widget.tutorialController?.active == true
            ? widget.tutorialController!.mobileCentralActionKey
            : const ValueKey('create_client'),
        onPressed: _clientsController.openCreate,
        iconData: Icons.person_add_alt_1_rounded,
      );
    }

    if (_desktopDestination == DesktopDestination.bankingApi &&
        session?.administrator == true &&
        session?.userId == 1) {
      return HomeFloatingActionButton(
        key: const ValueKey('create_bank_account'),
        onPressed: _bankingApiController.openCreate,
        iconData: Icons.add_card_rounded,
      );
    }

    return HomeFloatingActionButton(
      key: widget.tutorialController?.active == true
          ? widget.tutorialController!.mobileCentralActionKey
          : const ValueKey('quick_actions'),
      onNewLoan: _openClientsForNewLoan,
      onRegisterClient: _openClientRegistration,
    );
  }

  void _openClientsForNewLoan() {
    _selectSidebarDestination(DesktopDestination.clients);
  }

  void _openClientRegistration() {
    _selectSidebarDestination(DesktopDestination.clients);
    _clientsController.openCreate();
  }

  void _attachTutorialController(TutorialGuideController? controller) {
    if (controller == null) return;
    controller.addListener(_handleTutorialChanged);
    controller.attachHome(
      owner: this,
      openLoansPage: () => _selectDesktopDestination(DesktopDestination.loans),
      openClientsPage: _openClientsForNewLoan,
      openMobileQuickActions: _openTutorialMobileQuickActions,
      selectMobileNewLoan: _selectTutorialMobileNewLoan,
      openMobileSidebar: _openTutorialMobileSidebar,
      closeMobileSidebar: _closeMenu,
      ensureTutorialClient: () => _clientsController.ensureTutorialClient(),
      openTutorialClient: () => _clientsController.openTutorialClient(),
      returnToDashboard: _returnTutorialToDashboard,
    );
  }

  void _detachTutorialController(TutorialGuideController? controller) {
    if (controller == null) return;
    controller.removeListener(_handleTutorialChanged);
    controller.detachHome(this);
  }

  void _handleTutorialChanged() {
    if (mounted) setState(() {});
  }

  void _openTutorialMobileQuickActions() {
    if (!mounted ||
        _tutorialQuickActionsContext != null ||
        _tutorialQuickActionsOpening) {
      return;
    }
    _tutorialQuickActionsOpening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _tutorialQuickActionsOpening = false;
        return;
      }
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          elevation: 0,
          isScrollControlled: true,
          enableDrag: false,
          isDismissible: false,
          sheetAnimationStyle: const AnimationStyle(
            duration: Duration(milliseconds: 180),
            reverseDuration: Duration(milliseconds: 140),
          ),
          builder: (sheetContext) {
            _tutorialQuickActionsContext = sheetContext;
            return MenuModalBottomSheet(
              newLoanKey: widget.tutorialController?.mobileNewLoanOptionKey,
              onNewLoan: _selectTutorialMobileNewLoan,
              onRegisterClient: () {},
            );
          },
        ).whenComplete(() {
          _tutorialQuickActionsContext = null;
          _tutorialQuickActionsOpening = false;
        }),
      );
    });
  }

  void _selectTutorialMobileNewLoan() {
    _openClientsForNewLoan();
    final BuildContext? sheetContext = _tutorialQuickActionsContext;
    if (sheetContext != null && Navigator.of(sheetContext).canPop()) {
      Navigator.of(sheetContext).pop();
    }
  }

  void _openTutorialMobileSidebar() {
    if (_sidebarController.isOpen?.call() ?? false) return;
    _sidebarController.open?.call();
  }

  Future<void> _returnTutorialToDashboard() async {
    final BuildContext? sheetContext = _tutorialQuickActionsContext;
    if (sheetContext != null && Navigator.of(sheetContext).canPop()) {
      Navigator.of(sheetContext).pop();
    }
    _clientsController.closeDetail();
    if (!mounted) return;
    _selectSidebarDestination(DesktopDestination.home);
    await WidgetsBinding.instance.endOfFrame;
  }

  void _handleLoanCreated() {
    _selectSidebarDestination(DesktopDestination.loans);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showAppCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Empréstimo criado'),
            content: const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('O novo empréstimo foi cadastrado com sucesso.'),
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _closeMenu() {
    if (_sidebarController.isOpen?.call() ?? false) {
      _sidebarController.close?.call();
    }
  }

  void _selectSidebarDestination(DesktopDestination destination) {
    if (!_canAccessDestination(destination)) return;

    final bool destinationChanged =
        _desktopDestination != destination || _mobileSubpageOpen;
    if (_mobileSubpageOpen) {
      _closeCurrentSubpage();
    }
    if (_reportHistoryOpen && destination != DesktopDestination.reports) {
      _reportController.closeHistory();
    }
    if (destinationChanged) {
      setState(() {
        _desktopDestination = destination;
        _mobileSubpageOpen = false;
      });
    }

    final int mobileIndex = switch (destination) {
      DesktopDestination.loans => 1,
      DesktopDestination.ai => 2,
      DesktopDestination.settings => 3,
      _ => 0,
    };
    final HomeState currentState = context.read<HomeCubit>().state;
    if (currentState is HomeInitial &&
        currentState.activeIndex != mobileIndex) {
      context.read<HomeCubit>().onPageChanged(index: mobileIndex);
    }

    if (destinationChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeMenu();
      });
    } else {
      _closeMenu();
    }
  }

  void _selectMobileDestination(int index) {
    if (_mobileSubpageOpen) {
      _closeCurrentSubpage();
    }
    if (_reportHistoryOpen) {
      _reportController.closeHistory();
    }
    final DesktopDestination destination = switch (index) {
      1 => DesktopDestination.loans,
      2 => DesktopDestination.ai,
      3 => DesktopDestination.settings,
      _ => DesktopDestination.home,
    };

    setState(() {
      _desktopDestination = destination;
      _mobileSubpageOpen = false;
    });
    context.read<HomeCubit>().onPageChanged(index: index);
  }

  void _selectDesktopDestination(DesktopDestination destination) {
    if (!_canAccessDestination(destination)) return;

    if (destination == DesktopDestination.profile) {
      if (!_desktopProfileDialogOpen) unawaited(_openDesktopProfileDialog());
      return;
    }

    if (_desktopDestination != destination) {
      setState(() => _desktopDestination = destination);
    }

    final int mobileIndex = switch (destination) {
      DesktopDestination.loans => 1,
      DesktopDestination.ai => 2,
      DesktopDestination.settings => 3,
      _ => 0,
    };

    final HomeState currentState = context.read<HomeCubit>().state;
    if (currentState is HomeInitial &&
        currentState.activeIndex == mobileIndex) {
      return;
    }
    context.read<HomeCubit>().onPageChanged(index: mobileIndex);
  }

  Future<void> _openDesktopProfileDialog() async {
    _desktopProfileDialogOpen = true;
    try {
      await showAppDialog<void>(
        context: context,
        title: 'Meu perfil',
        subtitle: 'Consulte seus dados e regiões de acesso.',
        icon: Icons.person_outline_rounded,
        maxWidth: 520,
        maxHeight: 600,
        barrierDismissible: true,
        builder: (dialogContext) => ProfileScreen(
          showAppBar: false,
          compact: true,
          onLogout: () async {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
            await widget.onLogout();
          },
        ),
      );
    } finally {
      _desktopProfileDialogOpen = false;
    }
  }

  bool _canAccessDestination(DesktopDestination destination) {
    if (destination != DesktopDestination.bankingApi &&
        destination != DesktopDestination.conferences) {
      return true;
    }
    return AuthService().currentSession?.administrator == true;
  }

  void _onUsersDetailChanged(bool isOpen) {
    _onSubpageChanged(isOpen);
  }

  void _onSubpageChanged(bool isOpen) {
    if (!mounted) return;
    if (_mobileSubpageOpen == isOpen) return;
    setState(() => _mobileSubpageOpen = isOpen);
  }

  void _onReportHistoryChanged(bool isOpen) {
    if (!mounted || _reportHistoryOpen == isOpen) return;
    setState(() => _reportHistoryOpen = isOpen);
  }

  void _handleSystemBack(bool didPop, void result) {
    if (didPop) return;
    if (_mobileSubpageOpen && _closeCurrentSubpage()) return;
    if (_reportHistoryOpen && _reportController.closeHistory()) return;
    if (_desktopDestination != DesktopDestination.home) {
      _selectMobileDestination(0);
    }
  }

  bool _closeCurrentSubpage() {
    return switch (_desktopDestination) {
      DesktopDestination.users => _usersController.closeDetail(),
      DesktopDestination.regions => _regionsController.closeDetail(),
      DesktopDestination.clients => _clientsController.closeDetail(),
      _ => false,
    };
  }
}
