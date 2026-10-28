import 'package:flutter/material.dart';
import 'package:money/core/core.dart';
import 'package:money/presentation/presentation.dart';

class SettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? icon;
  final IconData? materialIcon;
  final Color? iconColor;
  final GestureTapCallback? onTap;
  final Widget? trailing;
  final bool hasDivider;
  final String? trailingText;

  const SettingTile({
    super.key,
    required this.title,
    this.icon,
    this.materialIcon,
    this.hasDivider = false,
    this.trailingText,
    this.iconColor,
    this.subtitle,
    this.onTap,
    this.trailing,
  }) : assert(icon != null || materialIcon != null);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          onTap: onTap,
          dense: true,
          leading: Container(
            width: 30,
            height: 30,
            padding: EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: (iconColor ?? context.colors.primary).withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: materialIcon != null
                ? Icon(
                    materialIcon,
                    size: 16,
                    color: iconColor ?? context.colors.primary,
                  )
                : SvgIcon(
                    icon: icon!,
                    color: iconColor ?? context.colors.primary,
                  ),
          ),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: subtitle != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                    ),
                    softWrap: true,
                  ),
                )
              : null,
          trailing:
              trailing ??
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (trailingText != null)
                    Text(
                      trailingText!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  if (onTap != null)
                    SvgIcon(
                      icon: context.isRtl
                          ? AppIcons.angleLeft
                          : AppIcons.angleRight,
                      color: context.colors.textSecondary,
                    ),
                ],
              ),
        ),
        if (hasDivider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(
              height: 0.4,
              color: context.colors.divider.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }
}
