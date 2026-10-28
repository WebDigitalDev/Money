import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:no_screenshot/no_screenshot.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:money/money.dart';

part 'setting_state.dart';

class SettingCubit extends Cubit<SettingState> {
  final SharedPreferencesService preferencesService =
      SharedPreferencesService();

  final LocalAuthentication auth = LocalAuthentication();
  SettingCubit() : super(SettingLoading());

  Future<void> init() async {
    final AppSettings settings = await preferencesService.getSettings();
    bool canAuthenticate = false;
    if (!kIsWeb) {
      try {
        canAuthenticate = (await auth.getAvailableBiometrics()).isNotEmpty;
      } catch (_) {}
    }
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    if (isClosed) return;

    emit(
      SettingInitial(
        themeMode: settings.themeMode,
        enableScreenshot: settings.enableScreenshot,
        appLocked: settings.enableLockApp,
        canAuthenticate: canAuthenticate,
        packageInfo: packageInfo,
      ),
    );
  }

  void setThemeMode(ThemeMode mode) {
    emit((state as SettingInitial).copyWith(themeMode: mode));
  }

  Future<void> switchAppLock(String localizedReason) async {
    final SettingInitial settingInitial = (state as SettingInitial);
    final bool enabling = !settingInitial.appLocked;

    try {
      if (enabling) {
        final bool authenticated = await auth.authenticate(
          localizedReason: localizedReason,
          authMessages: AppAuthMessages.portugueseBrazil,
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (!authenticated) return;
      }

      await preferencesService.saveEnableLockApp(enabling);
      if (isClosed) return;
      emit(settingInitial.copyWith(appLocked: enabling));
    } catch (_) {}
  }

  Future<void> switchScreenshot() async {
    final SettingInitial settingInitial = (state as SettingInitial);

    await preferencesService.saveEnableScreenshot(
      !settingInitial.enableScreenshot,
    );

    if (isClosed) return;

    if (!settingInitial.enableScreenshot) {
      NoScreenshot.instance.screenshotOn();
    } else {
      NoScreenshot.instance.screenshotOff();
    }

    emit(
      settingInitial.copyWith(
        enableScreenshot: !settingInitial.enableScreenshot,
      ),
    );
  }

  String? getAppDownloadUrl() {
    if (kIsWeb) return Uri.base.origin;

    return defaultTargetPlatform == TargetPlatform.android
        ? "https://play.google.com/store/apps/details?id=${(state as SettingInitial).packageInfo.packageName}"
        : null;
  }
}
