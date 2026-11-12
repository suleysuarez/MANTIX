import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/profile/avatar_cubit.dart';
import 'package:mantix/repositories/profile/profile_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

ResponseBody _bytes(List<int> bytes) => ResponseBody.fromBytes(Uint8List.fromList(bytes), 200, headers: {
      Headers.contentTypeHeader: ['image/jpeg'],
    });

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late AvatarCubit cubit;

  setUp(() {
    handler = (_) => errorResponse(404);
    adapter = FakeAdapter((options) => handler(options));
    cubit = AvatarCubit(ProfileRepository(dioWith(adapter)));
    addTearDown(cubit.close);
  });

  test('empieza sin foto', () => expect(cubit.state, isNull));

  test('load baja mi foto con el token, de /profile/avatar', () async {
    handler = (_) => _bytes(_jpeg);

    await cubit.load();

    expect(cubit.state, _jpeg);
    expect(adapter.requests.single.path, '/profile/avatar');
    expect(adapter.requests.single.method, 'GET');
  });

  test('sin foto en el servidor (404) quedan las iniciales y no se pide nada más', () async {
    await cubit.load();

    expect(cubit.state, isNull);
    expect(adapter.requests, hasLength(1));
  });

  test('si falla el servidor se borra lo anterior en vez de dejar una foto vieja', () async {
    cubit.show(_png);
    handler = (_) => errorResponse(500);

    await cubit.load();

    expect(cubit.state, isNull);
  });

  test('algo que no parece una imagen se descarta: mejor las iniciales que una foto rota', () async {
    handler = (_) => _bytes([1, 2, 3, 4, 5]);
    await cubit.load();
    expect(cubit.state, isNull);

    cubit.show(Uint8List.fromList([0, 1]));
    expect(cubit.state, isNull);
  });

  test('show acepta JPEG y PNG, y clear la quita', () {
    cubit.show(_jpeg);
    expect(cubit.state, _jpeg);
    cubit.show(_png);
    expect(cubit.state, _png);
    cubit.show(null);
    expect(cubit.state, isNull);
    cubit.show(_jpeg);
    cubit.clear();
    expect(cubit.state, isNull);
  });
}
