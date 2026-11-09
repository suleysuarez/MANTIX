import 'package:equatable/equatable.dart';

import '../../core/validation/validators.dart';

/// Un archivo elegido por el usuario (cámara, galería o documentos). Solo guarda la ruta, el
/// nombre y el tamaño: el contenido nunca se carga entero en memoria.
class AttachmentFile extends Equatable {
  const AttachmentFile({required this.path, required this.name, required this.size});

  final String path;
  final String name;

  /// Tamaño en bytes.
  final int size;

  @override
  List<Object?> get props => [path, name, size];
}

/// De dónde sale un adjunto.
enum AttachmentSource { camera, gallery, document }

/// Límites de los adjuntos de un equipo; el backend es la fuente de verdad y los repite.
abstract final class AttachmentRules {
  static const maxFiles = 5;
  static const maxBytes = 10 * 1024 * 1024;
  static const imageExtensions = {'jpg', 'jpeg', 'png'};
  static const documentExtensions = {'pdf', 'txt'};

  /// Extensiones aceptadas según de dónde viene el archivo.
  static Set<String> allowedFor(AttachmentSource source) => source == AttachmentSource.document ? documentExtensions : imageExtensions;

  static String extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  /// Mensaje en español si [file] no se puede adjuntar; `null` si es válido.
  static String? validate(AttachmentFile file, AttachmentSource source) {
    final extension = extensionOf(file.name);
    if (extension == 'heic' || extension == 'heif') return 'Las fotos HEIC no se admiten. Usa una foto JPG o PNG.';
    final message = Validators.attachment(
      fileName: file.name,
      sizeBytes: file.size,
      allowedExtensions: allowedFor(source),
      maxBytes: maxBytes,
    );
    if (message == null) return null;
    final isPhoto = source != AttachmentSource.document;
    if (isPhoto && file.size > maxBytes) return 'La foto pesa más de 10 MB aun después de comprimirla. Prueba con otra de menor resolución.';
    return message;
  }
}

/// Deja un nombre de archivo seguro para enviarlo: sin rutas, sin caracteres de control ni
/// símbolos raros, sin espacios repetidos y con un largo razonable que conserva la extensión.
String sanitizeFileName(String name, {int maxLength = 100}) {
  final base = name.split(RegExp(r'[\\/]')).last;
  var clean = base.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').replaceAll(RegExp(r'[^\p{L}\p{N}._ -]', unicode: true), '_');
  clean = clean.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'\.{2,}'), '.').trim();
  clean = clean.replaceFirst(RegExp(r'^[.\s]+'), '');
  if (clean.isEmpty) return 'archivo';
  if (clean.length > maxLength) {
    final dot = clean.lastIndexOf('.');
    final extension = dot > 0 && clean.length - dot <= 10 ? clean.substring(dot) : '';
    clean = clean.substring(0, maxLength - extension.length) + extension;
  }
  return clean;
}

enum AttachmentStatus { pending, uploading, done, failed }

/// Un adjunto del formulario, con su estado de subida.
class AttachmentDraft extends Equatable {
  const AttachmentDraft({required this.id, required this.file, this.status = AttachmentStatus.pending, this.progress = 0, this.failureMessage});

  final int id;
  final AttachmentFile file;
  final AttachmentStatus status;

  /// Avance de la subida, de 0 a 1.
  final double progress;
  final String? failureMessage;

  AttachmentDraft copyWith({AttachmentStatus? status, double? progress, String? failureMessage, bool clearFailure = false}) => AttachmentDraft(
        id: id,
        file: file,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
      );

  @override
  List<Object?> get props => [id, file, status, progress, failureMessage];
}
