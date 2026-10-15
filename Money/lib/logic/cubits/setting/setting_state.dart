part of 'setting_cubit.dart';

sealed class SettingState extends Equatable {
  const SettingState();
}

class SettingLoading extends SettingState {
  @override
  List<Object> get props => [];
}

final class SettingInitial extends SettingState {
  final ThemeMode themeMode;
  final bool enableScreenshot;
  final bool appLocked;
  final bool canAuthenticate;
  final PackageInfo packageInfo;

  const SettingInitial({
    required this.themeMode,
    required this.enableScreenshot,
    required this.appLocked,
    required this.canAuthenticate,
    required this.packageInfo,
  });

  @override
  List<Object> get props => [
    themeMode.name,
    enableScreenshot,
    appLocked,
    canAuthenticate,
    packageInfo.version,
  ];

  SettingInitial copyWith({
    ThemeMode? themeMode,
    bool? enableScreenshot,
    bool? appLocked,
    bool? canAuthenticate,
  }) {
    return SettingInitial(
      themeMode: themeMode ?? this.themeMode,
      enableScreenshot: enableScreenshot ?? this.enableScreenshot,
      appLocked: appLocked ?? this.appLocked,
      canAuthenticate: canAuthenticate ?? this.canAuthenticate,
      packageInfo: packageInfo,
    );
  }
}
