import 'package:flutter/material.dart';
import 'package:money/money.dart';

extension AppColorsExtension on BuildContext {
  AppColors get colors => isDark ? AppDarkColors() : AppLightColors();
}
