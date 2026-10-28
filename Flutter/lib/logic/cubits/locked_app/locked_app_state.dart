part of 'locked_app_cubit.dart';

sealed class LockedAppState extends Equatable {
  const LockedAppState();
}

final class LockedAppInitial extends LockedAppState {
  @override
  List<Object> get props => [];
}

final class UnlockedApp extends LockedAppState {
  final DateTime timestamp;

  UnlockedApp() : timestamp = DateTime.now();

  @override
  List<Object?> get props => [timestamp];
}
