part of 'home_cubit.dart';

sealed class HomeState extends Equatable {
  const HomeState();
}

final class HomeInitial extends HomeState {
  final int activeIndex;

  const HomeInitial({required this.activeIndex});

  @override
  List<Object?> get props => [activeIndex];
}
