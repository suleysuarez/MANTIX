import 'dart:typed_data';

import 'package:bloc/bloc.dart';

import '../../repositories/profile/profile_repository.dart';

/// Mi foto, la misma en todo el encabezado y el menú lateral. El estado son sus bytes, o `null` si no
/// hay foto (se ven las iniciales). Se carga al iniciar sesión, se vacía al cerrarla y la pantalla de
/// perfil la actualiza cuando se cambia o se quita. Es un Cubit porque solo guarda un dato derivado.
class AvatarCubit extends Cubit<Uint8List?> {
  AvatarCubit(this._repository) : super(null);

  final ProfileRepository _repository;

  /// Baja mi foto. Sin foto (404), sin permiso o sin red no pasa nada: se quedan las iniciales.
  Future<void> load() async {
    try {
      show(await _repository.avatar());
    } on Object {
      emit(null);
    }
  }

  /// Muestra estos bytes. Algo que no parece una imagen se descarta: es mejor ver las iniciales
  /// que una foto rota.
  void show(Uint8List? bytes) => emit(bytes != null && _looksLikeImage(bytes) ? bytes : null);

  void clear() => emit(null);

  /// El servidor guarda siempre un JPEG, pero se aceptan también PNG por si cambia.
  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final png = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    return jpeg || png;
  }
}
