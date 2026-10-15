import 'package:flutter/material.dart';
import 'package:money/money.dart';

class MenuTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String icon;
  final Color? iconColor;
  final bool hasDivider;
  final GestureTapCallback onTap;

  const MenuTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.hasDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          dense: true,
          onTap: onTap,
          leading: Container(
            width: 35,
            height: 35,
            padding: EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: (iconColor ?? context.colors.primary).withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SvgIcon(
              icon: icon,
              color: (iconColor ?? context.colors.primary),
            ),
          ),
          title: Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ),
        if (hasDivider)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.padding,
            ),
            child: Divider(
              height: 0.5,
              color: context.colors.divider.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }
}
