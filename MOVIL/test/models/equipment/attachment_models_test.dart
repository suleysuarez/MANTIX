import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/equipment/attachment_models.dart';

AttachmentFile file(String name, {int bytes = 100}) => AttachmentFile(path: '/c/$name', name: name, size: bytes);

void main() {
  group('AttachmentRules.validate', () {
    test('acepta JPG, JPEG y PNG como fotos y PDF y TXT como documentos', () {
      for (final name in ['a.jpg', 'a.JPG', 'a.jpeg', 'a.png']) {
        expect(AttachmentRules.validate(file(name), AttachmentSource.camera), isNull, reason: name);
        expect(AttachmentRules.validate(file(name), AttachmentSource.gallery), isNull, reason: name);
      }
      for (final name in ['a.pdf', 'a.TXT']) {
        expect(AttachmentRules.validate(file(name), AttachmentSource.document), isNull, reason: name);
      }
    });

    test('las fotos no pueden ser PDF ni TXT y los documentos no pueden ser imágenes', () {
      expect(AttachmentRules.validate(file('a.pdf'), AttachmentSource.camera), contains('Tipo de archivo no permitido'));
      expect(AttachmentRules.validate(file('a.jpg'), AttachmentSource.document), contains('Usa: pdf, txt'));
    });

    test('rechaza HEIC y HEIF con su propio mensaje', () {
      for (final name in ['a.heic', 'a.HEIF']) {
        expect(AttachmentRules.validate(file(name), AttachmentSource.gallery), 'Las fotos HEIC no se admiten. Usa una foto JPG o PNG.');
      }
    });

    test('rechaza lo vacío y lo que pasa de 10 MB, con mensaje distinto para fotos', () {
      expect(AttachmentRules.validate(file('a.pdf', bytes: 0), AttachmentSource.document), 'El archivo está vacío.');
      expect(AttachmentRules.validate(file('a.pdf', bytes: AttachmentRules.maxBytes), AttachmentSource.document), isNull);
      expect(AttachmentRules.validate(file('a.pdf', bytes: AttachmentRules.maxBytes + 1), AttachmentSource.document), 'El archivo supera el máximo de 10 MB.');
      expect(AttachmentRules.validate(file('a.jpg', bytes: AttachmentRules.maxBytes + 1), AttachmentSource.camera), contains('La foto pesa más de 10 MB'));
    });

    test('sin extensión no es válido', () {
      expect(AttachmentRules.validate(file('foto'), AttachmentSource.camera), contains('Tipo de archivo no permitido'));
    });

    test('los límites son los del servidor', () {
      expect(AttachmentRules.maxFiles, 5);
      expect(AttachmentRules.maxBytes, 10 * 1024 * 1024);
    });
  });

  group('sanitizeFileName', () {
    test('quita rutas, caracteres de control y símbolos raros', () {
      expect(sanitizeFileName('/storage/emulated/0/DCIM/foto.jpg'), 'foto.jpg');
      expect(sanitizeFileName(r'C:\Users\ana\ficha.pdf'), 'ficha.pdf');
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName('ficha\u0000\u0007.pdf'), 'ficha.pdf');
      expect(sanitizeFileName('a<b>:c|d?.txt'), 'a_b__c_d_.txt');
    });

    test('conserva letras con tilde y la ñ', () {
      expect(sanitizeFileName('Instalación niño.pdf'), 'Instalación niño.pdf');
    });

    test('colapsa espacios y puntos repetidos y no deja nombres ocultos', () {
      expect(sanitizeFileName('mi    foto..jpg'), 'mi foto.jpg');
      expect(sanitizeFileName('...oculto.txt'), 'oculto.txt');
    });

    test('un nombre vacío queda como «archivo»', () {
      expect(sanitizeFileName(''), 'archivo');
      expect(sanitizeFileName('   '), 'archivo');
      expect(sanitizeFileName('/'), 'archivo');
    });

    test('un nombre muy largo se recorta y conserva la extensión', () {
      final result = sanitizeFileName('${'a' * 300}.pdf');

      expect(result.length, 100);
      expect(result, endsWith('.pdf'));
    });
  });

  group('AttachmentDraft', () {
    test('copyWith cambia el estado y puede limpiar el fallo', () {
      final draft = AttachmentDraft(id: 1, file: file('a.jpg'), status: AttachmentStatus.failed, failureMessage: 'Sin conexión');

      final retried = draft.copyWith(status: AttachmentStatus.uploading, clearFailure: true);

      expect(retried.status, AttachmentStatus.uploading);
      expect(retried.failureMessage, isNull);
      expect(retried.file, draft.file);
    });
  });
}
