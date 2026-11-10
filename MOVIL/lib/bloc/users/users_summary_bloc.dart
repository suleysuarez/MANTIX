import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';

part 'users_summary_event.dart';
part 'users_summary_state.dart';

/// Cifras de la pantalla de usuarios y el contador de la pestaña Pendientes. Falla por separado
/// de las listas: si no carga, ellas siguen funcionando. Se recarga sola cuando alguien cambia.
class UsersSummaryBloc extends Bloc<UsersSummaryEvent, UsersSummaryState> {
  UsersSummaryBloc({required this._repository}) : super(const UsersSummaryState()) {
    on<UsersSummaryRequested>(_onRequested);
    _changes = _repository.changes.listen((_) => add(const UsersSummaryRequested()));
  }

  final UsersRepository _repository;
  late final StreamSubscription<void> _changes;

  Future<void> _onRequested(UsersSummaryRequested event, Emitter<UsersSummaryState> emit) async {
    // Al recargar se conserva el último resumen visible; solo cambia lo que llega.
    emit(state.copyWith(status: UsersSummaryStatus.loading, clearFailure: true));
    try {
      emit(state.copyWith(status: UsersSummaryStatus.ready, summary: await _repository.summary()));
    } catch (error) {
      emit(state.copyWith(status: UsersSummaryStatus.failure, failure: toFailure(error)));
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
