import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/theme/app_colors.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/models/page_info.dart';
import 'package:mantix/widgets/shared/date_range_dialog.dart';
import 'package:mantix/widgets/shared/mantix_sheet.dart';
import 'package:mantix/widgets/shared/multi_select_sheet.dart';
import 'package:mantix/widgets/shared/paginator.dart';
import 'package:mantix/widgets/shared/search_picker_sheet.dart';

/// Pantallas pequeñas y escala de texto que no deben producir overflow.
const _sizes = [Size(320, 568), Size(360, 640)];

Future<void> pumpSized(WidgetTester tester, Widget child, {Size size = const Size(360, 640), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    builder: (context, app) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: app!),
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

class _Numbers extends PagedBloc<int> {
  _Numbers({this.pages = const [], this.fail = false, super.pageSize});

  final List<List<int>> pages;
  final bool fail;
  final List<int> asked = [];

  @override
  Future<PagedResult<int>> fetch(int page) async {
    asked.add(page);
    if (fail) throw const NetworkFailure();
    if (pages.isEmpty) return const PagedResult(items: []);
    return PagedResult(items: pages[page - 1], info: PageInfo(total: 99, page: page, pageSize: 2, totalPages: pages.length));
  }
}

Paginator paginator({int page = 1, int pageSize = 5, int shown = 5, int total = 23, int totalPages = 5, ValueChanged<int>? onPage, ValueChanged<int>? onPageSize}) =>
    Paginator(page: page, pageSize: pageSize, shown: shown, total: total, totalPages: totalPages, onPage: onPage ?? (_) {}, onPageSize: onPageSize);

void main() {
  group('Paginator', () {
    test('pageRangeLabel', () {
      expect(pageRangeLabel(page: 1, pageSize: 5, shown: 5, total: 23), '1-5 de 23');
      expect(pageRangeLabel(page: 5, pageSize: 5, shown: 3, total: 23), '21-23 de 23');
      expect(pageRangeLabel(page: 1, pageSize: 5, shown: 0, total: 0), '0 de 0');
    });

    testWidgets('en la primera página no hay «anterior» y sí «siguiente»', (tester) async {
      await pumpSized(tester, paginator(onPageSize: (_) {}));
      expect(find.text('1-5 de 23'), findsOneWidget);
      expect(find.byTooltip('Página anterior'), findsNothing);
      expect(find.byTooltip('Página siguiente'), findsOneWidget);
    });

    testWidgets('en la última página no hay «siguiente» y sí «anterior»', (tester) async {
      await pumpSized(tester, paginator(page: 5, shown: 3));
      expect(find.text('21-23 de 23'), findsOneWidget);
      expect(find.byTooltip('Página siguiente'), findsNothing);
      expect(find.byTooltip('Página anterior'), findsOneWidget);
    });

    testWidgets('con una sola página no hay flechas, «1 / 1» ni selector con pocos elementos', (tester) async {
      await pumpSized(tester, paginator(shown: 3, total: 3, totalPages: 1, onPageSize: (_) {}));
      expect(find.text('1-3 de 3'), findsOneWidget);
      expect(find.byTooltip('Página anterior'), findsNothing);
      expect(find.byTooltip('Página siguiente'), findsNothing);
      expect(find.textContaining('/'), findsNothing);
      expect(find.byType(DropdownButton<int>), findsNothing);

      // La píldora sigue ahí, con la única página en el círculo mostaza.
      expect(find.text('1'), findsOneWidget);
      final selected = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == AppColors.mustard && (w.decoration! as BoxDecoration).shape == BoxShape.circle);
      expect(selected, findsOneWidget);
    });

    testWidgets('el selector de tamaño aparece si el total supera 5 y avisa del cambio', (tester) async {
      int? chosen;
      await pumpSized(tester, paginator(shown: 5, total: 6, totalPages: 2, onPageSize: (size) => chosen = size));
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      for (final size in pageSizeOptions) {
        expect(find.text('$size por página'), findsWidgets);
      }
      await tester.tap(find.text('20 por página').last);
      await tester.pumpAndSettle();
      expect(chosen, 20);
    });

    testWidgets('sin onPageSize no hay selector', (tester) async {
      await pumpSized(tester, paginator());
      expect(find.byType(DropdownButton<int>), findsNothing);
    });

    testWidgets('pasar de página avisa y, cargando, no hace nada', (tester) async {
      final pages = <int>[];
      await pumpSized(tester, paginator(page: 2, onPage: pages.add));
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.tap(find.byTooltip('Página anterior'));
      expect(pages, [3, 1]);

      pages.clear();
      await pumpSized(tester, Paginator(page: 2, pageSize: 5, shown: 5, total: 23, totalPages: 5, loading: true, onPage: pages.add));
      await tester.tap(find.byTooltip('Página siguiente'));
      expect(pages, isEmpty);
    });

    for (final size in _sizes) {
      testWidgets('sin overflow en ${size.width.toInt()}x${size.height.toInt()} con texto 1,3', (tester) async {
        await pumpSized(tester, paginator(page: 3, onPageSize: (_) {}), size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }

    test('visiblePages: todas si caben y, si no, «…» y siempre la primera y la última', () {
      expect(visiblePages(page: 1, totalPages: 3, slots: 7), [1, 2, 3]);
      expect(visiblePages(page: 1, totalPages: 7, slots: 7), [1, 2, 3, 4, 5, 6, 7]);
      // Como en el diseño: «1 2 3 4 5 … 99».
      expect(visiblePages(page: 5, totalPages: 99, slots: 7), [1, 2, 3, 4, 5, null, 99]);
      expect(visiblePages(page: 1, totalPages: 99, slots: 7), [1, 2, 3, 4, 5, null, 99]);
      expect(visiblePages(page: 10, totalPages: 99, slots: 7), [1, null, 9, 10, 11, null, 99]);
      expect(visiblePages(page: 95, totalPages: 99, slots: 7), [1, null, 95, 96, 97, 98, 99]);
      expect(visiblePages(page: 99, totalPages: 99, slots: 7), [1, null, 95, 96, 97, 98, 99]);
      // Con poco sitio, siempre al menos cinco huecos.
      expect(visiblePages(page: 2, totalPages: 20, slots: 4), [1, 2, 3, null, 20]);
      expect(visiblePages(page: 9, totalPages: 20, slots: 5), [1, null, 9, null, 20]);
    });

    test('visiblePages nunca repite una página ni se pasa del total', () {
      for (final slots in [5, 6, 7]) {
        for (var total = 1; total <= 30; total++) {
          for (var page = 1; page <= total; page++) {
            final pages = visiblePages(page: page, totalPages: total, slots: slots).whereType<int>().toList();
            expect(pages.toSet().length, pages.length, reason: 'sin repetidas ($page de $total, $slots huecos)');
            expect(pages, contains(page), reason: 'la actual siempre se ve');
            expect(pages.first, 1);
            expect(pages.last, total);
            expect(pages, everyElement(inInclusiveRange(1, total)));
            expect(visiblePages(page: page, totalPages: total, slots: slots).length, lessThanOrEqualTo(slots < 5 ? 5 : slots));
          }
        }
      }
    });

    testWidgets('con muchas páginas muestra «1 2 3 4 5 … 99» y la última se puede tocar', (tester) async {
      final pages = <int>[];
      await pumpSized(tester, paginator(page: 5, totalPages: 99, total: 990, onPage: pages.add), size: const Size(420, 640));

      for (final n in [1, 2, 3, 4, 5, 99]) {
        expect(find.text('$n'), findsOneWidget, reason: 'página $n');
      }
      expect(find.text('…'), findsOneWidget);
      expect(find.text('6'), findsNothing);
      await tester.tap(find.text('99'));
      expect(pages, [99]);
    });

    testWidgets('la píldora ocupa todo el ancho y la página actual va en un círculo mostaza', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSized(tester, Padding(padding: const EdgeInsets.all(16), child: paginator(page: 2, totalPages: 7)));

      final pill = tester.getRect(find.byType(Paginator).first);
      expect(pill.width, 360 - 32, reason: 'ancho completo');
      expect(find.bySemanticsLabel('Página 2'), findsOneWidget, reason: 'cada número se anuncia como botón');
      final selected = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == AppColors.mustard && (w.decoration! as BoxDecoration).shape == BoxShape.circle);
      expect(selected, findsOneWidget);
      expect(find.descendant(of: selected, matching: find.text('2')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('tocar un número va a esa página; la página actual no hace nada', (tester) async {
      final pages = <int>[];
      await pumpSized(tester, paginator(page: 2, totalPages: 5, onPage: pages.add));

      await tester.tap(find.text('4'));
      await tester.tap(find.text('2'));
      expect(pages, [4]);
    });

    testWidgets('en una pantalla estrecha caben menos números y la actual sigue visible', (tester) async {
      await pumpSized(tester, paginator(page: 9, totalPages: 20), size: const Size(320, 568), textScale: 1.3);

      expect(find.text('9'), findsOneWidget);
      final numbers = [for (var n = 1; n <= 20; n++) if (find.text('$n').evaluate().isNotEmpty) n];
      expect(numbers.length, inInclusiveRange(3, 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('en la primera página la flecha de la izquierda no existe y en la última la de la derecha tampoco', (tester) async {
      await pumpSized(tester, paginator(page: 1, totalPages: 3));
      expect(find.byTooltip('Página anterior'), findsNothing);
      expect(find.byTooltip('Página siguiente'), findsOneWidget);

      await pumpSized(tester, paginator(page: 3, totalPages: 3));
      expect(find.byTooltip('Página anterior'), findsOneWidget);
      expect(find.byTooltip('Página siguiente'), findsNothing);
    });
  });

  group('Filtro multiselección', () {
    Future<void> open(WidgetTester tester, void Function(Set<String>?) onResult, {Set<String> selected = const {}, Size size = const Size(360, 640), double scale = 1.0}) async {
      await pumpSized(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(await showMultiSelectSheet<String>(
              context,
              title: 'Estado',
              options: const [FilterOption('a', 'Enviado'), FilterOption('b', 'En proceso'), FilterOption('c', 'Resuelto')],
              selected: selected,
            )),
            child: const Text('abrir'),
          ),
        ),
        size: size,
        textScale: scale,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('marcar casillas no cierra la hoja; Aplicar devuelve la selección', (tester) async {
      Set<String>? result;
      await open(tester, (value) => result = value);
      await tester.tap(find.text('Enviado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resuelto'));
      await tester.pumpAndSettle();
      expect(find.text('Aplicar'), findsOneWidget, reason: 'la hoja sigue abierta');
      expect(find.text('2 activos'), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(result, {'a', 'c'});
    });

    testWidgets('Limpiar vacía la selección sin cerrar', (tester) async {
      Set<String>? result;
      await open(tester, (value) => result = value, selected: {'a', 'b'});
      expect(find.text('2 activos'), findsOneWidget);
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();
      expect(find.text('Aplicar'), findsOneWidget);
      expect(find.textContaining('activos'), findsNothing);
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
    });

    testWidgets('cerrar sin aplicar devuelve null', (tester) async {
      Set<String>? result = {'x'};
      await open(tester, (value) => result = value);
      await tester.tap(find.text('Enviado'));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('FilterButton muestra el contador de filtros activos', (tester) async {
      await pumpSized(tester, FilterButton(count: 3, onPressed: () {}));
      expect(find.text('3'), findsOneWidget);
      expect(find.byTooltip('Filtros (3 activos)'), findsOneWidget);
      await pumpSized(tester, FilterButton(count: 0, onPressed: () {}));
      expect(find.byTooltip('Filtros'), findsOneWidget);
    });

    for (final size in _sizes) {
      testWidgets('sin overflow en ${size.width.toInt()}x${size.height.toInt()} con texto 1,3', (tester) async {
        await open(tester, (_) {}, selected: {'a'}, size: size, scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Rango de fechas', () {
    final today = DateTime(2026, 11, 9);

    test('validateDateRange', () {
      expect(validateDateRange(null, null, today: today), isNotNull);
      expect(validateDateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 5), today: today), isNull);
      expect(validateDateRange(DateTime(2026, 11, 5), DateTime(2026, 11, 5), today: today), isNull);
      expect(validateDateRange(DateTime(2026, 11, 6), DateTime(2026, 11, 5), today: today), contains('posterior'));
      expect(validateDateRange(DateTime(2026, 11, 1), DateTime(2026, 12, 1), today: today), contains('futuras'));
      expect(validateDateRange(DateTime(2026, 11, 3), null, today: today), isNull);
    });

    Future<void> open(WidgetTester tester, DateTimeRange? initial, void Function(DateTimeRange?) onResult, {Size size = const Size(360, 640), double scale = 1.0}) async {
      await pumpSized(
        tester,
        Builder(builder: (context) => TextButton(onPressed: () async => onResult(await showDateRangeDialog(context, initial: initial)), child: const Text('abrir'))),
        size: size,
        textScale: scale,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('Aplicar devuelve el rango inicial', (tester) async {
      DateTimeRange? result;
      final initial = DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 15));
      await open(tester, initial, (value) => result = value);
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(result, initial);
    });

    testWidgets('sin fechas, Aplicar muestra el error y no cierra', (tester) async {
      var closed = false;
      await open(tester, null, (_) => closed = true);
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('Elige al menos una fecha.'), findsOneWidget);
      expect(closed, isFalse);
    });

    testWidgets('Cancelar devuelve null', (tester) async {
      DateTimeRange? result = DateTimeRange(start: DateTime(2026), end: DateTime(2026));
      await open(tester, null, (value) => result = value);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    for (final size in _sizes) {
      testWidgets('sin overflow en ${size.width.toInt()}x${size.height.toInt()} con texto 1,3', (tester) async {
        await open(tester, DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 15)), (_) {}, size: size, scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Hoja inferior', () {
    Future<void> open(WidgetTester tester, {Size size = const Size(360, 640), double scale = 1.0}) async {
      await pumpSized(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showMantixSheet<void>(
              context,
              title: 'Detalle del equipo con un título bastante largo para comprobar el ajuste',
              builder: (context, controller) => ListView(controller: controller, children: [for (var i = 0; i < 30; i++) ListTile(title: Text('Fila $i'))]),
              footer: FilledButton(onPressed: () {}, child: const Text('Guardar')),
            ),
            child: const Text('abrir'),
          ),
        ),
        size: size,
        textScale: scale,
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra título, contenido y pie; el botón cierra', (tester) async {
      await open(tester);
      expect(find.textContaining('Detalle del equipo'), findsOneWidget);
      expect(find.text('Fila 0'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Detalle del equipo'), findsNothing);
    });

    testWidgets('deja visible la parte alta de la pantalla (máx. 90 %)', (tester) async {
      await open(tester);
      final top = tester.getTopLeft(find.byType(DraggableScrollableSheet)).dy;
      expect(top, greaterThanOrEqualTo(640 * .1 - 1));
    });

    for (final size in _sizes) {
      testWidgets('sin overflow en ${size.width.toInt()}x${size.height.toInt()} con texto 1,3', (tester) async {
        await open(tester, size: size, scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Selector con búsqueda', () {
    Widget picker(PagedBloc<int> Function(String) create, {Future<int?> Function()? onCreate, String? createLabel, ValueChanged<int?>? onPicked}) => Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final value = await showSearchPicker<int>(
                context,
                title: 'Elegir',
                createBloc: create,
                itemBuilder: (context, item, select) => ListTile(title: Text('Elemento $item'), onTap: select),
                onCreate: onCreate,
                createLabel: createLabel,
              );
              onPicked?.call(value);
            },
            child: const Text('abrir'),
          ),
        );

    Future<void> open(WidgetTester tester, Widget child, {Size size = const Size(360, 640), double scale = 1.0}) async {
      await pumpSized(tester, child, size: size, textScale: scale);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('lista los resultados y elegir uno cierra la hoja con el valor', (tester) async {
      int? picked;
      await open(tester, picker((_) => _Numbers(pages: [[1, 2], [3]]), onPicked: (value) => picked = value));
      expect(find.text('Elemento 1'), findsOneWidget);
      await tester.tap(find.text('Elemento 2'));
      await tester.pumpAndSettle();
      expect(picked, 2);
    });

    testWidgets('«Ver más resultados» pide la página siguiente y se oculta al final', (tester) async {
      await open(tester, picker((_) => _Numbers(pages: [[1, 2], [3]])));
      await tester.tap(find.text('Ver más resultados'));
      await tester.pumpAndSettle();
      expect(find.text('Elemento 3'), findsOneWidget);
      expect(find.text('Elemento 1'), findsOneWidget);
      expect(find.text('Ver más resultados'), findsNothing);
    });

    testWidgets('escribir busca de nuevo con el texto', (tester) async {
      final searches = <String>[];
      await open(tester, picker((search) {
        searches.add(search);
        return _Numbers(pages: [[1]]);
      }));
      await tester.enterText(find.byType(TextField), '  dell ');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(searches, ['', 'dell']);
    });

    testWidgets('vacío y error con reintento', (tester) async {
      await open(tester, picker((_) => _Numbers()));
      expect(find.text('Sin resultados'), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Sin resultados'), findsOneWidget);
    });

    testWidgets('un error de red muestra el estado de error con reintento', (tester) async {
      final blocs = <_Numbers>[];
      await open(tester, picker((_) {
        final bloc = _Numbers(fail: true);
        blocs.add(bloc);
        return bloc;
      }));
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(blocs.single.asked, [1, 1]);
    });

    testWidgets('«Crear nueva» solo aparece si hay callback y etiqueta', (tester) async {
      await open(tester, picker((_) => _Numbers(pages: [[1]])));
      expect(find.text('Crear nueva categoría'), findsNothing);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      int? picked;
      await open(tester, picker((_) => _Numbers(pages: [[1]]), createLabel: 'Crear nueva categoría', onCreate: () async => 99, onPicked: (value) => picked = value));
      expect(find.text('Crear nueva categoría'), findsOneWidget);
      await tester.tap(find.text('Crear nueva categoría'));
      await tester.pumpAndSettle();
      expect(picked, 99);
    });

    for (final size in _sizes) {
      testWidgets('sin overflow en ${size.width.toInt()}x${size.height.toInt()} con texto 1,3', (tester) async {
        await open(tester, picker((_) => _Numbers(pages: [[1, 2], [3]]), createLabel: 'Crear nueva categoría', onCreate: () async => 1), size: size, scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('PagedBloc tamaño de página', () {
    test('usa 20 por defecto y el tamaño que se le da', () {
      final byDefault = _Numbers();
      final custom = _Numbers(pageSize: 5);
      addTearDown(byDefault.close);
      addTearDown(custom.close);
      expect(byDefault.pageSize, PageInfo.defaultPageSize);
      expect(custom.pageSize, 5);
    });
  });
}
