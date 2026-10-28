import 'package:flutter/material.dart';
import 'package:money/money.dart';

class CustomFloatingActionButton extends StatelessWidget {
  static const LinearGradient gradient = LinearGradient(
    colors: [Color(0xFFA8D6A0), Color(0xFF76B475), Color(0xFF4B7D60)],
    stops: [0, 0.52, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  final VoidCallback? onPressed;
  final IconData? iconData;
  final String? icon;
  final ShapeBorder shape;

  const CustomFloatingActionButton({
    super.key,
    this.onPressed,
    this.iconData,
    this.icon,
    this.shape = const CircleBorder(),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        boxShadow: [
          const BoxShadow(
            color: Color(0x554B7D60),
            blurRadius: 10,
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: RawMaterialButton(
        shape: shape,
        onPressed: onPressed,
        child: iconData != null
            ? Icon(iconData, size: 30, color: Colors.white)
            : icon != null
            ? SvgIcon(icon: icon!, color: Colors.white)
            : null,
      ),
    );
  }
}
