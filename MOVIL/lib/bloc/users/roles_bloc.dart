import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';

part 'roles_event.dart';
part 'roles_state.dart';

/// Pestaña Roles: los roles que existen, en solo lectura, con cuántas personas tiene cada uno.
/// Con [detailed] (quien puede asignar roles) también llegan la descripción y si está activo.
/// Se recarga sola cuando cambian los roles de alguien (cambian los conteos).
class RolesBloc extends Bloc<RolesEvent, RolesState> {
  RolesBloc({required this._repository, required this.detailed}) : super(const RolesState()) {
    on<RolesRequested>(_onRequested);
    _changes = _repository.changes.listen((_) => add(const RolesRequested()));
  }

  final UsersRepository _repository;
  final bool detailed;
  late final StreamSubscription<void> _changes;

  Future<void> _onRequested(RolesRequested event, Emitter<RolesState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llegan los nuevos.
    emit(state.roles.isEmpty ? const RolesState() : state.copyWith(refreshing: true));
    try {
      emit(RolesState(status: RolesStatus.ready, roles: await _repository.rolesOverview(detailed: detailed)));
    } catch (error) {
      emit(state.roles.isEmpty || state.status == RolesStatus.loading
          ? RolesState(status: RolesStatus.failure, failure: toFailure(error))
          // Una recarga que falla deja la lista que había.
          : RolesState(status: RolesStatus.ready, roles: state.roles, failure: toFailure(error)));
    } finally {
      event.done?.complete();
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
