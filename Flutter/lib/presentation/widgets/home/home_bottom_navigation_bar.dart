import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:money/money.dart';

class HomeBottomNavigationBar extends StatelessWidget {
  final int activeIndex;
  final Function(int) onTap;
  final List<String> icons;
  final Key? chatButtonKey;

  const HomeBottomNavigationBar({
    super.key,
    required this.activeIndex,
    required this.onTap,
    this.chatButtonKey,
    this.icons = const [
      AppIcons.home,
      AppIcons.loan,
      AppIcons.chat,
      AppIcons.settings,
    ],
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBottomNavigationBar.builder(
      itemCount: icons.length,
      backgroundColor: context.colors.bottomNavigationBar,
      splashColor: context.colors.splashColor.withValues(alpha: 0.1),
      tabBuilder: (int index, bool isActive) {
        return Padding(
          key: index == 2 ? chatButtonKey : null,
          padding: const EdgeInsets.all(18.0),
          child: SvgIcon(
            icon: icons[index],
            color: isActive
                ? context.colors.primary
                : context.colors.textPrimary,
          ),
        );
      },
      activeIndex: activeIndex,
      gapLocation: GapLocation.center,
      notchSmoothness: NotchSmoothness.verySmoothEdge,
      elevation: 0,
      shadow: const Shadow(color: Colors.transparent),
      borderWidth: 0,
      leftCornerRadius: 32,
      rightCornerRadius: 32,
      onTap: onTap,
    );
  }
}
