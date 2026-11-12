import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure_mapper.dart';
import '../../core/format/users_format.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';

part 'user_actions_event.dart';
part 'user_actions_state.dart';

/// Cambiar los roles de una persona, activar o desactivar su cuenta y editar su teléfono y código
/// de empleado. Valida antes de pedir nada al servidor (roles elegidos, formato de los campos,
/// no desactivarse a uno mismo, que haya algo que cambiar); las reglas que solo el servidor
/// conoce (último administrador, quitarse el propio rol de administrador, códigos repetidos)
/// llegan por su `code` ya traducidas. El resultado sale como un [UserOutcome] de una sola vez.
class UserActionsBloc extends Bloc<UserActionsEvent, UserActionsState> {
  UserActionsBloc({required this._repository, required this.currentUserId}) : super(const UserActionsState()) {
    on<UserRolesChangeRequested>(_onRoles);
    on<UserActiveChangeRequested>(_onActive);
    on<UserContactChangeRequested>(_onContact);
  }

  final UsersRepository _repository;

  /// La persona que usa la app: no puede desactivar su propia cuenta.
  final int currentUserId;
  int _outcomes = 0;

  UserOutcome _outcome(UserOutcomeKind kind, int userId, String message, [ManagedUser? user]) => UserOutcome(id: ++_outcomes, kind: kind, userId: userId, message: message, user: user);

  /// Corre [action] sobre [userId]: marca la persona como en curso y emite el resultado.
  Future<void> _run(int userId, Emitter<UserActionsState> emit, {required Future<ManagedUser> Function() action, required String Function(ManagedUser) success, required String failurePrefix}) async {
    emit(state.copyWith(inFlight: {...state.inFlight, userId}));
    try {
      final user = await action();
      emit(state.copyWith(inFlight: {...state.inFlight}..remove(userId), outcome: _outcome(UserOutcomeKind.succeeded, userId, success(user), user)));
    } catch (error) {
      emit(state.copyWith(inFlight: {...state.inFlight}..remove(userId), outcome: _outcome(UserOutcomeKind.failed, userId, '$failurePrefix ${toFailure(error).message}')));
    }
  }

  Future<void> _onRoles(UserRolesChangeRequested event, Emitter<UserActionsState> emit) async {
    if (state.inFlight.contains(event.userId)) return;
    final error = rolesError(event.roleIds);
    if (error != null) return emit(state.copyWith(outcome: _outcome(UserOutcomeKind.blocked, event.userId, error)));
    final wanted = event.roleIds.toSet();
    if (wanted.length == event.currentRoleIds.toSet().length && wanted.containsAll(event.currentRoleIds)) {
      return emit(state.copyWith(outcome: _outcome(UserOutcomeKind.blocked, event.userId, '${event.name} ya tiene esos roles.')));
    }
    await _run(
      event.userId,
      emit,
      action: () => _repository.setRoles(event.userId, wanted.toList()),
      success: (_) => 'Roles de ${event.name} actualizados.',
      failurePrefix: 'No se pudieron cambiar los roles de ${event.name}:',
    );
  }

  Future<void> _onActive(UserActiveChangeRequested event, Emitter<UserActionsState> emit) async {
    final user = event.user;
    if (state.inFlight.contains(user.id)) return;
    if (!event.active && user.id == currentUserId) {
      return emit(state.copyWith(outcome: _outcome(UserOutcomeKind.blocked, user.id, 'No puedes desactivar tu propia cuenta.')));
    }
    if (user.isActive == event.active) {
      return emit(state.copyWith(outcome: _outcome(UserOutcomeKind.blocked, user.id, 'La cuenta de ${user.fullName} ya está ${event.active ? 'activa' : 'desactivada'}.')));
    }
    await _run(
      user.id,
      emit,
      action: () => _repository.setActive(user.id, active: event.active),
      success: (_) => event.active ? 'La cuenta de ${user.fullName} fue activada.' : 'La cuenta de ${user.fullName} fue desactivada.',
      failurePrefix: 'No se pudo ${event.active ? 'activar' : 'desactivar'} a ${user.fullName}:',
    );
  }

  Future<void> _onContact(UserContactChangeRequested event, Emitter<UserActionsState> emit) async {
    final user = event.user;
    if (state.inFlight.contains(user.id)) return;
    final problem = phoneError(event.phone);
    if (problem != null) return emit(state.copyWith(outcome: _outcome(UserOutcomeKind.blocked, user.id, problem)));
    final phone = normalizedPhone(event.phone);
    final phoneChanged = phone != user.phone;
    if (!phoneChanged) {
      return emit(state.copyWith(outcome: _outcome(UserOutcomeKind.blocked, user.id, 'No hay cambios que guardar.')));
    }
    await _run(
      user.id,
      emit,
      action: () => _repository.updateContact(user.id, phone: (value: phone)),
      success: (_) => 'Datos de ${user.fullName} actualizados.',
      failurePrefix: 'No se pudieron guardar los datos de ${user.fullName}:',
    );
  }
}
