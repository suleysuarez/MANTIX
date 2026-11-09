import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/models/equipment/attachment_models.dart';
import 'package:mantix/pages/equipment/create_equipment_screen.dart';
import 'package:mantix/pages/equipment/equipment_screen.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mantix/services/device_services.dart';

import '../../models/equipment/equipment_models_test.dart' show equipmentItemJson;
import '../../support/device_fakes.dart';
import '../../support/fakes.dart';
import '../../support/header_support.dart';
import '../../support/requests_support.dart';

/// Repositorio con la subida y la descarga simuladas: así no se toca el disco dentro de
/// `testWidgets` (donde la E/S real no avanza). Lo demás pasa por el adaptador falso de Dio.
class _Repo extends EquipmentRepository {
  _Repo(super.dio);

  final List<({int id, String name})> uploads = [];
  final List<({String format, String? statuses, int? typeId})> downloads = [];
  Object? Function(String name)? uploadFailure;
  Object? downloadFailure;

  @override
  Future<void> uploadAttachment(int equipmentId, AttachmentFile file, {void Function(double progress)? onProgress}) async {
    uploads.add((id: equipmentId, name: file.name));
    final failure = uploadFailure?.call(file.name);
    if (failure != null) throw failure;
    onProgress?.call(1);
  }

  @override
  Future<void> downloadEquipmentReport({
    required String format,
    required String savePath,
    String? statuses,
    int? typeId,
    void Function(double progress)? onProgress,
  }) async {
    downloads.add((format: format, statuses: statuses, typeId: typeId));
    if (downloadFailure != null) throw downloadFailure!;
  }
}

const _form = {'equipos:ver', 'equipos:crear'};
const _formAttach = {'equipos:ver', 'equipos:crear', 'equipos:adjuntar'};

