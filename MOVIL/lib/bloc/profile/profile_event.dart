part of 'profile_bloc.dart';

/// De dónde sale la foto nueva.
enum ProfilePhotoSource { camera, gallery }

sealed class ProfileEvent {
  const ProfileEvent();
}

/// Carga (o recarga) mi perfil: al abrir, al tirar para refrescar o al reintentar.
class ProfileRequested extends ProfileEvent {
  const ProfileRequested({this.done});

  /// Se completa al terminar (tirar para refrescar espera a esto).
  final Completer<void>? done;
}

/// Guarda mi nombre y mi teléfono. Un teléfono vacío lo borra. Solo viaja lo que cambió.
class ProfileSaveRequested extends ProfileEvent {
  const ProfileSaveRequested({required this.fullName, required this.phone});

  final String fullName;
  final String phone;
}

/// Cambia mi foto con una tomada con la cámara o elegida de la galería. Si se cancela, no pasa nada.
class ProfilePhotoRequested extends ProfileEvent {
  const ProfilePhotoRequested(this.source);

  final ProfilePhotoSource source;
}

class ProfilePhotoRemoveRequested extends ProfileEvent {
  const ProfilePhotoRemoveRequested();
}
