part of 'profile_bloc.dart';

enum ProfileStatus { loading, ready, failure }

class ProfileState extends Equatable {
  const ProfileState({this.status = ProfileStatus.loading, this.profile, this.avatar, this.saving = false, this.notice, this.actionError, this.failure});

  final ProfileStatus status;
  final ProfileData? profile;

  /// Los bytes de mi foto; `null` sin foto o si no se pudo bajar.
  final Uint8List? avatar;

  /// Hay un guardado o una subida de foto en curso.
  final bool saving;

  /// Lo que salió bien en la última acción («Datos actualizados.»); se borra al empezar la siguiente.
  final String? notice;

  /// Lo que salió mal en la última acción, en español y sin detalles internos.
  final String? actionError;

  /// Por qué no cargó el perfil.
  final Failure? failure;

  bool get initialLoading => status == ProfileStatus.loading && profile == null;

  /// Se muestra el error con reintento solo si no hay nada que enseñar.
  bool get unavailable => status == ProfileStatus.failure && profile == null;

  ProfileState copyWith({
    ProfileStatus? status,
    ProfileData? profile,
    Uint8List? avatar,
    bool clearAvatar = false,
    bool? saving,
    String? notice,
    bool clearNotice = false,
    String? actionError,
    bool clearActionError = false,
    Failure? failure,
    bool clearFailure = false,
  }) =>
      ProfileState(
        status: status ?? this.status,
        profile: profile ?? this.profile,
        avatar: clearAvatar ? null : (avatar ?? this.avatar),
        saving: saving ?? this.saving,
        notice: clearNotice ? null : (notice ?? this.notice),
        actionError: clearActionError ? null : (actionError ?? this.actionError),
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, profile, avatar, saving, notice, actionError, failure];
}
