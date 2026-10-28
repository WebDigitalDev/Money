import 'package:flutter/material.dart';

extension IsDarkExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