void main() {
  late FakeAdapter adapter;
  late _Repo repository;
  late FakeImagePicker images;
  late FakeFilePicker files;
  late FakeShare share;
  late FakeTempFiles temp;
  late GoRouter router;

  setUp(() {
    adapter = FakeAdapter((options) => switch ((options.method, options.path)) {
          ('POST', '/equipment') => jsonResponse(201, equipmentItemJson(overrides: {'id': 7})),
          ('GET', '/equipment/types') => jsonResponse(200, [
              {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
            ]),
          ('GET', '/locations') => jsonResponse(200, []),
          ('GET', '/equipment/summary') => jsonResponse(200, {'total': 1, 'by_status': {'assigned': 1}}),
          ('GET', '/equipment') => pagedResponse([equipmentItemJson()]),
          _ => jsonResponse(404, {}),
        });
    repository = _Repo(dioWith(adapter));
    images = FakeImagePicker();
    files = FakeFilePicker();
    share = FakeShare();
    temp = FakeTempFiles();
  });

  Future<void> pump(WidgetTester tester, Set<String> permissions, {required String start}) async {
    tester.view.physicalSize = const Size(390, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => const Scaffold(body: Text('pantalla de inicio'))),
        GoRoute(path: CreateEquipmentScreen.path, builder: (_, _) => const CreateEquipmentScreen()),
        GoRoute(path: EquipmentScreen.path, builder: (_, _) => const EquipmentScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepositoryProvider<DeviceServices>.value(
        value: fakeDevice(images: images, files: files, share: share, temp: temp),
        child: RepositoryProvider<EquipmentRepository>.value(
          value: repository,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authenticatedBloc(testProfile(permissions: permissions))),
              BlocProvider<NotificationsBloc>.value(value: notificationsBloc()),
            ],
            child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push(start);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String optionKey) async {
    await tester.ensureVisible(find.byKey(const Key('attach-button')));
    await tester.tap(find.byKey(const Key('attach-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(optionKey)));
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSave(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('field-asset-tag')), 'EQ-029');
    await tester.enterText(find.byKey(const Key('field-brand')), 'Dell');
    await tester.enterText(find.byKey(const Key('field-model')), 'Latitude');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laptop').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GUARDAR EQUIPO'));
    await tester.tap(find.text('GUARDAR EQUIPO'));
    await tester.pumpAndSettle();
  }

  group('formulario: adjuntos', () {
    testWidgets('sin el permiso de adjuntar no hay sección de adjuntos', (tester) async {
      await pump(tester, _form, start: CreateEquipmentScreen.path);

      expect(find.byKey(const Key('attach-button')), findsNothing);
      expect(find.text('ADJUNTOS'), findsNothing);
      expect(images.recoverCalls, 0, reason: 'sin permiso tampoco se recupera una foto perdida');
    });

    testWidgets('con el permiso muestra la sección, el contador y recupera una foto perdida', (tester) async {
      images.lost = fakeFile('perdida.jpg');
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);

      expect(find.text('ADJUNTOS'), findsOneWidget);
      expect(images.recoverCalls, 1);
      expect(find.text('perdida.jpg'), findsOneWidget);
      expect(find.byKey(const Key('attach-counter')), findsOneWidget);
      expect(find.textContaining('1/5'), findsOneWidget);
      expect(find.text('Recuperamos la foto que estabas tomando.'), findsOneWidget);
    });

    testWidgets('«Adjuntar» ofrece tomar foto, elegir de la galería y elegir un archivo', (tester) async {
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);

      await tester.ensureVisible(find.byKey(const Key('attach-button')));
      await tester.tap(find.byKey(const Key('attach-button')));
      await tester.pumpAndSettle();

      expect(find.text('Tomar foto'), findsOneWidget);
      expect(find.text('Elegir de la galería'), findsOneWidget);
      expect(find.text('Elegir un archivo'), findsOneWidget);
    });

    testWidgets('cada opción abre su selector y añade lo elegido; se puede quitar', (tester) async {
      images.photo = fakeFile('foto.jpg');
      images.gallery = fakeFile('galeria.png');
      files.document = fakeFile('ficha.pdf');
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);

      await choose(tester, 'attach-camera');
      await choose(tester, 'attach-gallery');
      await choose(tester, 'attach-document');

      expect([images.takeCalls, images.galleryCalls, files.pickCalls], [1, 1, 1]);
      expect(find.text('foto.jpg'), findsOneWidget);
      expect(find.text('galeria.png'), findsOneWidget);
      expect(find.text('ficha.pdf'), findsOneWidget);
      expect(find.textContaining('3/5'), findsOneWidget);

      await tester.tap(find.byTooltip('Quitar galeria.png'));
      await tester.pumpAndSettle();

      expect(find.text('galeria.png'), findsNothing);
      expect(find.textContaining('2/5'), findsOneWidget);
    });

    testWidgets('un archivo no permitido se rechaza con un aviso en español', (tester) async {
      files.document = fakeFile('hoja.xlsx');
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);

      await choose(tester, 'attach-document');

      expect(find.text('hoja.xlsx'), findsNothing);
      expect(find.textContaining('«hoja.xlsx»'), findsOneWidget);
    });

    testWidgets('al llegar a cinco el botón avisa y se deshabilita', (tester) async {
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);
      for (var i = 1; i <= 5; i++) {
        images.gallery = fakeFile('f$i.jpg');
        await choose(tester, 'attach-gallery');
      }

      expect(find.textContaining('5/5'), findsOneWidget);
      expect(find.text('Máximo de 5 archivos'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('attach-button')));
      await tester.tap(find.byKey(const Key('attach-button')));
      await tester.pumpAndSettle();
      expect(find.text('Tomar foto'), findsNothing);
    });

    testWidgets('sin adjuntos, guardar vuelve atrás como siempre y no sube nada', (tester) async {
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);

      await fillAndSave(tester);

      expect(find.text('pantalla de inicio'), findsOneWidget);
      expect(find.text('Equipo registrado.'), findsOneWidget);
      expect(repository.uploads, isEmpty);
    });

    testWidgets('con adjuntos crea el equipo, los sube a su id y cierra con aviso', (tester) async {
      images.gallery = fakeFile('foto.jpg');
      files.document = fakeFile('ficha.pdf');
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);
      await choose(tester, 'attach-gallery');
      await choose(tester, 'attach-document');

      await fillAndSave(tester);

      expect(repository.uploads.map((u) => (u.id, u.name)), [(7, 'foto.jpg'), (7, 'ficha.pdf')]);
      expect(find.text('pantalla de inicio'), findsOneWidget);
      expect(find.text('Equipo registrado y 2 adjuntos subidos.'), findsOneWidget);
    });

    testWidgets('si un adjunto falla el equipo queda creado, se ve el motivo y se reintenta solo ese', (tester) async {
      var failPdf = true;
      repository.uploadFailure = (name) => name == 'ficha.pdf' && failPdf ? const NetworkFailure() : null;
      images.gallery = fakeFile('foto.jpg');
      files.document = fakeFile('ficha.pdf');
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);
      await choose(tester, 'attach-gallery');
      await choose(tester, 'attach-document');

      await fillAndSave(tester);

      expect(find.text('pantalla de inicio'), findsNothing, reason: 'se queda para mostrar el resultado');
      expect(find.byKey(const Key('results-summary')), findsOneWidget);
      expect(find.textContaining('No se pudieron subir 1 de 2 adjuntos'), findsOneWidget);
      expect(find.textContaining('Revisa tu conexión'), findsOneWidget);
      expect(find.text('REINTENTAR FALLIDOS'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'POST' && r.path == '/equipment'), hasLength(1));

      failPdf = false;
      repository.uploads.clear();
      await tester.tap(find.byKey(const Key('results-retry')));
      await tester.pumpAndSettle();

      expect(repository.uploads.map((u) => u.name), ['ficha.pdf'], reason: 'solo el fallido');
      expect(find.text('pantalla de inicio'), findsOneWidget);
      expect(find.text('Equipo registrado y 2 adjuntos subidos.'), findsOneWidget);
    });

    testWidgets('tras un fallo, «Cerrar» sale sin reintentar', (tester) async {
      repository.uploadFailure = (_) => const ServerFailure();
      images.gallery = fakeFile('foto.jpg');
      await pump(tester, _formAttach, start: CreateEquipmentScreen.path);
      await choose(tester, 'attach-gallery');
      await fillAndSave(tester);

      await tester.tap(find.byKey(const Key('results-close')));
      await tester.pumpAndSettle();

      expect(find.text('pantalla de inicio'), findsOneWidget);
      expect(repository.uploads, hasLength(1));
    });
  });

  group('listado: exportar', () {
    const exporter = {'equipos:ver', 'reportes:exportar'};

    testWidgets('sin el permiso de exportar no aparece el botón', (tester) async {
      await pump(tester, {'equipos:ver'}, start: EquipmentScreen.path);

      expect(find.byKey(const Key('export-button')), findsNothing);
    });

    testWidgets('con el permiso se elige el formato, se descarga, se comparte y se borra el temporal', (tester) async {
      await pump(tester, exporter, start: EquipmentScreen.path);

      await tester.tap(find.byKey(const Key('export-button')));
      await tester.pumpAndSettle();
      expect(find.text('Excel'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.textContaining('la búsqueda por texto no se incluye'), findsOneWidget);
      await tester.tap(find.byKey(const Key('export-csv')));
      await tester.pumpAndSettle();

      expect(repository.downloads.single, (format: 'csv', statuses: null, typeId: null));
      expect(share.shared.single.mimeType, 'text/csv');
      expect(temp.deleted, temp.created);
    });

    testWidgets('si no hay equipos que exportar avisa y no comparte', (tester) async {
      temp.size = 0;
      await pump(tester, exporter, start: EquipmentScreen.path);

      await tester.tap(find.byKey(const Key('export-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-xlsx')));
      await tester.pumpAndSettle();

      expect(find.text('No hay equipos para exportar con estos filtros.'), findsOneWidget);
      expect(share.shared, isEmpty);
    });

    testWidgets('si el servidor responde 403 avisa que no tiene permiso', (tester) async {
      repository.downloadFailure = const ForbiddenFailure();
      await pump(tester, exporter, start: EquipmentScreen.path);

      await tester.tap(find.byKey(const Key('export-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-pdf')));
      await tester.pumpAndSettle();

      expect(find.text('No tienes permiso para exportar el inventario.'), findsOneWidget);
      expect(share.shared, isEmpty);
    });

    testWidgets('si falla la red avisa con el mensaje de conexión', (tester) async {
      repository.downloadFailure = const NetworkFailure();
      await pump(tester, exporter, start: EquipmentScreen.path);

      await tester.tap(find.byKey(const Key('export-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-xlsx')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Revisa tu conexión'), findsOneWidget);
    });
  });
}
