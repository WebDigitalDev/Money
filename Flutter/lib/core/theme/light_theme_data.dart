import 'package:flutter/material.dart';
import 'package:money/money.dart';

final lightThemeData = ThemeData(
  brightness: Brightness.light,
  primaryColor: appLightColors.primary,
  primaryColorDark: appDarkColors.primary,
  primaryColorLight: appLightColors.primaryLight,
  secondaryHeaderColor: appLightColors.secondary,
  scaffoldBackgroundColor: appLightColors.background,
  cardColor: appLightColors.surface,
  dividerColor: appLightColors.divider,
  disabledColor: appLightColors.disabled,
  textTheme: ThemeData.light().textTheme.apply(
    bodyColor: appLightColors.textPrimary,
    displayColor: appLightColors.textPrimary,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: appLightColors.appBar,
    foregroundColor: appLightColors.textPrimary,
    centerTitle: false,
    elevation: 1,
    titleTextStyle: TextStyle(
      fontWeight: FontWeight.bold,
      color: appLightColors.textPrimary,
      fontSize: 16,
    ),
  ),
  splashColor: appDarkColors.splashColor.withValues(alpha: 0.1),
  colorScheme: ColorScheme.light(
    primary: appLightColors.primary,
    onPrimary: Colors.white,
    secondary: appLightColors.secondary,
    onSecondary: Colors.white,
    surface: appLightColors.surface,
    onSurface: appLightColors.textPrimary,
    error: appLightColors.error,
    onError: Colors.white,
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: appLightColors.primary,
    foregroundColor: Colors.white,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: appLightColors.surface,
    titleTextStyle: TextStyle(
      color: appLightColors.textPrimary,
      fontWeight: FontWeight.bold,
      fontSize: 18,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    hintStyle: TextStyle(color: appLightColors.textPlaceholder),
    labelStyle: TextStyle(
      color: appLightColors.textPrimary,
      fontWeight: FontWeight.w500,
    ),
    prefixIconColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? appLightColors.primary
          : appLightColors.textPrimary,
    ),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: appLightColors.inputBorder, width: 0.2),
    ),
    isDense: true,
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: appLightColors.primary, width: 0.8),
    ),
  ),
  expansionTileTheme: ExpansionTileThemeData(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 15),
    collapsedIconColor: appLightColors.textPrimary,
    collapsedTextColor: appLightColors.textPrimary,
    iconColor: appLightColors.textPrimary,
    textColor: appLightColors.textPrimary,
    shape: const Border(),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: appLightColors.snackBar,
    contentTextStyle: TextStyle(color: appLightColors.snackBarText),
    actionTextColor: appLightColors.snackBarText,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: appLightColors.primary,
      foregroundColor: Colors.white,
      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
  ),
  radioTheme: RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.selected)
          ? appLightColors.secondary
          : Colors.white,
    ),
  ),
  checkboxTheme: CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    side: BorderSide(color: appLightColors.textSecondary),
    fillColor: WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.selected)
          ? appLightColors.primary
          : Colors.white,
    ),
    checkColor: WidgetStateProperty.all(Colors.white),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: appLightColors.surface,
    modalBackgroundColor: appLightColors.surface,
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith<Color>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.selected)) {
        return appLightColors.primary;
      }
      return appLightColors.surface;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith<Color>((
      Set<WidgetState> states,
    ) {
      return Colors.transparent;
    }),
    trackColor: WidgetStateProperty.resolveWith<Color>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.selected)) {
        return appLightColors.primary.withValues(alpha: 0.5);
      }
      return appLightColors.disabled;
    }),
  ),
);
