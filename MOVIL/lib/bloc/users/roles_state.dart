part of 'roles_bloc.dart';

enum RolesStatus { loading, ready, failure }

class RolesState extends Equatable {
  const RolesState({this.status = RolesStatus.loading, this.roles = const [], this.refreshing = false, this.failure});

  final RolesStatus status;
  final List<RoleInfo> roles;

  /// Se está recargando mientras se siguen mostrando los roles anteriores.
  final bool refreshing;

  /// Error de la última carga: con `status` en `failure` no hay lista; con `ready`, es el de una
  /// recarga que falló y la lista anterior sigue visible.
  final Failure? failure;

  RolesState copyWith({bool? refreshing}) => RolesState(status: status, roles: roles, refreshing: refreshing ?? this.refreshing, failure: failure);

  @override
  List<Object?> get props => [status, roles, refreshing, failure];
}
