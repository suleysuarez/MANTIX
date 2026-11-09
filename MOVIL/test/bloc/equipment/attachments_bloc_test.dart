import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/equipment/attachments_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/attachment_models.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/device_fakes.dart';

class _MockEquipmentRepository extends Mock implements EquipmentRepository {}

const _mb = 1024 * 1024;

void main() {
  late _MockEquipmentRepository repository;
  late FakeImagePicker images;
  late FakeFilePicker files;

  setUpAll(() => registerFallbackValue(fakeFile('x.jpg')));

  setUp(() {
    repository = _MockEquipmentRepository();
    images = FakeImagePicker();
    files = FakeFilePicker();
    when(() => repository.uploadAttachment(any(), any(), onProgress: any(named: 'onProgress'))).thenAnswer((invocation) async {
      final onProgress = invocation.namedArguments[#onProgress] as void Function(double)?;
      onProgress?.call(0.5);
      onProgress?.call(1);
    });
  });

  AttachmentsBloc newBloc() {
    final bloc = AttachmentsBloc(repository: repository, images: images, files: files);
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> pick(AttachmentsBloc bloc, AttachmentSource source) async {
    bloc.add(AttachmentPickRequested(source));
    await bloc.stream.firstWhere((s) => !s.picking);
  }

  group('foto con la cámara', () {
    test('una foto tomada se añade a la lista', () async {
      images.photo = fakeFile('IMG_1.jpg', bytes: 3 * _mb);
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.camera);

      expect(images.takeCalls, 1);
      expect(bloc.state.drafts.map((d) => d.file.name), ['IMG_1.jpg']);
      expect(bloc.state.drafts.single.status, AttachmentStatus.pending);
      expect(bloc.state.notice, isNull);
    });

    test('si el usuario cancela no se añade nada ni se avisa de nada', () async {
      images.photo = null;
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.camera);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice, isNull);
      expect(bloc.state.picking, isFalse);
    });

    test('una foto de más de 10 MB aun comprimida se rechaza con un mensaje claro', () async {
      images.photo = fakeFile('grande.jpg', bytes: 11 * _mb);
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.camera);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice!.isError, isTrue);
      expect(bloc.state.notice!.message, contains('La foto pesa más de 10 MB aun después de comprimirla'));
    });

    test('una foto HEIC se rechaza', () async {
      images.gallery = fakeFile('IMG_9.heic');
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.gallery);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice!.message, contains('HEIC'));
    });

    test('solo se aceptan JPG y PNG: un WEBP de la galería se rechaza', () async {
      images.gallery = fakeFile('captura.webp');
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.gallery);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice!.message, allOf(contains('«captura.webp»'), contains('Tipo de archivo no permitido')));
    });

    test('JPG, JPEG y PNG de la galería se aceptan', () async {
      final bloc = newBloc();
      for (final name in ['a.jpg', 'b.JPEG', 'c.png']) {
        images.gallery = fakeFile(name);
        await pick(bloc, AttachmentSource.gallery);
      }

      expect(bloc.state.drafts.map((d) => d.file.name), ['a.jpg', 'b.JPEG', 'c.png']);
    });

    test('una foto vacía se rechaza', () async {
      images.photo = fakeFile('vacia.jpg', bytes: 0);
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.camera);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice!.message, contains('vacío'));
    });

    test('si la cámara falla se avisa sin detalles internos', () async {
      images.error = StateError('camera_access_denied: detalle interno');
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.camera);

      expect(bloc.state.notice!.message, 'No pudimos abrir la cámara. Inténtalo de nuevo.');
      expect(bloc.state.notice!.message, isNot(contains('detalle interno')));
      expect(bloc.state.picking, isFalse);
    });
  });

  group('documentos', () {
    test('un PDF o un TXT se aceptan', () async {
      final bloc = newBloc();
      files.document = fakeFile('ficha.pdf');
      await pick(bloc, AttachmentSource.document);
      files.document = fakeFile('notas.txt');
      await pick(bloc, AttachmentSource.document);

      expect(bloc.state.drafts.map((d) => d.file.name), ['ficha.pdf', 'notas.txt']);
    });

    test('desde documentos no se aceptan imágenes ni otros tipos', () async {
      final bloc = newBloc();
      files.document = fakeFile('hoja.xlsx');
      await pick(bloc, AttachmentSource.document);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice!.message, allOf(contains('«hoja.xlsx»'), contains('Usa: pdf, txt')));
    });

    test('un documento de más de 10 MB se rechaza', () async {
      files.document = fakeFile('manual.pdf', bytes: 10 * _mb + 1);
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.document);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice!.message, contains('supera el máximo de 10 MB'));
    });

    test('exactamente 10 MB se acepta', () async {
      files.document = fakeFile('justo.pdf', bytes: 10 * _mb);
      final bloc = newBloc();

      await pick(bloc, AttachmentSource.document);

      expect(bloc.state.drafts, hasLength(1));
    });
  });

  group('tope de cinco', () {
    test('cuenta fotos y archivos juntos y no vuelve a abrir el selector', () async {
      final bloc = newBloc();
      for (var i = 1; i <= 3; i++) {
        images.photo = fakeFile('foto$i.jpg');
        await pick(bloc, AttachmentSource.camera);
      }
      for (var i = 1; i <= 2; i++) {
        files.document = fakeFile('ficha$i.pdf');
        await pick(bloc, AttachmentSource.document);
      }
      expect(bloc.state.drafts, hasLength(5));
      expect(bloc.state.isFull, isTrue);

      bloc.add(const AttachmentPickRequested(AttachmentSource.camera));
      final notice = (await bloc.stream.firstWhere((s) => s.notice != null)).notice!;

      expect(notice.message, 'Ya adjuntaste el máximo de 5 archivos.');
      expect(images.takeCalls, 3, reason: 'no se abre la cámara si ya está lleno');
      expect(bloc.state.drafts, hasLength(5));
    });

    test('quitar uno libera un hueco', () async {
      final bloc = newBloc();
      for (var i = 1; i <= 5; i++) {
        images.gallery = fakeFile('f$i.jpg');
        await pick(bloc, AttachmentSource.gallery);
      }

      bloc.add(AttachmentRemoved(bloc.state.drafts.first.id));
      await bloc.stream.firstWhere((s) => s.drafts.length == 4);

      expect(bloc.state.isFull, isFalse);
    });

    test('el mismo archivo no se añade dos veces', () async {
      images.gallery = fakeFile('igual.jpg');
      final bloc = newBloc();
      await pick(bloc, AttachmentSource.gallery);

      bloc.add(const AttachmentPickRequested(AttachmentSource.gallery));
      final notice = (await bloc.stream.firstWhere((s) => s.notice != null)).notice!;

      expect(notice.message, 'Ese archivo ya está en la lista.');
      expect(bloc.state.drafts, hasLength(1));
    });
  });

  group('pérdida de datos de Android', () {
    test('recupera la foto que se estaba tomando cuando el sistema cerró la app', () async {
      images.lost = fakeFile('recuperada.jpg');
      final bloc = newBloc();

      bloc.add(const LostPhotoRecoveryRequested());
      await bloc.stream.firstWhere((s) => s.drafts.isNotEmpty);

      expect(bloc.state.drafts.single.file.name, 'recuperada.jpg');
      expect(bloc.state.notice!.isError, isFalse);
      expect(bloc.state.notice!.message, contains('Recuperamos la foto'));
    });

    test('la foto recuperada también pasa por las validaciones', () async {
      images.lost = fakeFile('enorme.jpg', bytes: 12 * _mb);
      final bloc = newBloc();

      bloc.add(const LostPhotoRecoveryRequested());
      await bloc.stream.firstWhere((s) => s.notice != null);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice!.isError, isTrue);
    });

    test('sin datos perdidos no cambia nada, y se entrega una sola vez', () async {
      images.lost = fakeFile('una-vez.jpg');
      final bloc = newBloc();
      bloc.add(const LostPhotoRecoveryRequested());
      await bloc.stream.firstWhere((s) => s.drafts.isNotEmpty);

      bloc.add(const LostPhotoRecoveryRequested());
      await Future<void>.delayed(Duration.zero);

      expect(images.recoverCalls, 2);
      expect(bloc.state.drafts, hasLength(1));
    });

    test('si recuperar falla, el formulario sigue como si nada', () async {
      images.lostError = StateError('fallo del plugin');
      final bloc = newBloc();

      bloc.add(const LostPhotoRecoveryRequested());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.drafts, isEmpty);
      expect(bloc.state.notice, isNull);
    });
  });

  group('subida', () {
    Future<AttachmentsBloc> withFiles(List<String> names) async {
      final bloc = newBloc();
      for (final name in names) {
        images.gallery = fakeFile(name);
        await pick(bloc, AttachmentSource.gallery);
      }
      return bloc;
    }

    test('sube cada adjunto al equipo creado, en orden, con progreso', () async {
      final bloc = await withFiles(['a.jpg', 'b.png']);
      final progress = <double>[];
      bloc.stream.listen((s) {
        for (final d in s.drafts) {
          if (d.status == AttachmentStatus.uploading) progress.add(d.progress);
        }
      });

      bloc.add(const AttachmentsUploadRequested(7));
      await bloc.stream.firstWhere((s) => !s.uploading && s.allDone);

      verifyInOrder([
        () => repository.uploadAttachment(7, fakeFile('a.jpg'), onProgress: any(named: 'onProgress')),
        () => repository.uploadAttachment(7, fakeFile('b.png'), onProgress: any(named: 'onProgress')),
      ]);
      expect(bloc.state.drafts.every((d) => d.progress == 1), isTrue);
      expect(progress, contains(0.5), reason: 'se informa el avance');
      expect(bloc.state.equipmentId, 7);
      expect(files.clearCalls, 1, reason: 'sin fallos se limpia la caché del selector');
    });

    test('si una subida falla el resto sigue y se muestra el motivo de cada archivo', () async {
      when(() => repository.uploadAttachment(7, fakeFile('b.png'), onProgress: any(named: 'onProgress')))
          .thenThrow(const ValidationFailure(code: 'unsupported_media_type', message: 'Tipo de archivo o formato no admitido. Usa PDF, JPG, PNG o TXT.'));
      final bloc = await withFiles(['a.jpg', 'b.png', 'c.jpg']);

      bloc.add(const AttachmentsUploadRequested(7));
      await bloc.stream.firstWhere((s) => !s.uploading && s.drafts.every((d) => d.status != AttachmentStatus.pending));

      expect(bloc.state.drafts.map((d) => d.status), [AttachmentStatus.done, AttachmentStatus.failed, AttachmentStatus.done]);
      expect(bloc.state.drafts[1].failureMessage, 'Tipo de archivo o formato no admitido. Usa PDF, JPG, PNG o TXT.');
      expect(bloc.state.failedCount, 1);
      expect(bloc.state.doneCount, 2);
      expect(bloc.state.allDone, isFalse);
      expect(files.clearCalls, 0, reason: 'con fallos se conservan los archivos para reintentar');
    });

    test('reintentar vuelve a subir solo los fallidos', () async {
      var failB = true;
      when(() => repository.uploadAttachment(7, fakeFile('b.png'), onProgress: any(named: 'onProgress'))).thenAnswer((_) async {
        if (failB) throw const NetworkFailure();
      });
      final bloc = await withFiles(['a.jpg', 'b.png']);
      bloc.add(const AttachmentsUploadRequested(7));
      await bloc.stream.firstWhere((s) => !s.uploading && s.hasFailed);
      expect(bloc.state.drafts[1].failureMessage, contains('conectar'));
      clearInteractions(repository);

      failB = false;
      bloc.add(const AttachmentsRetryRequested());
      await bloc.stream.firstWhere((s) => !s.uploading && s.allDone);

      verify(() => repository.uploadAttachment(7, fakeFile('b.png'), onProgress: any(named: 'onProgress'))).called(1);
      verifyNever(() => repository.uploadAttachment(7, fakeFile('a.jpg'), onProgress: any(named: 'onProgress')));
      expect(bloc.state.drafts[1].failureMessage, isNull);
      expect(files.clearCalls, 1);
    });

    test('un adjunto fallido se puede quitar antes de reintentar, uno ya subido no', () async {
      when(() => repository.uploadAttachment(7, fakeFile('b.png'), onProgress: any(named: 'onProgress'))).thenThrow(const NetworkFailure());
      final bloc = await withFiles(['a.jpg', 'b.png']);
      bloc.add(const AttachmentsUploadRequested(7));
      await bloc.stream.firstWhere((s) => !s.uploading && s.hasFailed);

      bloc.add(AttachmentRemoved(bloc.state.drafts.first.id));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.drafts, hasLength(2), reason: 'lo subido se queda en la lista');

      bloc.add(AttachmentRemoved(bloc.state.drafts.last.id));
      await bloc.stream.firstWhere((s) => s.drafts.length == 1);
      expect(bloc.state.drafts.single.status, AttachmentStatus.done);
    });

    test('reintentar sin haber subido nada antes no hace nada', () async {
      final bloc = await withFiles(['a.jpg']);

      bloc.add(const AttachmentsRetryRequested());
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => repository.uploadAttachment(any(), any(), onProgress: any(named: 'onProgress')));
    });

    test('mientras sube no se abren selectores ni se quitan adjuntos', () async {
      final bloc = await withFiles(['a.jpg']);
      when(() => repository.uploadAttachment(7, fakeFile('a.jpg'), onProgress: any(named: 'onProgress'))).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      bloc.add(const AttachmentsUploadRequested(7));
      await bloc.stream.firstWhere((s) => s.uploading);

      bloc
        ..add(const AttachmentPickRequested(AttachmentSource.camera))
        ..add(AttachmentRemoved(bloc.state.drafts.single.id));
      await bloc.stream.firstWhere((s) => !s.uploading);

      expect(images.takeCalls, 0);
      expect(bloc.state.drafts, hasLength(1));
    });
  });
}
