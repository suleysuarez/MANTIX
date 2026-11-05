import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/errors/failure_mapper.dart';
import 'package:mantix/core/theme/app_colors.dart';
import 'package:mantix/core/validation/validators.dart';
import 'package:mantix/shared/app_chip.dart';
import 'package:mantix/shared/app_text_field.dart';
import 'package:mantix/shared/async_view.dart';
import 'package:mantix/shared/confirm_dialog.dart';
import 'package:mantix/shared/empty_state.dart';
import 'package:mantix/shared/error_state.dart';
import 'package:mantix/shared/glass_card.dart';
import 'package:mantix/shared/skeleton.dart';

import '../support/pump_app.dart';

void main() {
  group('chips', () {
    testWidgets('StatusChip muestra la etiqueta en español y se anuncia como una frase', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, const StatusChip('resolved'));

      expect(find.text('Resuelto'), findsOneWidget);
      expect(find.bySemanticsLabel('Estado: Resuelto'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('PriorityChip se anuncia con su prefijo', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, const PriorityChip('critical'));

      expect(find.text('Crítica'), findsOneWidget);
      expect(find.bySemanticsLabel('Prioridad: Crítica'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('un estado desconocido se muestra tal cual', (tester) async {
      await pumpApp(tester, const StatusChip('estado_nuevo'));

      expect(find.text('estado_nuevo'), findsOneWidget);
    });

    testWidgets('cancelado se tacha y el resto no', (tester) async {
      await pumpApp(tester, const Column(children: [StatusChip('cancelled'), StatusChip('closed')]));

      TextDecoration? decorationOf(String label) => tester.widget<Text>(find.text(label)).style?.decoration;
      expect(decorationOf('Cancelado'), TextDecoration.lineThrough);
      expect(decorationOf('Cerrado'), isNot(TextDecoration.lineThrough));
    });

    testWidgets('con texto muy largo no se desborda', (tester) async {
      await pumpApp(
        tester,
        const SizedBox(width: 90, child: AppChip(label: 'Una etiqueta demasiado larga para caber', colors: _colors)),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Skeleton', () {
    testWidgets('parpadea por defecto', (tester) async {
      await pumpApp(tester, const Skeleton());
      await tester.pump();

      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('con «reducir movimiento» se queda quieto', (tester) async {
      await pumpApp(tester, const Skeleton(), disableAnimations: true);
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('SkeletonList se anuncia como «Cargando contenido»', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester, const SkeletonList(itemCount: 3));

      expect(find.bySemanticsLabel('Cargando contenido'), findsOneWidget);
      expect(find.byType(Skeleton), findsNWidgets(3));
      semantics.dispose();
    });
  });

  group('EmptyState', () {
    testWidgets('muestra título y mensaje', (tester) async {
      await pumpApp(tester, const EmptyState(title: 'Sin tickets', message: 'Aparecerán aquí.'));

      expect(find.text('Sin tickets'), findsOneWidget);
      expect(find.text('Aparecerán aquí.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('el botón de acción llama a onAction y mide al menos 48 px', (tester) async {
      var taps = 0;
      await pumpApp(tester, EmptyState(title: 'Sin tickets', actionLabel: 'Nuevo ticket', onAction: () => taps++));

      final button = find.widgetWithText(FilledButton, 'Nuevo ticket');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      expect(taps, 1);
    });

    testWidgets('sin onAction no se muestra el botón', (tester) async {
      await pumpApp(tester, const EmptyState(title: 'Sin tickets', actionLabel: 'Nuevo ticket'));

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('acepta una ilustración propia', (tester) async {
      await pumpApp(tester, const EmptyState(title: 'Sin tickets', illustration: Text('ilustración')));

      expect(find.text('ilustración'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNothing);
    });
  });

  group('ErrorState', () {
    testWidgets('error de red: título, mensaje y reintento', (tester) async {
      var retries = 0;
      await pumpApp(tester, ErrorState(failure: const NetworkFailure(), onRetry: () => retries++));

      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.textContaining('No pudimos conectar'), findsOneWidget);
      final retry = find.widgetWithText(FilledButton, 'Reintentar');
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      await tester.tap(retry);
      expect(retries, 1);
    });

    testWidgets('muestra el código de referencia si lo hay', (tester) async {
      await pumpApp(tester, const ErrorState(failure: ServerFailure(requestId: 'abc123')));

      expect(find.text('Código de referencia: abc123'), findsOneWidget);
    });

    testWidgets('sin onRetry no hay botón', (tester) async {
      await pumpApp(tester, const ErrorState(failure: ForbiddenFailure()));

      expect(find.text('Sin permiso'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    test('cada tipo de fallo tiene su título e icono', () {
      expect(ErrorState.titleOf(const UnauthorizedFailure()), 'Sesión caducada');
      expect(ErrorState.titleOf(const NotFoundFailure()), 'No encontrado');
      expect(ErrorState.titleOf(const ConflictFailure()), 'Algo salió mal');
      expect(ErrorState.iconOf(const NetworkFailure()), Icons.cloud_off);
      expect(ErrorState.iconOf(const ForbiddenFailure()), Icons.lock_outline);
    });
  });

  group('AsyncView', () {
    Widget view({List<int>? loaded, Failure? failure, VoidCallback? onRetry}) => AsyncView<List<int>>(
          loaded: loaded,
          failure: failure,
          isEmpty: (items) => items.isEmpty,
          empty: const EmptyState(title: 'Lista vacía'),
          onRetry: onRetry,
          data: (items) => Text('hay ${items.length}'),
        );

    testWidgets('cargando muestra el esqueleto', (tester) async {
      await pumpApp(tester, view());

      expect(find.byType(SkeletonList), findsOneWidget);
    });

    testWidgets('vacío muestra el estado vacío', (tester) async {
      await pumpApp(tester, view(loaded: const []), settle: true);

      expect(find.text('Lista vacía'), findsOneWidget);
    });

    testWidgets('con datos muestra el contenido', (tester) async {
      await pumpApp(tester, view(loaded: const [1, 2, 3]), settle: true);

      expect(find.text('hay 3'), findsOneWidget);
    });

    testWidgets('error de la red muestra reintento y lo ejecuta', (tester) async {
      var retries = 0;
      final error = DioException(requestOptions: RequestOptions(path: '/x'));
      await pumpApp(tester, view(failure: toFailure(error), onRetry: () => retries++), settle: true);

      expect(find.text('Sin conexión'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);
    });

    testWidgets('un 401 se muestra como sesión caducada', (tester) async {
      final request = RequestOptions(path: '/x');
      final error = DioException(requestOptions: request, response: Response(requestOptions: request, statusCode: 401));
      await pumpApp(tester, view(failure: toFailure(error)), settle: true);

      expect(find.text('Sesión caducada'), findsOneWidget);
    });

    testWidgets('un error desconocido no filtra su contenido', (tester) async {
      await pumpApp(tester, view(failure: toFailure(Exception('contraseña=secreta'))), settle: true);

      expect(find.text('Algo salió mal'), findsOneWidget);
      expect(find.textContaining('secreta'), findsNothing);
    });

    testWidgets('sin pantalla de vacío propia usa la de por defecto', (tester) async {
      await pumpApp(
        tester,
        AsyncView<List<int>>(loaded: const [], isEmpty: (i) => i.isEmpty, data: (i) => const Text('datos')),
        settle: true,
      );

      expect(find.text('No hay nada por aquí todavía'), findsOneWidget);
    });
  });

  group('AppTextField', () {
    testWidgets('muestra el error del validador al interactuar, ya recortado', (tester) async {
      await pumpApp(tester, AppTextField(label: 'Título', validator: Validators.required('El título')));

      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.pump();

      expect(find.text('El título es obligatorio.'), findsOneWidget);
    });

    testWidgets('sin error cuando el texto es válido', (tester) async {
      await pumpApp(tester, AppTextField(label: 'Título', validator: Validators.required('El título')));

      await tester.enterText(find.byType(TextFormField), 'Ruido');
      await tester.pump();

      expect(find.text('El título es obligatorio.'), findsNothing);
    });

    testWidgets('muestra el error del servidor bajo el campo', (tester) async {
      await pumpApp(tester, const AppTextField(label: 'Prioridad', errorText: 'Valor no válido'));

      expect(find.text('Valor no válido'), findsOneWidget);
    });

    testWidgets('el campo mide al menos 48 px de alto', (tester) async {
      await pumpApp(tester, const AppTextField(label: 'Título'));

      expect(tester.getSize(find.byType(TextFormField)).height, greaterThanOrEqualTo(48));
    });
  });

  group('showConfirmDialog', () {
    Future<void> open(WidgetTester tester, void Function(bool) onResult, {bool destructive = false}) async {
      await pumpApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(await showConfirmDialog(
              context,
              title: 'Cerrar ticket',
              message: 'Ya no se podrá editar.',
              confirmLabel: 'Cerrar',
              destructive: destructive,
            )),
            child: const Text('abrir'),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirmar devuelve true', (tester) async {
      bool? result;
      await open(tester, (r) => result = r);

      expect(find.text('Cerrar ticket'), findsOneWidget);
      expect(find.text('Ya no se podrá editar.'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('cancelar devuelve false', (tester) async {
      bool? result;
      await open(tester, (r) => result = r);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('cerrar tocando fuera cuenta como cancelar', (tester) async {
      bool? result;
      await open(tester, (r) => result = r);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  testWidgets('GlassCard muestra su contenido', (tester) async {
    await pumpApp(tester, const GlassCard(child: Text('hola')));

    expect(find.text('hola'), findsOneWidget);
  });
}

const _colors = ChipColors(background: Color(0xFFDBEAFE), foreground: Color(0xFF1E40AF), dot: Color(0xFF2563EB));
