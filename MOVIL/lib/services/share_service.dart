import 'package:share_plus/share_plus.dart';

/// Compartir un archivo con la hoja de compartir del sistema. Interfaz simulable en pruebas:
/// ningún Bloc usa el plugin directamente.
abstract class ShareService {
  Future<void> shareFile(String path, {String? mimeType, String? subject});
}

class SystemShareService implements ShareService {
  const SystemShareService();

  @override
  Future<void> shareFile(String path, {String? mimeType, String? subject}) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: mimeType)], subject: subject));
  }
}
