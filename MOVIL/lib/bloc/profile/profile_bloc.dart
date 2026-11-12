import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/users_format.dart';
import '../../models/profile/profile_models.dart';
import '../../repositories/profile/profile_repository.dart';
import '../../services/image_picker_service.dart';

part 'profile_event.dart';
part 'profile_state.dart';

/// Mi perfil: cargarlo, editar nombre y teléfono, y cambiar o quitar la foto. El correo no se
/// edita (es la identidad de acceso). Cada acción borra el aviso anterior antes de empezar, así
/// que el mismo mensaje dos veces seguidas se vuelve a mostrar.
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc({required this._repository, required this._images}) : super(const ProfileState()) {
    on<ProfileRequested>(_onRequested);
    on<ProfileSaveRequested>(_onSave);
    on<ProfilePhotoRequested>(_onPhoto);
    on<ProfilePhotoRemoveRequested>(_onRemovePhoto);
  }

  final ProfileRepository _repository;
  final ImagePickerService _images;

  /// Baja los bytes de la foto; si falla, la persona ve sus iniciales en vez de un error.
  Future<Uint8List?> _loadAvatar(ProfileData profile) async {
    if (!profile.hasAvatar) return null;
    try {
      return await _repository.avatar();
    } on Object {
      return null;
    }
  }

  Future<void> _onRequested(ProfileRequested event, Emitter<ProfileState> emit) async {
    // Al recargar se conserva lo que ya se ve; solo cambia lo que llega.
    emit(state.copyWith(status: ProfileStatus.loading, clearFailure: true));
    try {
      final profile = await _repository.get();
      final sameAvatar = state.avatar != null && state.profile?.avatarVersion == profile.avatarVersion;
      final avatar = sameAvatar ? state.avatar : await _loadAvatar(profile);
      emit(ProfileState(status: ProfileStatus.ready, profile: profile, avatar: avatar));
    } catch (error) {
      emit(state.copyWith(status: ProfileStatus.failure, failure: toFailure(error)));
    } finally {
      event.done?.complete();
    }
  }

  Future<void> _onSave(ProfileSaveRequested event, Emitter<ProfileState> emit) async {
    final current = state.profile;
    if (current == null || state.saving) return;
    final name = collapseSpaces(event.fullName);
    final phone = collapseSpaces(event.phone);
    final nameChanged = name != current.fullName;
    final phoneChanged = phone != (current.phone ?? '');
    emit(state.copyWith(saving: true, clearNotice: true, clearActionError: true));
    if (!nameChanged && !phoneChanged) {
      return emit(state.copyWith(saving: false, actionError: 'No hay cambios que guardar.'));
    }
    try {
      final profile = await _repository.update(fullName: nameChanged ? name : null, phone: phoneChanged ? phone : null);
      emit(state.copyWith(saving: false, profile: profile, notice: 'Datos actualizados.'));
    } catch (error) {
      emit(state.copyWith(saving: false, actionError: toFailure(error).message));
    }
  }

  Future<void> _onPhoto(ProfilePhotoRequested event, Emitter<ProfileState> emit) async {
    if (state.profile == null || state.saving) return;
    emit(state.copyWith(clearNotice: true, clearActionError: true));
    try {
      final file = event.source == ProfilePhotoSource.camera ? await _images.takePhoto() : await _images.pickFromGallery();
      if (file == null) return; // canceló: no hay nada que decir
      emit(state.copyWith(saving: true));
      final profile = await _repository.uploadAvatar(file);
      emit(state.copyWith(saving: false, profile: profile, avatar: await _loadAvatar(profile), notice: 'Foto actualizada.'));
    } catch (error) {
      emit(state.copyWith(saving: false, actionError: toFailure(error).message));
    }
  }

  Future<void> _onRemovePhoto(ProfilePhotoRemoveRequested event, Emitter<ProfileState> emit) async {
    if (state.profile == null || state.saving) return;
    emit(state.copyWith(saving: true, clearNotice: true, clearActionError: true));
    try {
      final profile = await _repository.removeAvatar();
      emit(state.copyWith(saving: false, profile: profile, clearAvatar: true, notice: 'Foto quitada.'));
    } catch (error) {
      emit(state.copyWith(saving: false, actionError: toFailure(error).message));
    }
  }
}
