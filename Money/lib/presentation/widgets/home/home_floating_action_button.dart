import 'package:flutter/material.dart';
import 'package:money/core/core.dart';
import 'package:money/presentation/presentation.dart';

class HomeFloatingActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final VoidCallback? onNewLoan;
  final VoidCallback? onRegisterClient;
  final IconData? iconData;
  final String? icon;

  const HomeFloatingActionButton({
    super.key,
    this.onPressed,
    this.onNewLoan,
    this.onRegisterClient,
    this.iconData,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return CustomFloatingActionButton(
      onPressed: onPressed ?? () => _openMenu(context),
      iconData: iconData,
      icon: iconData == null ? (icon ?? AppIcons.addTransaction) : null,
    );
  }

  void _openMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      builder: (context) => MenuModalBottomSheet(
        onNewLoan: onNewLoan ?? () {},
        onRegisterClient: onRegisterClient ?? () {},
      ),
    );
  }
}
