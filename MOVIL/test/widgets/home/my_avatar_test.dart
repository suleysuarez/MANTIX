import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/profile/avatar_cubit.dart';
import 'package:mantix/repositories/profile/profile_repository.dart';
import 'package:mantix/widgets/home/mantix_drawer.dart';

import '../../support/fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_support.dart';

/// Un PNG real de 1×1 píxel.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

CircleAvatar _avatar(WidgetTester tester) => tester.widget<CircleAvatar>(find.byType(CircleAvatar));

void main() {
  testWidgets('sin foto muestra las iniciales', (tester) async {
    await pumpApp(tester, const MyAvatar(name: 'Ana Pérez', radius: 20));

    expect(find.text('AP'), findsOneWidget);
    expect(_avatar(tester).foregroundImage, isNull);
  });

  testWidgets('sin AvatarCubit en el árbol también muestra las iniciales y no falla', (tester) async {
    await pumpApp(tester, const MyAvatar(name: 'María de los Ángeles', radius: 20));

    expect(tester.takeException(), isNull);
    expect(find.text('MD'), findsOneWidget);
  });

  group('con AvatarCubit', () {
    late AvatarCubit cubit;

    setUp(() => cubit = AvatarCubit(ProfileRepository(dioWith(FakeAdapter((_) => errorResponse(404))))));
    tearDown(() => cubit.close());

    Future<void> pumpAvatar(WidgetTester tester) => pumpApp(tester, BlocProvider.value(value: cubit, child: const MyAvatar(name: 'Ana Pérez', radius: 20)));

    testWidgets('con foto la dibuja y las iniciales quedan debajo por si no se pudiera mostrar', (tester) async {
      cubit.show(Uint8List.fromList(_png));
      await pumpAvatar(tester);

      expect(_avatar(tester).foregroundImage, isA<MemoryImage>());
      expect(find.text('AP'), findsOneWidget);
    });

    testWidgets('cuando cambia la foto la burbuja se actualiza sola, y al quitarla vuelven las iniciales', (tester) async {
      await pumpAvatar(tester);
      expect(_avatar(tester).foregroundImage, isNull);

      cubit.show(Uint8List.fromList(_png));
      await tester.pumpAndSettle();
      expect(_avatar(tester).foregroundImage, isA<MemoryImage>());

      cubit.clear();
      await tester.pumpAndSettle();
      expect(_avatar(tester).foregroundImage, isNull);
      expect(find.text('AP'), findsOneWidget);
    });
  });
}
