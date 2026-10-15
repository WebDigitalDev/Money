part of 'shared_cubit.dart';

@immutable
sealed class SharedState extends Equatable {
  const SharedState();
}

final class SharedInitial extends SharedState {
  final ThemeMode themeMode;

  const SharedInitial({required this.themeMode});

  @override
  List<Object?> get props => [themeMode];
}

final class ShowModalBottomSheet extends SharedState {
  final WidgetBuilder builder;
  final DateTime timestamp;
  final Color? backgroundColor;

  ShowModalBottomSheet({required this.builder, this.backgroundColor})
    : timestamp = DateTime.now();

  @override
  List<Object?> get props => [builder, backgroundColor, timestamp];
}
