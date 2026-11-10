part of 'pending_users_bloc.dart';

enum PendingStatus { loading, ready, failure }

class PendingUsersState extends Equatable {
  const PendingUsersState({this.status = PendingStatus.loading, this.users = const [], this.refreshing = false, this.failure});

  final PendingStatus status;
  final List<PendingUser> users;

  /// Se está recargando mientras se siguen mostrando los pendientes anteriores.
  final bool refreshing;

  /// Error de la última carga: con `status` en `failure` no hay lista; con `ready`, es el de una
  /// recarga que falló y la lista anterior sigue visible.
  final Failure? failure;

  PendingUsersState copyWith({bool? refreshing}) => PendingUsersState(status: status, users: users, refreshing: refreshing ?? this.refreshing, failure: failure);

  @override
  List<Object?> get props => [status, users, refreshing, failure];
}
