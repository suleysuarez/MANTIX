import 'package:file_picker/file_picker.dart';

import '../models/equipment/attachment_models.dart';

/// Elegir un documento (PDF o TXT) con el selector del sistema. Es una interfaz para poder
/// simularla en las pruebas: ningún Bloc usa el plugin directamente.
abstract class FilePickerService {
  /// El documento elegido, o `null` si el usuario cancela.
  Future<AttachmentFile?> pickDocument();

  /// Borra las copias temporales que el selector deja en la caché de la app.
  Future<void> clearTemporaryFiles();
}

class SystemFilePickerService implements FilePickerService {
  const SystemFilePickerService();

  @override
  Future<AttachmentFile?> pickDocument() async {
    // Este selector devuelve la ruta del archivo (una copia en la caché), no sus bytes.
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: AttachmentRules.documentExtensions.toList());
    final path = file?.path;
    if (file == null || path == null) return null;
    return AttachmentFile(path: path, name: file.name, size: await file.length() ?? 0);
  }

  @override
  Future<void> clearTemporaryFiles() => FilePicker.clearTemporaryFiles();
}
