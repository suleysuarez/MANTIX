import 'package:mantix/models/equipment/attachment_models.dart';
import 'package:mantix/services/device_services.dart';
import 'package:mantix/services/file_picker_service.dart';
import 'package:mantix/services/image_picker_service.dart';
import 'package:mantix/services/share_service.dart';
import 'package:mantix/services/temp_file_service.dart';

/// Simulacros de los servicios del teléfono: ninguna prueba llama a un plugin real.
class FakeImagePicker implements ImagePickerService {
  /// Lo que devolverá cada selector; `null` equivale a que el usuario cancele.
  AttachmentFile? photo;
  AttachmentFile? gallery;
  AttachmentFile? lost;

  /// Si no es `null`, el selector falla con este error.
  Object? error;
  Object? lostError;
  int takeCalls = 0;
  int galleryCalls = 0;
  int recoverCalls = 0;

  @override
  Future<AttachmentFile?> takePhoto() async {
    takeCalls++;
    if (error != null) throw error!;
    return photo;
  }

  @override
  Future<AttachmentFile?> pickFromGallery() async {
    galleryCalls++;
    if (error != null) throw error!;
    return gallery;
  }

  @override
  Future<AttachmentFile?> recoverLostPhoto() async {
    recoverCalls++;
    if (lostError != null) throw lostError!;
    final recovered = lost;
    lost = null; // Android entrega la foto perdida una sola vez.
    return recovered;
  }
}

class FakeFilePicker implements FilePickerService {
  AttachmentFile? document;
  Object? error;
  int pickCalls = 0;
  int clearCalls = 0;

  @override
  Future<AttachmentFile?> pickDocument() async {
    pickCalls++;
    if (error != null) throw error!;
    return document;
  }

  @override
  Future<void> clearTemporaryFiles() async => clearCalls++;
}

class FakeShare implements ShareService {
  final List<({String path, String? mimeType, String? subject})> shared = [];
  Object? error;

  @override
  Future<void> shareFile(String path, {String? mimeType, String? subject}) async {
    if (error != null) throw error!;
    shared.add((path: path, mimeType: mimeType, subject: subject));
  }
}

/// Archivos temporales en memoria: no toca el disco.
class FakeTempFiles implements TempFileService {
  /// Tamaño que dirá tener cualquier archivo creado.
  int size = 1024;
  final List<String> created = [];
  final List<String> deleted = [];
  Object? deleteError;

  @override
  Future<String> createPath(String fileName) async {
    final path = '/tmp/mantix_test/$fileName';
    created.add(path);
    return path;
  }

  @override
  Future<int> length(String path) async => size;

  @override
  Future<void> delete(String path) async {
    if (deleteError != null) throw deleteError!;
    deleted.add(path);
  }
}

/// Un archivo de [bytes] bytes con ese nombre, listo para devolverlo desde un selector simulado.
AttachmentFile fakeFile(String name, {int bytes = 2048}) => AttachmentFile(path: '/cache/$name', name: name, size: bytes);

DeviceServices fakeDevice({FakeImagePicker? images, FakeFilePicker? files, FakeShare? share, FakeTempFiles? temp}) =>
    DeviceServices(imagePicker: images ?? FakeImagePicker(), filePicker: files ?? FakeFilePicker(), share: share ?? FakeShare(), tempFiles: temp ?? FakeTempFiles());
