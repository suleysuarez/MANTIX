import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/page_info.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';

part 'users_list_event.dart';
part 'users_list_state.dart';

/// Lista de usuarios con paginación por páginas. Los filtros ([search], [role], [isActive] y las
/// fechas de creación) y el tamaño de página van en el constructor: cambiar uno crea un Bloc
/// nuevo (la pantalla le pone una `key`), igual que Equipos; moverse entre páginas es un evento.
/// Si otra parte de la app cambia a alguien, la página actual se recarga sola.
class UsersListBloc extends Bloc<UsersListEvent, UsersListState> {
  UsersListBloc({required this._repository, this.search = '', this.role, this.isActive, this.createdFrom, this.createdTo, this.pageSize = PageInfo.defaultPageSize, this.sort = 'name'}) : super(const UsersListState()) {
    on<UsersListStarted>((_, emit) => _load(1, emit));
    on<UsersPageSelected>((event, emit) => _load(event.page, emit));
    on<UsersListRefreshed>((event, emit) async {
      try {
        await _load(state.page, emit);
      } finally {
        event.done?.complete();
      }
    });
    _changes = _repository.changes.listen((_) => add(const UsersListRefreshed()));
  }

  final UsersRepository _repository;
  final String search;
  final String? role;
  final bool? isActive;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final int pageSize;
  final String sort;
  late final StreamSubscription<void> _changes;

  /// Vuelve a pedir la página actual y espera a que termine; sirve al «tirar para refrescar».
  Future<void> refresh() {
    final done = Completer<void>();
    add(UsersListRefreshed(done: done));
    return done.future;
  }

  Future<void> _load(int page, Emitter<UsersListState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llega la página pedida.
    emit(state.items.isEmpty && state.status != UsersListStatus.success ? UsersListState(page: page) : state.copyWith(page: page, loadingPage: true));
    try {
      final result = await _repository.listUsers(page: page, size: pageSize, search: search, role: role, isActive: isActive, createdFrom: createdFrom, createdTo: createdTo, sort: sort);
      emit(UsersListState(status: UsersListStatus.success, items: result.items, info: result.info, page: page));
    } catch (error) {
      emit(UsersListState(status: UsersListStatus.failure, page: page, failure: toFailure(error)));
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
