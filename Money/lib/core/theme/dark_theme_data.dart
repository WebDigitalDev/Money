import 'package:flutter/material.dart';
import 'package:money/core/constants/app_colors.dart';

final darkThemeData = ThemeData(
  brightness: Brightness.dark,
  primaryColor: appDarkColors.primary,
  primaryColorDark: appDarkColors.primary,
  primaryColorLight: appLightColors.primaryLight,
  secondaryHeaderColor: appDarkColors.secondary,
  scaffoldBackgroundColor: appDarkColors.background,
  cardColor: appDarkColors.surface,
  dividerColor: appDarkColors.divider,
  disabledColor: appDarkColors.disabled.withValues(alpha: 0.4),
  textTheme: ThemeData.dark().textTheme.apply(
    bodyColor: appDarkColors.textPrimary,
    displayColor: appDarkColors.textPrimary,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: appDarkColors.appBar,
    foregroundColor: appDarkColors.textPrimary,
    centerTitle: false,
    elevation: 1,
    titleTextStyle: TextStyle(
      fontWeight: FontWeight.bold,
      color: appDarkColors.textPrimary,
      fontSize: 16,
    ),
  ),
  colorScheme: ColorScheme.dark(
    primary: appDarkColors.primary,
    onPrimary: Colors.white,
    secondary: appDarkColors.secondary,
    onSecondary: Colors.white,
    surface: appDarkColors.surface,
    onSurface: appDarkColors.textPrimary,
    error: appDarkColors.error,
    onError: Colors.white,
  ),
  splashColor: appDarkColors.splashColor.withValues(alpha: 0.1),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: appDarkColors.primary,
    foregroundColor: Colors.white,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: appDarkColors.surface,
    titleTextStyle: TextStyle(
      color: appDarkColors.textPrimary,
      fontWeight: FontWeight.bold,
      fontSize: 18,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    hintStyle: TextStyle(color: appDarkColors.textPlaceholder),
    labelStyle: TextStyle(
      color: appDarkColors.textPrimary,
      fontWeight: FontWeight.w500,
    ),
    prefixIconColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? appDarkColors.primary
          : appDarkColors.textPrimary,
    ),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: appDarkColors.inputBorder, width: 0.2),
    ),
    isDense: true,
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: appDarkColors.primary, width: 0.8),
    ),
  ),
  expansionTileTheme: ExpansionTileThemeData(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 15),
    collapsedIconColor: appDarkColors.textPrimary,
    collapsedTextColor: appDarkColors.textPrimary,
    iconColor: appDarkColors.textPrimary,
    textColor: appDarkColors.textPrimary,
    shape: const Border(),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: appDarkColors.snackBar,
    contentTextStyle: TextStyle(color: appDarkColors.snackBarText),
    actionTextColor: appDarkColors.snackBarText,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: appDarkColors.primary,
      foregroundColor: Colors.white,
      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
  ),
  radioTheme: RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.selected)
          ? appDarkColors.secondary
          : appDarkColors.textPrimary,
    ),
  ),
  checkboxTheme: CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    side: BorderSide(color: appDarkColors.textSecondary),
    fillColor: WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.selected)
          ? appDarkColors.primary
          : Colors.white,
    ),
    checkColor: WidgetStateProperty.all(Colors.white),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: appDarkColors.surface,
    modalBackgroundColor: appDarkColors.surface,
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith<Color>((
      Set<WidgetState> states,
    ) {
      if (states.contains(WidgetState.selected)) {
        return appDarkColors.primary;
      }
      return appDarkColors.surface;
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
        return appDarkColors.primary.withValues(alpha: 0.5);
      }
      return appDarkColors.textSecondary.withValues(alpha: 0.3);
    }),
  ),
);
