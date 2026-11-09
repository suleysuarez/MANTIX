import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/widgets/shared/paged_list_view.dart';

void main() {
  Future<void> pumpList(WidgetTester tester, PagedListState<int> state, {Widget? header}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PagedListView<int>(
            value: state,
            header: header,
            onRefresh: () async {},
            onLoadMore: () {},
            itemBuilder: (context, item) => Text('elemento $item'),
            empty: const Text('lista vacía'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const header = Text('encabezado');

  testWidgets('con datos, el encabezado va primero y los elementos debajo', (tester) async {
    await pumpList(tester, const PagedListState(status: PagedStatus.success, items: [1, 2]), header: header);

    expect(find.text('encabezado'), findsOneWidget);
    expect(find.text('elemento 1'), findsOneWidget);
    expect(find.text('elemento 2'), findsOneWidget);
    expect(tester.getTopLeft(find.text('encabezado')).dy, lessThan(tester.getTopLeft(find.text('elemento 1')).dy));
  });

  testWidgets('sin elementos, el encabezado sigue visible y debajo va el vacío', (tester) async {
    await pumpList(tester, const PagedListState(status: PagedStatus.success), header: header);

    expect(find.text('encabezado'), findsOneWidget);
    expect(find.text('lista vacía'), findsOneWidget);
  });

  testWidgets('con error, el encabezado sigue visible y debajo va el error con reintento', (tester) async {
    await pumpList(tester, const PagedListState(status: PagedStatus.failure, failure: NetworkFailure()), header: header);

    expect(find.text('encabezado'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('cargando, el encabezado sigue visible', (tester) async {
    await pumpList(tester, const PagedListState(), header: header);

    expect(find.text('encabezado'), findsOneWidget);
  });

  testWidgets('sin encabezado se comporta como siempre', (tester) async {
    await pumpList(tester, const PagedListState(status: PagedStatus.success, items: [1]));

    expect(find.text('elemento 1'), findsOneWidget);
    expect(find.text('encabezado'), findsNothing);
  });
}
