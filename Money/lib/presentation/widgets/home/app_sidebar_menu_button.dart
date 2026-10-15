import 'package:flutter/material.dart';
import 'package:money/money.dart';

class AppSidebarMenuButton extends StatelessWidget {
  const AppSidebarMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppSidebarScope.maybeOf(context);
    if (scope == null) {
      return const SizedBox.shrink();
    }

    return IconButton(
      onPressed: scope.openMenu,
      tooltip: context.tr!.menu,
      icon: SvgIcon(
        icon: AppIcons.menu,
        width: 18,
        color: context.colors.textPrimary,
      ),
    );
  }
}
