import 'package:flutter/widgets.dart';

class AppSidebarScope extends InheritedWidget {
  final VoidCallback openMenu;
  final VoidCallback openProfile;
  final VoidCallback openConferences;
  final VoidCallback? openNotifications;
  final VoidCallback? backFromNotifications;
  final ValueChanged<int> openClient;

  const AppSidebarScope({
    super.key,
    required this.openMenu,
    required this.openProfile,
    required this.openConferences,
    this.openNotifications,
    this.backFromNotifications,
    required this.openClient,
    required super.child,
  });

  static AppSidebarScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppSidebarScope>();
  }

  @override
  bool updateShouldNotify(AppSidebarScope oldWidget) {
    return openMenu != oldWidget.openMenu ||
        openProfile != oldWidget.openProfile ||
        openConferences != oldWidget.openConferences ||
        openNotifications != oldWidget.openNotifications ||
        backFromNotifications != oldWidget.backFromNotifications ||
        openClient != oldWidget.openClient;
  }
}
