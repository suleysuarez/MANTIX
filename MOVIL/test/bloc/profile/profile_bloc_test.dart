import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';
import 'package:mantix/bloc/profile/profile_bloc.dart';
import 'package:mantix/bloc/profile/profile_history_bloc.dart';
import 'package:mantix/models/equipment/attachment_models.dart';
import 'package:mantix/repositories/profile/profile_repository.dart';

import '../../support/fakes.dart';
import '../../support/profile_support.dart';
import '../../support/requests_support.dart';

ResponseBody _bytes(List<int> bytes) => ResponseBody.fromBytes(Uint8List.fromList(bytes), 200, headers: {
      Headers.contentTypeHeader: ['image/jpeg'],
    });

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late ProfileRepository repository;
  late FakeImagePicker images;

  setUp(() {
    handler = (_) => errorResponse(404);
    adapter = FakeAdapter((options) => handler(options));
    repository = ProfileRepository(dioWith(adapter));
    images = FakeImagePicker();
  });

  ProfileBloc build() => ProfileBloc(repository: repository, images: images);

  Future<ProfileBloc> loaded({bool hasAvatar = false}) async {
    handler = (options) {
      if (options.path == '/profile/avatar') return _bytes([1, 2, 3]);
      return jsonResponse(200, profileJson(hasAvatar: hasAvatar));
    };
    final bloc = build()..add(const ProfileRequested());
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((s) => s.status == ProfileStatus.ready);
    return bloc;
  }

  List<RequestOptions> writes() => adapter.requests.where((r) => r.method != 'GET').toList();

  group('cargar', () {
    test('trae el perfil y, si tiene foto, sus bytes', () async {
      final bloc = await loaded(hasAvatar: true);

      expect(bloc.state.profile!.fullName, 'Ana Pérez');
      expect(bloc.state.avatar, [1, 2, 3]);
      expect(adapter.requests.map((r) => r.path), ['/profile', '/profile/avatar']);
    });

    test('sin foto no pide la foto', () async {
      final bloc = await loaded();

      expect(bloc.state.avatar, isNull);
      expect(adapter.requests.map((r) => r.path), ['/profile']);
    });

    test('si la foto no baja, el perfil carga igual y quedan las iniciales', () async {
      handler = (options) => options.path == '/profile/avatar' ? errorResponse(500) : jsonResponse(200, profileJson(hasAvatar: true));
      final bloc = build()..add(const ProfileRequested());
      addTearDown(bloc.close);

      final state = await bloc.stream.firstWhere((s) => s.status == ProfileStatus.ready);

      expect(state.profile, isNotNull);
      expect(state.avatar, isNull);
    });

    test('si el perfil falla, queda el error con reintento y sin datos', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const ProfileRequested());
      addTearDown(bloc.close);

      final state = await bloc.stream.firstWhere((s) => s.status == ProfileStatus.failure);

      expect(state.unavailable, isTrue);
      expect(state.failure, isNotNull);
    });

    test('al recargar con la misma foto no la vuelve a bajar', () async {
      final bloc = await loaded(hasAvatar: true);
      bloc.add(const ProfileRequested());
      await bloc.stream.firstWhere((s) => s.status == ProfileStatus.ready);

      expect(adapter.requests.where((r) => r.path == '/profile/avatar'), hasLength(1));
    });
  });

  group('editar mis datos', () {
    ResponseBody respond(RequestOptions options) {
      if (options.method == 'PATCH') return jsonResponse(200, profileJson(name: 'Ana María', phone: null));
      return jsonResponse(200, profileJson());
    }

    test('solo manda lo que cambió y normaliza los espacios', () async {
      final bloc = await loaded();
      handler = respond;

      bloc.add(const ProfileSaveRequested(fullName: '  Ana   María ', phone: '+57 300 123 4567'));
      final state = await bloc.stream.firstWhere((s) => s.notice != null);

      expect(writes().single.method, 'PATCH');
      expect(writes().single.path, '/profile');
      expect(writes().single.data, {'full_name': 'Ana María'});
      expect(state.profile!.fullName, 'Ana María');
      expect(state.notice, 'Datos actualizados.');
      expect(state.saving, isFalse);
    });

    test('un teléfono vacío lo borra', () async {
      final bloc = await loaded();
      handler = respond;

      bloc.add(const ProfileSaveRequested(fullName: 'Ana Pérez', phone: '  '));
      await bloc.stream.firstWhere((s) => s.notice != null);

      expect(writes().single.data, {'phone': ''});
    });

    test('sin cambios no se pide nada y se dice', () async {
      final bloc = await loaded();

      bloc.add(const ProfileSaveRequested(fullName: 'Ana Pérez', phone: '+57 300 123 4567'));
      final state = await bloc.stream.firstWhere((s) => s.actionError != null);

      expect(state.actionError, 'No hay cambios que guardar.');
      expect(writes(), isEmpty);
    });

    test('si el servidor lo rechaza, se explica y el perfil queda como estaba', () async {
      final bloc = await loaded();
      handler = (_) => errorResponse(422, code: 'validation_error');

      bloc.add(const ProfileSaveRequested(fullName: 'Ana María', phone: '+57 300 123 4567'));
      final state = await bloc.stream.firstWhere((s) => s.actionError != null);

      expect(state.saving, isFalse);
      expect(state.profile!.fullName, 'Ana Pérez');
      expect(state.actionError, isNot(contains('detalle interno')));
    });

    test('el mismo aviso dos veces seguidas se vuelve a emitir', () async {
      final bloc = await loaded();
      handler = respond;
      final notices = <String?>[];
      final sub = bloc.stream.listen((s) => notices.add(s.notice));
      addTearDown(sub.cancel);

      bloc.add(const ProfileSaveRequested(fullName: 'Ana María', phone: '+57 300 123 4567'));
      await bloc.stream.firstWhere((s) => s.notice != null);
      bloc.add(const ProfileSaveRequested(fullName: 'Ana M.', phone: '+57 300 123 4567'));
      await bloc.stream.firstWhere((s) => s.notice == null && s.saving);
      await bloc.stream.firstWhere((s) => s.notice != null);

      expect(notices.where((n) => n == 'Datos actualizados.'), hasLength(2));
    });
  });

  group('foto', () {
    late File photo;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('mantix_profile_');
      photo = File('${dir.path}${Platform.pathSeparator}yo.jpg');
      await photo.writeAsBytes(List.filled(8, 7));
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // En Windows el archivo puede seguir abierto por una subida rechazada: no es un fallo de la prueba.
        }
      });
    });

    test('cambiar la foto con la cámara la sube con PUT, baja la nueva y avisa', () async {
      final bloc = await loaded();
      images.next = AttachmentFile(path: photo.path, name: 'yo.jpg', size: 8);
      handler = (options) {
        if (options.path == '/profile/avatar' && options.method == 'GET') return _bytes([9, 9]);
        return jsonResponse(200, profileJson(hasAvatar: true, avatarVersion: 2));
      };

      bloc.add(const ProfilePhotoRequested(ProfilePhotoSource.camera));
      final state = await bloc.stream.firstWhere((s) => s.notice != null);

      expect(images.camera, 1);
      expect(writes().single.method, 'PUT');
      expect(writes().single.path, '/profile/avatar');
      expect(state.avatar, [9, 9]);
      expect(state.profile!.hasAvatar, isTrue);
      expect(state.notice, 'Foto actualizada.');
    });

    test('elegir de la galería usa la galería', () async {
      final bloc = await loaded();
      images.next = AttachmentFile(path: photo.path, name: 'yo.png', size: 8);
      handler = (options) => options.method == 'GET' && options.path == '/profile/avatar' ? _bytes([5]) : jsonResponse(200, profileJson(hasAvatar: true));

      bloc.add(const ProfilePhotoRequested(ProfilePhotoSource.gallery));
      await bloc.stream.firstWhere((s) => s.notice != null);

      expect((images.gallery, images.camera), (1, 0));
    });

    test('si se cancela no se pide nada ni se avisa', () async {
      final bloc = await loaded();
      images.next = null;

      bloc.add(const ProfilePhotoRequested(ProfilePhotoSource.gallery));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(writes(), isEmpty);
      expect(bloc.state.notice, isNull);
      expect(bloc.state.actionError, isNull);
    });

    test('una foto que el servidor rechaza se explica sin detalles internos', () async {
      final bloc = await loaded();
      images.next = AttachmentFile(path: photo.path, name: 'yo.jpg', size: 8);
      handler = (_) => errorResponse(415, code: 'unsupported_media_type');

      bloc.add(const ProfilePhotoRequested(ProfilePhotoSource.gallery));
      final state = await bloc.stream.firstWhere((s) => s.actionError != null);

      expect(state.saving, isFalse);
      expect(state.actionError, isNot(contains('detalle interno')));
    });

    test('quitar la foto la borra del servidor y de la pantalla', () async {
      final bloc = await loaded(hasAvatar: true);
      handler = (_) => jsonResponse(200, profileJson());

      bloc.add(const ProfilePhotoRemoveRequested());
      final state = await bloc.stream.firstWhere((s) => s.notice != null);

      expect(writes().single.method, 'DELETE');
      expect(state.avatar, isNull);
      expect(state.profile!.hasAvatar, isFalse);
      expect(state.notice, 'Foto quitada.');
    });
  });

  group('actividad', () {
    test('pide de 20 en 20 y entrega las acciones', () async {
      handler = (_) => pagedResponse([historyJson(), historyJson(id: 2, action: 'profile.updated', kind: 'profile')]);
      final bloc = ProfileHistoryBloc(repository: repository)..add(const PagedStarted());
      addTearDown(bloc.close);

      final state = await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);

      expect(state.items.map((e) => e.action), ['auth.login', 'profile.updated']);
      final query = adapter.requests.single.queryParameters;
      expect(adapter.requests.single.path, '/profile/history');
      expect((query['page'], query['size']), (1, 20));
    });

    test('«Ver más» pide la página siguiente y las suma', () async {
      handler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([historyJson(id: page)], page: page, totalPages: 2, total: 2);
      };
      final bloc = ProfileHistoryBloc(repository: repository)..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);

      bloc.add(const PagedLoadMoreRequested());
      final state = await bloc.stream.firstWhere((s) => !s.loadingMore && s.items.length == 2);

      expect(state.items.map((e) => e.id), [1, 2]);
    });
  });
}
