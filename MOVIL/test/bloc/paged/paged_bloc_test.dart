import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/page_info.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';

class _Numbers extends PagedBloc<int> {
  _Numbers(this.pages);

  /// Páginas por servir; `null` en una posición simula un fallo.
  final List<List<int>?> pages;
  final List<int> asked = [];

  @override
  Future<PagedResult<int>> fetch(int page) async {
    asked.add(page);
    final items = pages[page - 1];
    if (items == null) throw const NetworkFailure();
    return PagedResult(
      items: items,
      info: PageInfo(total: 99, page: page, pageSize: 2, totalPages: pages.length),
    );
  }
}

class _Single extends PagedBloc<int> {
  int calls = 0;

  @override
  Future<PagedResult<int>> fetch(int page) async {
    calls++;
    return const PagedResult(items: [1]);
  }
}

PagedListState<int> loaded(List<int> items, int page, int totalPages, {bool loadingMore = false}) => PagedListState(
      status: PagedStatus.success,
      items: items,
      info: PageInfo(total: 99, page: page, pageSize: 2, totalPages: totalPages),
      loadingMore: loadingMore,
    );

void main() {
  test('empieza cargando y sin datos', () {
    final bloc = _Numbers([]);
    addTearDown(bloc.close);
    expect(bloc.state.status, PagedStatus.loading);
    expect(bloc.state.items, isEmpty);
  });

  blocTest<_Numbers, PagedListState<int>>(
    'carga la primera página al iniciar',
    build: () => _Numbers([
      [1, 2],
      [3, 4],
    ]),
    act: (bloc) => bloc.add(const PagedStarted()),
    expect: () => [loaded([1, 2], 1, 2)],
    verify: (bloc) {
      expect(bloc.state.hasMore, isTrue);
      expect(bloc.asked, [1]);
    },
  );

  blocTest<_Numbers, PagedListState<int>>(
    'loadMore añade la siguiente página y se detiene en la última',
    build: () => _Numbers([
      [1, 2],
      [3, 4],
    ]),
    act: (bloc) async {
      bloc.add(const PagedStarted());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const PagedLoadMoreRequested());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const PagedLoadMoreRequested());
    },
    wait: const Duration(milliseconds: 10),
    expect: () => [
      loaded([1, 2], 1, 2),
      loaded([1, 2], 1, 2, loadingMore: true),
      loaded([1, 2, 3, 4], 2, 2),
    ],
    verify: (bloc) {
      expect(bloc.state.hasMore, isFalse);
      expect(bloc.asked, [1, 2], reason: 'no pide más allá de la última página');
    },
  );

  blocTest<_Numbers, PagedListState<int>>(
    'dos loadMore seguidos piden la página una sola vez',
    build: () => _Numbers([
      [1, 2],
      [3, 4],
      [5, 6],
    ]),
    act: (bloc) async {
      bloc.add(const PagedStarted());
      await Future<void>.delayed(Duration.zero);
      bloc
        ..add(const PagedLoadMoreRequested())
        ..add(const PagedLoadMoreRequested());
    },
    wait: const Duration(milliseconds: 10),
    verify: (bloc) {
      expect(bloc.asked, [1, 2]);
      expect(bloc.state.items, [1, 2, 3, 4]);
    },
  );

  blocTest<_Numbers, PagedListState<int>>(
    'si falla una página conserva lo cargado y guarda el error',
    build: () => _Numbers([
      [1, 2],
      null,
    ]),
    act: (bloc) async {
      bloc.add(const PagedStarted());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const PagedLoadMoreRequested());
    },
    wait: const Duration(milliseconds: 10),
    verify: (bloc) {
      expect(bloc.state.items, [1, 2]);
      expect(bloc.state.loadingMore, isFalse);
      expect(bloc.state.loadMoreFailure, isA<NetworkFailure>());
    },
  );

  blocTest<_Numbers, PagedListState<int>>(
    'si falla la primera página el estado es de error',
    build: () => _Numbers([null]),
    act: (bloc) => bloc.add(const PagedStarted()),
    expect: () => [const PagedListState<int>(status: PagedStatus.failure, failure: NetworkFailure())],
  );

  blocTest<_Single, PagedListState<int>>(
    'sin cabeceras de paginación no hay más páginas',
    build: _Single.new,
    act: (bloc) async {
      bloc.add(const PagedStarted());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const PagedLoadMoreRequested());
    },
    wait: const Duration(milliseconds: 10),
    verify: (bloc) {
      expect(bloc.state.hasMore, isFalse);
      expect(bloc.calls, 1);
    },
  );

  test('refresh con datos cargados los mantiene visibles y termina al recibir la respuesta', () async {
    final bloc = _Numbers([
      [1, 2],
    ]);
    addTearDown(bloc.close);
    bloc.add(const PagedStarted());
    await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);

    final seen = <PagedListState<int>>[];
    final subscription = bloc.stream.listen(seen.add);
    await bloc.refresh();
    await subscription.cancel();

    expect(bloc.asked, [1, 1]);
    expect(seen.every((s) => s.status != PagedStatus.loading), isTrue, reason: 'nunca vuelve el esqueleto');
    expect(bloc.state.items, [1, 2]);
  });

  test('refresh tras un error vuelve a mostrar el esqueleto y se recupera', () async {
    var fail = true;
    final bloc = _Flaky(() => fail);
    addTearDown(bloc.close);
    bloc.add(const PagedStarted());
    await bloc.stream.firstWhere((s) => s.status == PagedStatus.failure);

    fail = false;
    final seen = <PagedStatus>[];
    final subscription = bloc.stream.listen((s) => seen.add(s.status));
    await bloc.refresh();
    await subscription.cancel();

    expect(seen, [PagedStatus.loading, PagedStatus.success]);
  });
}

class _Flaky extends PagedBloc<int> {
  _Flaky(this.shouldFail);

  final bool Function() shouldFail;

  @override
  Future<PagedResult<int>> fetch(int page) async {
    if (shouldFail()) throw const NetworkFailure();
    return const PagedResult(items: [1]);
  }
}
