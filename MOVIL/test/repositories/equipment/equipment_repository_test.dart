import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/attachment_models.dart';
import 'package:mantix/models/equipment/equipment_models.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';

import '../../models/equipment/equipment_models_test.dart' show equipmentItemJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  group('listEquipment', () {
    test('pide size=20, ordena por fecha y lee la paginación de las cabeceras', () async {
      final adapter = FakeAdapter((_) => pagedResponse([equipmentItemJson()], totalPages: 3, total: 41));
      final result = await EquipmentRepository(dioWith(adapter)).listEquipment();

      final request = adapter.requests.single;
      expect(request.path, '/equipment');
      expect(request.queryParameters, {'page': 1, 'size': 20, 'sort': '-created_at'});
      expect(result.items.single.assetTag, 'DEMO-007');
      expect(result.info!.total, 41);
      expect(result.hasNext, isTrue);
    });

    test('envía el estado y la búsqueda solo cuando hay filtro, y recorta el texto', () async {
      final adapter = FakeAdapter((_) => pagedResponse([]));
      await EquipmentRepository(dioWith(adapter)).listEquipment(page: 2, statuses: 'assigned,in_storage', search: '  dell ');

      expect(adapter.requests.single.queryParameters, containsPair('page', 2));
      expect(adapter.requests.single.queryParameters, containsPair('status', 'assigned,in_storage'));
      expect(adapter.requests.single.queryParameters, containsPair('search', 'dell'));
    });

    test('un texto en blanco o un estado vacío no se envían', () async {
      final adapter = FakeAdapter((_) => pagedResponse([]));
      await EquipmentRepository(dioWith(adapter)).listEquipment(statuses: '', search: '   ');

      expect(adapter.requests.single.queryParameters.keys, isNot(contains('status')));
      expect(adapter.requests.single.queryParameters.keys, isNot(contains('search')));
    });

    test('un 403 sale como ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403));
      expect(EquipmentRepository(dioWith(adapter)).listEquipment(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('summary', () {
    test('lee los contadores', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, {'total': 5, 'by_status': {'assigned': 3, 'in_repair': 2}}));
      final summary = await EquipmentRepository(dioWith(adapter)).summary();

      expect(adapter.requests.single.path, '/equipment/summary');
      expect(summary.total, 5);
      expect(summary.byStatus['in_repair'], 2);
    });

    test('un error del servidor sale como Failure sin detalles internos', () async {
      final adapter = FakeAdapter((_) => errorResponse(500));
      await expectLater(EquipmentRepository(dioWith(adapter)).summary(), throwsA(isA<ServerFailure>()));
    });
  });
  group('types', () {
    test('lee las categorías', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [
            {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
            {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
          ]));
      final types = await EquipmentRepository(dioWith(adapter)).types();

      expect(adapter.requests.single.path, '/equipment/types');
      expect(types.map((t) => t.name), ['Laptop', 'Impresora']);
    });
  });

  group('create', () {
    const equipment = NewEquipment(assetTag: 'EQ-029', typeId: 1, brand: 'Dell', model: 'Latitude');

    test('hace POST con el cuerpo del formulario, devuelve el equipo y avisa del cambio', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, equipmentItemJson()));
      final repository = EquipmentRepository(dioWith(adapter));
      var changes = 0;
      final subscription = repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);

      final created = await repository.create(equipment);
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/equipment');
      expect(adapter.requests.single.data, equipment.toJson());
      expect(created.assetTag, 'DEMO-007');
      expect(changes, 1);
    });

    test('una etiqueta repetida sale como ConflictFailure con su código y no avisa del cambio', () async {
      final adapter = FakeAdapter((_) => errorResponse(409, code: 'equipment_identifier_taken'));
      final repository = EquipmentRepository(dioWith(adapter));
      var changes = 0;
      final subscription = repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);

      await expectLater(repository.create(equipment), throwsA(isA<ConflictFailure>().having((f) => f.code, 'code', 'equipment_identifier_taken')));
      await Future<void>.delayed(Duration.zero);

      expect(changes, 0);
    });

    test('un 422 trae los errores por campo', () async {
      final adapter = FakeAdapter((_) => errorResponse(422, errors: [
            {'field': 'brand', 'message': 'Campo requerido', 'type': 'missing'},
          ]));

      await expectLater(
        EquipmentRepository(dioWith(adapter)).create(equipment),
        throwsA(isA<ValidationFailure>().having((f) => f.fieldErrors.keys, 'campos', contains('brand'))),
      );
    });
  });
  group('listEquipment con página, tamaño y categoría', () {
    test('envía el tamaño de página y las categorías repetidas', () async {
      final adapter = FakeAdapter((_) => pagedResponse([]));
      await EquipmentRepository(dioWith(adapter)).listEquipment(page: 3, size: 50, typeIds: [2, 5]);

      expect(adapter.requests.single.queryParameters, {'page': 3, 'size': 50, 'sort': '-created_at', 'equipment_type_id': [2, 5]});
    });
  });

  group('locations y custodios', () {
    test('locations lee las ubicaciones', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [
            {'id': 3, 'code': 'HQ', 'name': 'Sede central', 'kind': 'site', 'parent_id': null},
          ]));
      final locations = await EquipmentRepository(dioWith(adapter)).locations();

      expect(adapter.requests.single.path, '/locations');
      expect(locations.single.name, 'Sede central');
    });

    test('custodianCandidates busca por texto recortado y lee usuarios', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [
            {'id': 9, 'full_name': 'Ana Pérez', 'email': 'ana@example.com'},
          ]));
      final candidates = await EquipmentRepository(dioWith(adapter)).custodianCandidates('  ana ');

      expect(adapter.requests.single.path, '/equipment/custodian-candidates');
      expect(adapter.requests.single.queryParameters, {'search': 'ana'});
      expect(candidates.single.fullName, 'Ana Pérez');
    });

    test('custodianCandidates sin texto no envía búsqueda', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, []));
      await EquipmentRepository(dioWith(adapter)).custodianCandidates('  ');

      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('assignLocation y assignCustody hacen POST con su cuerpo y avisan del cambio', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, equipmentItemJson()));
      final repository = EquipmentRepository(dioWith(adapter));
      var changes = 0;
      final subscription = repository.changes.listen((_) => changes++);
      addTearDown(subscription.cancel);

      await repository.assignLocation(7, 3);
      await repository.assignCustody(7, 9);
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests[0].path, '/equipment/7/location');
      expect(adapter.requests[0].data, {'location_id': 3});
      expect(adapter.requests[1].path, '/equipment/7/custody');
      expect(adapter.requests[1].data, {'assigned_to_user_id': 9});
      expect(changes, 2);
    });

    test('un 403 al asignar sale como ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403));

      await expectLater(EquipmentRepository(dioWith(adapter)).assignCustody(7, 9), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('uploadAttachment', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('mantix_upload_test_'));
    tearDown(() {
      // En Windows el adaptador simulado puede dejar abierto el archivo; no es un fallo de la prueba.
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Se limpia con la carpeta temporal del sistema.
      }
    });

    AttachmentFile fileOnDisk(String name, {int bytes = 4096}) {
      final file = File('${directory.path}${Platform.pathSeparator}$name')..writeAsBytesSync(Uint8List(bytes));
      return AttachmentFile(path: file.path, name: name, size: bytes);
    }

    test('envía el archivo desde su ruta, como multipart «file», con el nombre saneado y su tipo', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, {'id': 1}));
      final file = fileOnDisk('foto.jpg');

      await EquipmentRepository(dioWith(adapter)).uploadAttachment(7, AttachmentFile(path: file.path, name: '/storage/DCIM/mi   foto?.jpg', size: file.size));

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/equipment/7/attachments');
      final form = request.data as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'mi foto_.jpg');
      expect(form.files.single.value.contentType.toString(), 'image/jpeg');
    });

    test('cada extensión viaja con su tipo', () async {
      final types = <String?>[];
      final adapter = FakeAdapter((options) {
        types.add((options.data as FormData).files.single.value.contentType?.mimeType);
        return jsonResponse(201, {});
      });
      final repository = EquipmentRepository(dioWith(adapter));

      for (final name in ['a.png', 'b.pdf', 'c.txt']) {
        await repository.uploadAttachment(7, fileOnDisk(name));
      }

      expect(types, ['image/png', 'application/pdf', 'text/plain']);
    });

    test('informa el avance de 0 a 1 mientras se envía', () async {
      final progress = <double>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = _ReadingAdapter();

      await EquipmentRepository(dio).uploadAttachment(7, fileOnDisk('grande.pdf', bytes: 300000), onProgress: progress.add);

      expect(progress, isNotEmpty);
      expect(progress.last, 1);
      expect(progress.every((value) => value > 0 && value <= 1), isTrue);
    });

    test('no sube un archivo que ya no existe (falla antes de enviar nada)', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, {}));

      await expectLater(
        EquipmentRepository(dioWith(adapter)).uploadAttachment(7, AttachmentFile(path: '${directory.path}/borrado.jpg', name: 'borrado.jpg', size: 10)),
        throwsA(isA<FileSystemException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('un 413 llega como fallo de datos con el mensaje de «demasiado grande»', () async {
      final adapter = FakeAdapter((_) => errorResponse(413, code: 'payload_too_large'));

      await expectLater(
        EquipmentRepository(dioWith(adapter)).uploadAttachment(7, fileOnDisk('a.pdf')),
        throwsA(isA<ValidationFailure>().having((f) => f.message, 'message', 'El archivo supera el tamaño máximo permitido (10 MB).')),
      );
    });

    test('un 415 llega como fallo de datos con el mensaje de «tipo no admitido»', () async {
      final adapter = FakeAdapter((_) => errorResponse(415, code: 'unsupported_media_type'));

      await expectLater(
        EquipmentRepository(dioWith(adapter)).uploadAttachment(7, fileOnDisk('a.pdf')),
        throwsA(isA<ValidationFailure>().having((f) => f.message, 'message', contains('Tipo de archivo o formato no admitido'))),
      );
    });

    test('un 413 o un 415 con un código desconocido conservan su mensaje por estado', () async {
      for (final (status, text) in [(413, 'tamaño máximo'), (415, 'no admitido')]) {
        final adapter = FakeAdapter((_) => errorResponse(status, code: 'codigo_nuevo'));

        await expectLater(
          EquipmentRepository(dioWith(adapter)).uploadAttachment(7, fileOnDisk('a.pdf')),
          throwsA(isA<ValidationFailure>().having((f) => f.message, 'message', contains(text))),
        );
      }
    });

    test('un 422 trae los errores por campo', () async {
      final adapter = FakeAdapter((_) => errorResponse(422, errors: [
            {'field': 'file', 'message': 'El contenido no coincide con la extensión.', 'type': 'value_error'},
          ]));

      await expectLater(
        EquipmentRepository(dioWith(adapter)).uploadAttachment(7, fileOnDisk('a.pdf')),
        throwsA(isA<ValidationFailure>().having((f) => f.fieldErrors['file'], 'file', contains('no coincide'))),
      );
    });

    test('sin permiso (403) y con el máximo de adjuntos (409) usan sus mensajes específicos', () async {
      await expectLater(
        EquipmentRepository(dioWith(FakeAdapter((_) => errorResponse(403, code: 'attachment_equipment_forbidden')))).uploadAttachment(7, fileOnDisk('a.pdf')),
        throwsA(isA<ForbiddenFailure>().having((f) => f.message, 'message', 'No tienes permiso para adjuntar archivos a equipos.')),
      );
      await expectLater(
        EquipmentRepository(dioWith(FakeAdapter((_) => errorResponse(409, code: 'attachment_limit_reached')))).uploadAttachment(7, fileOnDisk('a.pdf')),
        throwsA(isA<ConflictFailure>().having((f) => f.message, 'message', 'Se alcanzó el máximo de archivos adjuntos.')),
      );
    });
  });

  group('downloadEquipmentReport', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('mantix_download_test_'));
    tearDown(() {
      // En Windows el adaptador simulado puede dejar abierto el archivo; no es un fallo de la prueba.
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Se limpia con la carpeta temporal del sistema.
      }
    });

    ResponseBody bytes(List<int> data, {int status = 200}) =>
        ResponseBody.fromBytes(data, status, headers: {'content-length': ['${data.length}']});

    test('descarga en streaming al archivo indicado con el formato y los filtros', () async {
      final adapter = FakeAdapter((_) => bytes(List.filled(1000, 7)));
      final path = '${directory.path}/equipos.xlsx';

      await EquipmentRepository(dioWith(adapter)).downloadEquipmentReport(format: 'xlsx', savePath: path, statuses: 'in_repair', typeId: 2);

      final request = adapter.requests.single;
      expect(request.path, '/reports/equipment');
      expect(request.queryParameters, {'format': 'xlsx', 'status': 'in_repair', 'equipment_type_id': 2});
      expect(File(path).lengthSync(), 1000);
      expect(request.receiveTimeout, const Duration(seconds: 120));
    });

    test('sin filtros solo envía el formato', () async {
      final adapter = FakeAdapter((_) => bytes([1, 2, 3]));

      await EquipmentRepository(dioWith(adapter)).downloadEquipmentReport(format: 'csv', savePath: '${directory.path}/e.csv', statuses: '');

      expect(adapter.requests.single.queryParameters, {'format': 'csv'});
    });

    test('informa el avance hasta el 100 %', () async {
      final adapter = FakeAdapter((_) => bytes(List.filled(2000, 1)));
      final progress = <double>[];

      await EquipmentRepository(dioWith(adapter)).downloadEquipmentReport(format: 'pdf', savePath: '${directory.path}/e.pdf', onProgress: progress.add);

      expect(progress.last, 1);
    });

    test('un 403 sale como ForbiddenFailure y no deja el archivo a medias', () async {
      final adapter = FakeAdapter((_) => errorResponse(403));
      final path = '${directory.path}/e.xlsx';

      await expectLater(EquipmentRepository(dioWith(adapter)).downloadEquipmentReport(format: 'xlsx', savePath: path), throwsA(isA<ForbiddenFailure>()));
      expect(File(path).existsSync(), isFalse);
    });

    test('sin conexión sale como NetworkFailure', () async {
      final adapter = FakeAdapter((options) => throw DioException(requestOptions: options, type: DioExceptionType.connectionError));

      await expectLater(
        EquipmentRepository(dioWith(adapter)).downloadEquipmentReport(format: 'xlsx', savePath: '${directory.path}/e.xlsx'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}

/// Adaptador que lee el cuerpo enviado, como hace uno real, para que Dio informe el avance.
class _ReadingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    await requestStream?.drain<void>();
    return jsonResponse(201, {'id': 1});
  }

  @override
  void close({bool force = false}) {}
}
