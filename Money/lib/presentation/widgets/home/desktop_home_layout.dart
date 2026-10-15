import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:money/money.dart';
import 'package:money/presentation/screens/notifications_screen.dart';

const double _desktopContentMaxWidth = 1400;
const double _desktopHorizontalPadding = 24;

enum DesktopDestination {
  home,
  loans,
  regions,
  clients,
  users,
  financialGoals,
  routes,
  reports,
  bankingApi,
  whatsappApi,
  support,
  settings,
  ai,
  profile,
  conferences,
  notifications,
}

class DesktopHomeLayout extends StatelessWidget {
  final DesktopDestination activeDestination;
  final ValueChanged<DesktopDestination> onDestinationSelected;
  final Future<void> Function() onLogout;
  final bool? administrator;
  final TutorialGuideController? tutorialController;
  final bool tutorialMode;
  final ClientsScreenController? clientsController;
  final RoutesScreenController? routesController;
  final ValueChanged<bool>? onClientsDetailChanged;
  final VoidCallback? onLoanCreated;

  const DesktopHomeLayout({
    super.key,
    required this.activeDestination,
    required this.onDestinationSelected,
    required this.onLogout,
    this.administrator,
    this.tutorialController,
    this.tutorialMode = false,
    this.clientsController,
    this.routesController,
    this.onClientsDetailChanged,
    this.onLoanCreated,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAdministrator =
        administrator ?? AuthService().currentSession?.administrator ?? false;
    final DesktopDestination visibleDestination =
        activeDestination == DesktopDestination.profile ||
            activeDestination == DesktopDestination.ai
        ? DesktopDestination.home
        : (activeDestination == DesktopDestination.bankingApi ||
                  activeDestination == DesktopDestination.whatsappApi ||
                  activeDestination == DesktopDestination.conferences) &&
              !isAdministrator
        ? DesktopDestination.home
        : activeDestination;

    return _DesktopChatOverlay(
      initiallyOpen: activeDestination == DesktopDestination.ai,
      tutorialController: tutorialController,
      child: ColoredBox(
        color: context.colors.background,
        child: Column(
          children: [
            _DesktopHeader(
              activeDestination: visibleDestination,
              onDestinationSelected: onDestinationSelected,
              administrator: isAdministrator,
              tutorialController: tutorialController,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _desktopHorizontalPadding,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _desktopContentMaxWidth,
                    ),
                    child: NetworkAwareContent(
                      showAppBar: false,
                      child: _DesktopPage(
                        destination: visibleDestination,
                        onLogout: onLogout,
                        onNewLoan: () =>
                            onDestinationSelected(DesktopDestination.clients),
                        tutorialController: tutorialController,
                        tutorialMode: tutorialMode,
                        clientsController: clientsController,
                        routesController: routesController,
                        onClientsDetailChanged: onClientsDetailChanged,
                        onLoanCreated: onLoanCreated,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  final DesktopDestination activeDestination;
  final ValueChanged<DesktopDestination> onDestinationSelected;
  final bool? administrator;
  final TutorialGuideController? tutorialController;

  const _DesktopHeader({
    required this.activeDestination,
    required this.onDestinationSelected,
    required this.administrator,
    this.tutorialController,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Column(
        children: [
          SizedBox(
            height: 66,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _desktopHorizontalPadding,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _desktopContentMaxWidth,
                  ),
                  child: Row(
                    children: [
                      Image.asset(
                        AppImages.money,
                        width: 150,
                        height: 49,
                        fit: BoxFit.contain,
                        alignment: AlignmentDirectional.centerStart,
                      ),
                      const Spacer(),
                      if (administrator == true) ...[
                        _HeaderActionButton(
                          tooltip: 'Conferências',
                          isActive:
                              activeDestination ==
                              DesktopDestination.conferences,
                          onPressed: () => onDestinationSelected(
                            DesktopDestination.conferences,
                          ),
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.fact_check_outlined,
                                size: 24,
                                color: context.colors.primary,
                              ),
                              PositionedDirectional(
                                top: 1,
                                end: 1,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: context.colors.secondary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: context.colors.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _HeaderActionButton(
                        tooltip: 'Notificações',
                        isActive: false,
                        onPressed: () => onDestinationSelected(
                          DesktopDestination.notifications,
                        ),
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          size: 24,
                          color: context.colors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ProfileButton(
                        isActive:
                            activeDestination == DesktopDestination.profile,
                        onPressed: () =>
                            onDestinationSelected(DesktopDestination.profile),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: context.colors.divider),
          _DesktopNavigationBar(
            activeDestination: activeDestination,
            onDestinationSelected: onDestinationSelected,
            administrator: administrator,
            tutorialController: tutorialController,
          ),
        ],
      ),
    );
  }
}

class _DesktopChatOverlay extends StatefulWidget {
  final Widget child;
  final bool initiallyOpen;
  final TutorialGuideController? tutorialController;

  const _DesktopChatOverlay({
    required this.child,
    required this.initiallyOpen,
    this.tutorialController,
  });

  @override
  State<_DesktopChatOverlay> createState() => _DesktopChatOverlayState();
}

class _DesktopChatOverlayState extends State<_DesktopChatOverlay> {
  bool _isOpen = false;
  bool _wasOpened = false;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.initiallyOpen;
    _wasOpened = widget.initiallyOpen;
  }

  @override
  void didUpdateWidget(covariant _DesktopChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.initiallyOpen && widget.initiallyOpen) {
      _isOpen = true;
      _wasOpened = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size viewport = MediaQuery.sizeOf(context);
    final double panelWidth = (viewport.width - 48).clamp(360.0, 410.0);
    final double panelHeight = (viewport.height - 200).clamp(380.0, 590.0);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_wasOpened)
            PositionedDirectional(
              end: 24,
              bottom: 92,
              child: Offstage(
                offstage: !_isOpen,
                child: Material(
                  key: const ValueKey('desktop_chat_panel'),
                  color: context.colors.surface,
                  elevation: 18,
                  shadowColor: Colors.black.withValues(alpha: 0.28),
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: panelWidth,
                    height: panelHeight,
                    decoration: BoxDecoration(
                      border: Border.all(color: context.colors.divider),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ChatScreen(
                      showAppBar: false,
                      compact: true,
                      onClose: _close,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _DesktopChatButton(
        buttonKey: widget.tutorialController?.active == true
            ? widget.tutorialController!.desktopChatButtonKey
            : null,
        isOpen: _isOpen,
        onPressed: _toggle,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _toggle() {
    setState(() {
      _wasOpened = true;
      _isOpen = !_isOpen;
    });
  }

  void _close() {
    if (!_isOpen) return;
    setState(() => _isOpen = false);
  }
}

class _DesktopChatButton extends StatelessWidget {
  final Key? buttonKey;
  final bool isOpen;
  final VoidCallback onPressed;

  const _DesktopChatButton({
    required this.isOpen,
    required this.onPressed,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      key: buttonKey ?? const ValueKey('desktop_chat_button'),
      heroTag: 'desktop_chat_button',
      tooltip: isOpen
          ? 'Fechar assistente financeira'
          : 'Abrir assistente financeira',
      onPressed: onPressed,
      backgroundColor: context.colors.surface,
      elevation: 7,
      hoverElevation: 10,
      shape: CircleBorder(
        side: BorderSide(color: context.colors.primary, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: Image.asset(
            'assets/images/profile.png',
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

class _DesktopNavigationBar extends StatelessWidget {
  final DesktopDestination activeDestination;
  final ValueChanged<DesktopDestination> onDestinationSelected;
  final bool? administrator;
  final TutorialGuideController? tutorialController;

  const _DesktopNavigationBar({
    required this.activeDestination,
    required this.onDestinationSelected,
    required this.administrator,
    this.tutorialController,
  });

  @override
  Widget build(BuildContext context) {
    final bool isAdministrator =
        administrator ?? AuthService().currentSession?.administrator ?? false;
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _desktopHorizontalPadding,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _desktopContentMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        _DesktopNavItem(
                          label: context.tr!.desktop_home,
                          icon: Icons.home_outlined,
                          isActive:
                              activeDestination == DesktopDestination.home,
                          onTap: () =>
                              onDestinationSelected(DesktopDestination.home),
                        ),
                        _DesktopNavItem(
                          key: tutorialController?.desktopLoansTabKey,
                          label: context.tr!.sidebar_loans,
                          svgIcon: AppIcons.loan,
                          isActive:
                              activeDestination == DesktopDestination.loans,
                          onTap: () =>
                              onDestinationSelected(DesktopDestination.loans),
                        ),
                        _DesktopNavItem(
                          label: context.tr!.sidebar_regions,
                          icon: Icons.location_on_outlined,
                          isActive:
                              activeDestination == DesktopDestination.regions,
                          onTap: () =>
                              onDestinationSelected(DesktopDestination.regions),
                        ),
                        _DesktopSubmenu(
                          label: context.tr!.desktop_people,
                          icon: Icons.groups_2_outlined,
                          activeDestination: activeDestination,
                          destinations: [
                            DesktopDestination.clients,
                            if (isAdministrator) DesktopDestination.users,
                          ],
                          entries: [
                            _DesktopSubmenuEntry(
                              label: context.tr!.sidebar_clients,
                              icon: Icons.person_outline_rounded,
                              destination: DesktopDestination.clients,
                            ),
                            if (isAdministrator)
                              _DesktopSubmenuEntry(
                                label: context.tr!.sidebar_users,
                                icon: Icons.manage_accounts_outlined,
                                destination: DesktopDestination.users,
                              ),
                          ],
                          onSelected: onDestinationSelected,
                        ),
                        _DesktopNavItem(
                          label: context.tr!.sidebar_financial_goals,
                          icon: Icons.track_changes_rounded,
                          isActive:
                              activeDestination ==
                              DesktopDestination.financialGoals,
                          onTap: () => onDestinationSelected(
                            DesktopDestination.financialGoals,
                          ),
                        ),
                        _DesktopNavItem(
                          label: 'Rotas',
                          icon: Icons.route_outlined,
                          isActive:
                              activeDestination == DesktopDestination.routes,
                          onTap: () =>
                              onDestinationSelected(DesktopDestination.routes),
                        ),
                        _DesktopNavItem(
                          label: context.tr!.sidebar_reports,
                          icon: Icons.bar_chart_rounded,
                          isActive:
                              activeDestination == DesktopDestination.reports,
                          onTap: () =>
                              onDestinationSelected(DesktopDestination.reports),
                        ),
                        if (isAdministrator)
                          _DesktopSubmenu(
                            label: context.tr!.desktop_integrations,
                            icon: Icons.hub_outlined,
                            activeDestination: activeDestination,
                            destinations: const [
                              DesktopDestination.bankingApi,
                              DesktopDestination.whatsappApi,
                            ],
                            entries: [
                              _DesktopSubmenuEntry(
                                label: context.tr!.sidebar_banking_api,
                                icon: Icons.account_balance_outlined,
                                destination: DesktopDestination.bankingApi,
                              ),
                              _DesktopSubmenuEntry(
                                label: context.tr!.sidebar_whatsapp_api,
                                icon: Icons.forum_outlined,
                                destination: DesktopDestination.whatsappApi,
                              ),
                            ],
                            onSelected: onDestinationSelected,
                          ),
                        _DesktopNavItem(
                          label: context.tr!.settings,
                          icon: Icons.settings_outlined,
                          isActive:
                              activeDestination == DesktopDestination.settings,
                          onTap: () => onDestinationSelected(
                            DesktopDestination.settings,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? svgIcon;
  final bool isActive;
  final VoidCallback onTap;

  const _DesktopNavItem({
    super.key,
    required this.label,
    this.icon,
    this.svgIcon,
    required this.isActive,
    required this.onTap,
  }) : assert(icon != null || svgIcon != null);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: _DesktopNavSurface(
        label: label,
        icon: icon,
        svgIcon: svgIcon,
        isActive: isActive,
        onTap: onTap,
      ),
    );
  }
}

class _DesktopSubmenu extends StatefulWidget {
  final String label;
  final IconData icon;
  final DesktopDestination activeDestination;
  final List<DesktopDestination> destinations;
  final List<_DesktopSubmenuEntry> entries;
  final ValueChanged<DesktopDestination> onSelected;

  const _DesktopSubmenu({
    required this.label,
    required this.icon,
    required this.activeDestination,
    required this.destinations,
    required this.entries,
    required this.onSelected,
  });

  @override
  State<_DesktopSubmenu> createState() => _DesktopSubmenuState();
}

class _DesktopSubmenuState extends State<_DesktopSubmenu> {
  static const Duration _closeDelay = Duration(milliseconds: 180);

  final MenuController _menuController = MenuController();
  Timer? _closeTimer;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = widget.destinations.contains(
      widget.activeDestination,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: MenuAnchor(
        controller: _menuController,
        alignmentOffset: const Offset(0, 5),
        animated: true,
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(context.colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: 0.18),
          ),
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          fixedSize: const WidgetStatePropertyAll(Size.fromWidth(200)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        menuChildren: widget.entries.map((entry) {
          final bool entryIsActive =
              entry.destination == widget.activeDestination;

          return MenuItemButton(
            onHover: (isHovered) {
              if (isHovered) {
                _cancelScheduledClose();
              } else {
                _scheduleClose();
              }
            },
            onPressed: () => widget.onSelected(entry.destination),
            leadingIcon: Icon(
              entry.icon,
              size: 20,
              color: entryIsActive
                  ? context.colors.primary
                  : context.colors.textSecondary,
            ),
            trailingIcon: entryIsActive
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: context.colors.primary,
                  )
                : const SizedBox(width: 18),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(200, 46)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14),
              ),
              foregroundColor: WidgetStatePropertyAll(
                entryIsActive
                    ? context.colors.primary
                    : context.colors.textPrimary,
              ),
              textStyle: WidgetStatePropertyAll(
                TextStyle(
                  fontSize: 14,
                  fontWeight: entryIsActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              overlayColor: WidgetStatePropertyAll(
                context.colors.primary.withValues(alpha: 0.08),
              ),
            ),
            child: Text(entry.label),
          );
        }).toList(),
        builder: (context, controller, child) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _openMenu(),
            onExit: (_) => _scheduleClose(),
            child: _DesktopNavSurface(
              label: widget.label,
              icon: widget.icon,
              isActive: isActive,
              onTap: _toggleMenu,
              trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ),
          );
        },
      ),
    );
  }

  void _openMenu() {
    _cancelScheduledClose();
    if (!_menuController.isOpen) {
      _menuController.open();
    }
  }

  void _toggleMenu() {
    _cancelScheduledClose();
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(_closeDelay, () {
      if (mounted && _menuController.isOpen) {
        _menuController.close();
      }
    });
  }

  void _cancelScheduledClose() {
    _closeTimer?.cancel();
    _closeTimer = null;
  }
}

class _DesktopNavSurface extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? svgIcon;
  final bool isActive;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _DesktopNavSurface({
    required this.label,
    this.icon,
    this.svgIcon,
    required this.isActive,
    this.onTap,
    this.trailing,
  }) : assert(icon != null || svgIcon != null);

  @override
  Widget build(BuildContext context) {
    final Color contentColor = isActive
        ? Colors.white
        : context.colors.textSecondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                colors: [Color(0xFF4B7D60), Color(0xFF76B475)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: context.colors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (svgIcon != null)
                  SvgIcon(
                    icon: svgIcon!,
                    width: 19,
                    height: 19,
                    color: contentColor,
                  )
                else
                  Icon(icon, size: 19, color: contentColor),
                const SizedBox(width: 7),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: contentColor,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 3),
                  IconTheme(
                    data: IconThemeData(color: contentColor),
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final String tooltip;
  final Widget icon;
  final VoidCallback onPressed;
  final bool isActive;

  const _HeaderActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        backgroundColor: isActive
            ? context.colors.primary.withValues(alpha: 0.13)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: icon,
    );
  }
}

class _ProfileButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onPressed;

  const _ProfileButton({required this.isActive, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr!.profile,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 42, height: 42),
      icon: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.primary,
          shape: BoxShape.circle,
          border: isActive
              ? Border.all(color: context.colors.textPrimary, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: context.colors.primary.withValues(alpha: 0.22),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.person_rounded, color: Colors.white, size: 23),
        ),
      ),
    );
  }
}

class _DesktopSubmenuEntry {
  final String label;
  final IconData icon;
  final DesktopDestination destination;

  const _DesktopSubmenuEntry({
    required this.label,
    required this.icon,
    required this.destination,
  });
}

class _DesktopPage extends StatefulWidget {
  final DesktopDestination destination;
  final Future<void> Function() onLogout;
  final VoidCallback onNewLoan;
  final TutorialGuideController? tutorialController;
  final bool tutorialMode;
  final ClientsScreenController? clientsController;
  final RoutesScreenController? routesController;
  final ValueChanged<bool>? onClientsDetailChanged;
  final VoidCallback? onLoanCreated;

  const _DesktopPage({
    required this.destination,
    required this.onLogout,
    required this.onNewLoan,
    this.tutorialController,
    this.tutorialMode = false,
    this.clientsController,
    this.routesController,
    this.onClientsDetailChanged,
    this.onLoanCreated,
  });

  @override
  State<_DesktopPage> createState() => _DesktopPageState();
}

class _DesktopPageState extends State<_DesktopPage> {
  final Set<DesktopDestination> _visited = {};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.destination);
  }

  @override
  void didUpdateWidget(covariant _DesktopPage oldWidget) {
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
                  destination,
                  active: destination == widget.destination,
                )
              : const SizedBox.expand(),
      ],
    );
  }

  Widget _buildDestination(
    DesktopDestination destination, {
    required bool active,
  }) {
    switch (destination) {
      case DesktopDestination.home:
        return DashboardScreen(
          showAppBar: false,
          active: active,
          tutorialMode: widget.tutorialMode,
        );
      case DesktopDestination.loans:
        return TransactionScreen(
          showAppBar: false,
          active: active,
          tutorialMode: widget.tutorialMode,
          onNewLoan: widget.onNewLoan,
          newLoanButtonKey: widget.tutorialController?.desktopNewLoanButtonKey,
        );
      case DesktopDestination.ai:
        return const ChatScreen(showAppBar: false);
      case DesktopDestination.settings:
        return BlocProvider(
          create: (_) => SettingCubit()..init(),
          child: const SettingScreen(showAppBar: false),
        );
      case DesktopDestination.profile:
        return ProfileScreen(showAppBar: false, onLogout: widget.onLogout);
      case DesktopDestination.users:
        return UsersScreen(showAppBar: false, active: active);
      case DesktopDestination.regions:
        return RegionsScreen(showAppBar: false, active: active);
      case DesktopDestination.clients:
        return ClientsScreen(
          showAppBar: false,
          active: active,
          controller: widget.clientsController,
          tutorialController: widget.tutorialController,
          tutorialMode: widget.tutorialMode,
          onDetailVisibilityChanged: widget.onClientsDetailChanged,
          onLoanCreated: widget.onLoanCreated,
        );
      case DesktopDestination.support:
        return const SizedBox.expand();
      case DesktopDestination.financialGoals:
        return FinancialGoalsScreen(showAppBar: false, active: active);
      case DesktopDestination.routes:
        return RoutesScreen(
          showAppBar: false,
          active: active,
          controller: widget.routesController,
        );
      case DesktopDestination.reports:
        return const ReportScreen(showAppBar: false);
      case DesktopDestination.bankingApi:
        return BankingApiScreen(showAppBar: false, active: active);
      case DesktopDestination.whatsappApi:
        return WhatsappApiScreen(showAppBar: false, active: active);
      case DesktopDestination.conferences:
        return ConferencesScreen(showAppBar: false, active: active);
      case DesktopDestination.notifications:
        return NotificationsScreen(showAppBar: false, active: active);
    }
  }
}
