import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:money/money.dart';
import 'package:money/presentation/screens/notifications_screen.dart';

class HomePageView extends StatefulWidget {
  final DesktopDestination destination;
  final UsersScreenController? usersController;
  final ValueChanged<bool>? onUsersDetailChanged;
  final RegionsScreenController? regionsController;
  final ValueChanged<bool>? onRegionsDetailChanged;
  final ClientsScreenController? clientsController;
  final BankingApiScreenController? bankingApiController;
  final ReportScreenController? reportController;
  final FinancialGoalsScreenController? financialGoalsController;
  final RoutesScreenController? routesController;
  final TutorialGuideController? tutorialController;
  final bool tutorialMode;
  final ValueChanged<bool>? onReportHistoryChanged;
  final ValueChanged<bool>? onClientsDetailChanged;
  final VoidCallback? onLoanCreated;
  final Future<void> Function() onLogout;

  const HomePageView({
    super.key,
    required this.destination,
    this.usersController,
    this.onUsersDetailChanged,
    this.regionsController,
    this.onRegionsDetailChanged,
    this.clientsController,
    this.bankingApiController,
    this.reportController,
    this.financialGoalsController,
    this.routesController,
    this.tutorialController,
    this.tutorialMode = false,
    this.onReportHistoryChanged,
    this.onClientsDetailChanged,
    this.onLoanCreated,
    required this.onLogout,
  });

  @override
  State<HomePageView> createState() => _HomePageViewState();
}

class _HomePageViewState extends State<HomePageView> {
  // Clientes também é mantido preparado porque o cadastro pode ser aberto
  // diretamente pelo menu central a partir de qualquer destino.
  final Set<DesktopDestination> _visited = {
    DesktopDestination.clients,
    DesktopDestination.users,
  };

  @override
  void initState() {
    super.initState();
    _visited.add(widget.destination);
  }

  @override
  void didUpdateWidget(covariant HomePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.destination);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.destination.index,
      sizing: StackFit.expand,
      children: [
        for (final DesktopDestination destination in DesktopDestination.values)
          _visited.contains(destination)
              ? _buildDestination(
                  context,
                  destination,
                  active: destination == widget.destination,
                )
              : const SizedBox.expand(),
      ],
    );
  }

  Widget _buildDestination(
    BuildContext context,
    DesktopDestination destination, {
    required bool active,
  }) {
    switch (destination) {
      case DesktopDestination.home:
        return DashboardScreen(
          active: active,
          tutorialMode: widget.tutorialMode,
          tutorialController: widget.tutorialController,
        );
      case DesktopDestination.loans:
        return TransactionScreen(
          active: active,
          tutorialMode: widget.tutorialMode,
        );
      case DesktopDestination.ai:
        return const ChatScreen();
      case DesktopDestination.settings:
        return BlocProvider(
          create: (_) => SettingCubit()..init(),
          child: SettingScreen(),
        );
      case DesktopDestination.profile:
        return ProfileScreen(onLogout: widget.onLogout);
      case DesktopDestination.users:
        return UsersScreen(
          active: active,
          controller: widget.usersController,
          onDetailVisibilityChanged: widget.onUsersDetailChanged,
        );
      case DesktopDestination.regions:
        return RegionsScreen(
          active: active,
          controller: widget.regionsController,
          onDetailVisibilityChanged: widget.onRegionsDetailChanged,
        );
      case DesktopDestination.clients:
        return ClientsScreen(
          active: active,
          controller: widget.clientsController,
          tutorialController: widget.tutorialController,
          tutorialMode: widget.tutorialMode,
          onDetailVisibilityChanged: widget.onClientsDetailChanged,
          onLoanCreated: widget.onLoanCreated,
        );
      case DesktopDestination.financialGoals:
        return FinancialGoalsScreen(
          active: active,
          controller: widget.financialGoalsController,
        );
      case DesktopDestination.routes:
        return RoutesScreen(
          active: active,
          controller: widget.routesController,
        );
      case DesktopDestination.reports:
        return ReportScreen(
          controller: widget.reportController,
          onHistoryVisibilityChanged: widget.onReportHistoryChanged,
        );
      case DesktopDestination.bankingApi:
        return BankingApiScreen(
          active: active,
          controller: widget.bankingApiController,
        );
      case DesktopDestination.whatsappApi:
        return WhatsappApiScreen(active: active);
      case DesktopDestination.conferences:
        return ConferencesScreen(active: active);
      case DesktopDestination.notifications:
        return NotificationsScreen(active: active);
      case DesktopDestination.support:
        return _MobileEmptyDestination(title: context.tr!.sidebar_support);
    }
  }
}

class _MobileEmptyDestination extends StatelessWidget {
  final String title;

  const _MobileEmptyDestination({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HomeAppBar(title: title, leading: const AppSidebarMenuButton()),
      body: const SizedBox.expand(),
    );
  }
}
