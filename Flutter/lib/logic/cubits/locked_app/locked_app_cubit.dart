import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:money/core/core.dart';

part 'locked_app_state.dart';

class LockedAppCubit extends Cubit<LockedAppState> {
  final LocalAuthentication auth = LocalAuthentication();

  LockedAppCubit() : super(LockedAppInitial());

  Future<void> unlock(String localizedReason) async {
    try {
      if (await auth.authenticate(
        localizedReason: localizedReason,
        authMessages: AppAuthMessages.portugueseBrazil,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      )) {
        if (isClosed) return;
        emit(UnlockedApp());
      }
    } catch (_) {}
  }
}
