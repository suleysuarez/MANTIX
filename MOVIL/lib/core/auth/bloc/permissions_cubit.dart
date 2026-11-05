import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'auth_bloc.dart';

/// Permisos efectivos de la sesión actual (vacíos si no hay sesión activa).
/// Solo sirven para ocultar o deshabilitar: la autorización real es del backend.
class PermissionsState extends Equatable {
  const PermissionsState([this.codes = const {}]);

  factory PermissionsState.of(AuthState auth) =>
      auth is Authenticated ? PermissionsState(auth.profile.permissions) : const PermissionsState();

  final Set<String> codes;

  bool can(String permission) => codes.contains(permission);

  @override
  List<Object?> get props => [codes];
}

/// Cubit derivado del [AuthBloc]: no tiene eventos propios, solo refleja sus permisos.
class PermissionsCubit extends Cubit<PermissionsState> {
  PermissionsCubit(AuthBloc auth) : super(PermissionsState.of(auth.state)) {
    _subscription = auth.stream.listen((state) => emit(PermissionsState.of(state)));
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
