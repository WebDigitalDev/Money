import 'package:flutter/material.dart';
import 'package:money/money.dart';
import 'package:money/presentation/screens/notifications_screen.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  final Size preferredSize;
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showDefaultActions;

  const HomeAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.showDefaultActions = true,
  }) : preferredSize = const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final AppSidebarScope? navigationScope = AppSidebarScope.maybeOf(context);
    return AppBar(
      backgroundColor: context.colors.bottomNavigationBar,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      leading: leading,
      leadingWidth: leading == null ? null : 40,
      titleSpacing: leading == null ? null : 0,
      title: Row(
        children: [
          SvgIcon(
            icon: AppIcons.dollar,
            width: 26,
            height: 36,
            color: context.colors.primary,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(title, maxLines: 1),
            ),
          ),
        ],
      ),
      actions: [
        ...?actions,
        if (showDefaultActions &&
            AuthService().currentSession?.administrator == true)
          IconButton(
            onPressed: navigationScope?.openConferences ?? () {},
            tooltip: 'Conferências',
            icon: Icon(
              Icons.fact_check_outlined,
              color: context.colors.primary,
              size: 25,
            ),
          ),
        if (showDefaultActions)
          IconButton(
            tooltip: 'Notificações',
            onPressed: () => NotificationsScreen.open(context),
            icon: Icon(
              Icons.notifications_none_rounded,
              color: context.colors.primary,
              size: 25,
            ),
          ),
        if (showDefaultActions)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: IconButton(
              onPressed: navigationScope?.openProfile ?? () {},
              tooltip: 'Perfil',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              icon: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
