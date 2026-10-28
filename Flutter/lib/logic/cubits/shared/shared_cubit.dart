import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:money/money.dart';

part 'shared_state.dart';

class SharedCubit extends Cubit<SharedState> {
  final SharedPreferencesService preferencesService =
      SharedPreferencesService();
  final LocalAuthentication auth = LocalAuthentication();

  SharedCubit(ThemeMode themeMode)
    : super(SharedInitial(themeMode: _explicitThemeMode(themeMode)));

  Future<void> updateThemeMode(ThemeMode themeMode) async {
    final ThemeMode explicitMode = _explicitThemeMode(themeMode);
    if (state is SharedInitial &&
        (state as SharedInitial).themeMode == explicitMode) {
      return;
    }

    // A interface troca imediatamente; a persistência não bloqueia a animação.
    emit(SharedInitial(themeMode: explicitMode));
    await preferencesService.saveThemeMode(explicitMode);
  }

  static ThemeMode _explicitThemeMode(ThemeMode mode) =>
      mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;

  void showModalBottomSheet(WidgetBuilder builder, {Color? backgroundColor}) {
    emit(
      ShowModalBottomSheet(builder: builder, backgroundColor: backgroundColor),
    );
  }

  Future<void> authenticateIfAvailable(
    String localizedReason,
    Function callback,
  ) async {
    if (kIsWeb) {
      callback();
      return;
    }

    if (await auth.canCheckBiometrics || await auth.isDeviceSupported()) {
      try {
        if (await auth.authenticate(
          localizedReason: localizedReason,
          authMessages: AppAuthMessages.portugueseBrazil,
          persistAcrossBackgrounding: true,
        )) {
          callback();
        }
      } catch (_) {}
    } else {
      callback();
    }
  }
}
