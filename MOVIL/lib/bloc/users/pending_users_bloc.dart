import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';

part 'pending_users_event.dart';
part 'pending_users_state.dart';

/// Pestaña Pendientes: personas activas que ya entraron y esperan un rol. El servidor no pagina
/// esta lista. Se recarga sola cuando se asigna un rol (la persona sale de aquí).
class PendingUsersBloc extends Bloc<PendingUsersEvent, PendingUsersState> {
  PendingUsersBloc({required this._repository}) : super(const PendingUsersState()) {
    on<PendingUsersRequested>(_onRequested);
    _changes = _repository.changes.listen((_) => add(const PendingUsersRequested()));
  }

  final UsersRepository _repository;
  late final StreamSubscription<void> _changes;

  Future<void> _onRequested(PendingUsersRequested event, Emitter<PendingUsersState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llegan los nuevos.
    emit(state.users.isEmpty ? const PendingUsersState() : state.copyWith(refreshing: true));
    try {
      emit(PendingUsersState(status: PendingStatus.ready, users: await _repository.pending()));
    } catch (error) {
      emit(state.users.isEmpty || state.status == PendingStatus.loading
          ? PendingUsersState(status: PendingStatus.failure, failure: toFailure(error))
          // Una recarga que falla deja la lista que había.
          : PendingUsersState(status: PendingStatus.ready, users: state.users, failure: toFailure(error)));
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
