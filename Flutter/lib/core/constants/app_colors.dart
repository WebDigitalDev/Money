import 'package:flutter/material.dart';

abstract class AppColors {
  Color get primary;

  Color get secondary;

  Color get background;

  Color get bottomNavigationBar;

  Color get splashColor;

  Color get surface;

  Color get appBar;

  Color get divider;

  Color get textPrimary;

  Color get textSecondary;

  Color get textPlaceholder;

  Color get error;

  Color get disabled;

  Color get inputBorder;

  Color get snackBar;

  Color get snackBarText;
}

final class AppLightColors extends AppColors {
  static final AppLightColors _instance = AppLightColors._internal();

  factory AppLightColors() => _instance;

  AppLightColors._internal();

  @override
  Color get primary => Color(0xFF76B475);

  Color get primaryLight => Color(0xFFA8D6A0);

  @override
  Color get secondary => Color(0xFFF07167);

  @override
  Color get background => Color(0xFFF5F7FA);

  @override
  Color get surface => Color(0xFFFFFFFF);

  @override
  Color get bottomNavigationBar => surface;

  @override
  Color get splashColor => primary;

  @override
  Color get appBar => surface;

  @override
  Color get divider => Color(0xFFE0E0E0);

  @override
  Color get textPrimary => Color(0xFF1E1E1E);

  @override
  Color get textSecondary => Color(0xFF5F6368);

  @override
  Color get textPlaceholder => Color(0xFFA0A0A0);

  @override
  Color get error => Color(0xFFD32F2F);

  @override
  Color get disabled => Color(0xFFB0BEC5);

  @override
  Color get inputBorder => Color(0xFF9D9D9D);

  @override
  Color get snackBar => Color(0xFF2C2C2C);

  @override
  Color get snackBarText => Colors.white;
}

final class AppDarkColors extends AppColors {
  static final AppDarkColors _instance = AppDarkColors._internal();

  factory AppDarkColors() => _instance;

  AppDarkColors._internal();

  @override
  Color get primary => Color(0xFF76B475);

  @override
  Color get secondary => Color(0xFFF07167);

  @override
  Color get background => Color(0xFF0A0A0A);

  @override
  Color get surface => Color(0xFF141414);

  @override
  Color get bottomNavigationBar => surface;

  @override
  Color get splashColor => primary;

  @override
  Color get appBar => Color(0xFF0A0A0A);

  @override
  Color get divider => Color(0xFF202020);

  @override
  Color get textPrimary => Color(0xFFEFEFEF);

  @override
  Color get textSecondary => Color(0xFFB3B3B3);

  @override
  Color get textPlaceholder => Color(0xFF7A7A7A);

  @override
  Color get error => Color(0xFFD32F2F);

  @override
  Color get disabled => Color(0xFFB0BEC5);

  @override
  Color get inputBorder => Color(0xFF9D9D9D);

  @override
  Color get snackBar => Color(0xFF2C2C2C);

  @override
  Color get snackBarText => Colors.white;
}

final AppLightColors appLightColors = AppLightColors();
final AppDarkColors appDarkColors = AppDarkColors();
