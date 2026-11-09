import 'package:image_picker/image_picker.dart';

import '../models/equipment/attachment_models.dart';

/// Tomar una foto o elegirla de la galería. Interfaz simulable en pruebas: ningún Bloc usa el
/// plugin directamente.
abstract class ImagePickerService {
  /// La foto tomada con la cámara, o `null` si el usuario cancela.
  Future<AttachmentFile?> takePhoto();

  /// La foto elegida de la galería, o `null` si el usuario cancela.
  Future<AttachmentFile?> pickFromGallery();

  /// Si Android cerró la app mientras se tomaba la foto, la devuelve al volver (una sola vez).
  Future<AttachmentFile?> recoverLostPhoto();
}

class SystemImagePickerService implements ImagePickerService {
  SystemImagePickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Calidad y tamaño máximo: una foto de móvil actual (12 MP o más) queda muy por debajo de
  /// 10 MB y se sigue viendo bien. Sin metadatos completos no se pide ningún permiso extra.
  static const _quality = 85;
  static const _maxSide = 2048.0;

  Future<AttachmentFile?> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: _quality,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      requestFullMetadata: false,
    );
    return file == null ? null : _fromXFile(file);
  }

  static Future<AttachmentFile> _fromXFile(XFile file) async => AttachmentFile(path: file.path, name: file.name, size: await file.length());

  @override
  Future<AttachmentFile?> takePhoto() => _pick(ImageSource.camera);

  @override
  Future<AttachmentFile?> pickFromGallery() => _pick(ImageSource.gallery);

  @override
  Future<AttachmentFile?> recoverLostPhoto() async {
    final lost = await _picker.retrieveLostData();
    final file = lost.file;
    if (lost.isEmpty || file == null || lost.type != RetrieveType.image) return null;
    return _fromXFile(file);
  }
}
