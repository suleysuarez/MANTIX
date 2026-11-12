import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';

enum AssignableRolesStatus { loading, ready, failure }

class AssignableRolesState extends Equatable {
  const AssignableRolesState({this.status = AssignableRolesStatus.loading, this.roles = const [], this.failure});

  final AssignableRolesStatus status;
  final List<UserRoleRef> roles;
  final Failure? failure;

  @override
  List<Object?> get props => [status, roles, failure];
}

/// Roles activos que se pueden asignar, para el selector y para el filtro por rol. Son pocos y
/// no cambian durante la sesión: una carga, sin eventos (por eso es un Cubit).
class AssignableRolesCubit extends Cubit<AssignableRolesState> {
  AssignableRolesCubit(this._repository) : super(const AssignableRolesState());

  final UsersRepository _repository;

  Future<void> load() async {
    emit(const AssignableRolesState());
    try {
      emit(AssignableRolesState(status: AssignableRolesStatus.ready, roles: await _repository.assignableRoles()));
    } catch (error) {
      emit(AssignableRolesState(status: AssignableRolesStatus.failure, failure: toFailure(error)));
    }
  }
}
