import 'dart:io';

/// Archivos temporales de la app (por ejemplo, el inventario exportado antes de compartirlo).
/// Interfaz para poder simularla en las pruebas sin tocar el disco.
abstract class TempFileService {
  /// Ruta de un archivo temporal nuevo con ese nombre; todavía no existe.
  Future<String> createPath(String fileName);

  /// Tamaño en bytes del archivo (0 si no existe).
  Future<int> length(String path);

  /// Borra el archivo temporal y la carpeta que lo contiene.
  Future<void> delete(String path);
}

class SystemTempFileService implements TempFileService {
  const SystemTempFileService();

  @override
  Future<String> createPath(String fileName) async {
    final directory = await Directory.systemTemp.createTemp('mantix_');
    return '${directory.path}${Platform.pathSeparator}$fileName';
  }

  @override
  Future<int> length(String path) async {
    final file = File(path);
    return await file.exists() ? file.length() : 0;
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    final directory = file.parent;
    if (await file.exists()) await file.delete();
    // La carpeta la creamos nosotros para este archivo: solo se borra si está vacía.
    if (await directory.exists() && directory.path != Directory.systemTemp.path && (await directory.list().isEmpty)) await directory.delete();
  }
}
