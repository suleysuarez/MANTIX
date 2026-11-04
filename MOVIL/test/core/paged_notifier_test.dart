import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/network/page_info.dart';
import 'package:mantix/core/network/paged_notifier.dart';

class _Numbers extends PagedNotifier<int> {
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

void main() {
  late _Numbers notifier;
  late ProviderContainer container;

  AsyncNotifierProvider<_Numbers, PagedState<int>> setup(List<List<int>?> pages) {
    notifier = _Numbers(pages);
    final provider = AsyncNotifierProvider<_Numbers, PagedState<int>>(() => notifier);
    container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    return provider;
  }

  test('carga la primera página al construirse', () async {
    final provider = setup([
      [1, 2],
      [3, 4],
    ]);
    final state = await container.read(provider.future);
    expect(state.items, [1, 2]);
    expect(state.hasMore, isTrue);
    expect(notifier.asked, [1]);
  });

  test('loadMore añade la siguiente página y se detiene en la última', () async {
    final provider = setup([
      [1, 2],
      [3, 4],
    ]);
    await container.read(provider.future);

    await container.read(provider.notifier).loadMore();
    expect(container.read(provider).value!.items, [1, 2, 3, 4]);
    expect(container.read(provider).value!.hasMore, isFalse);

    await container.read(provider.notifier).loadMore();
    expect(notifier.asked, [1, 2], reason: 'no pide más allá de la última página');
  });

  test('dos loadMore seguidos piden la página una sola vez', () async {
    final provider = setup([
      [1, 2],
      [3, 4],
      [5, 6],
    ]);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    await Future.wait([controller.loadMore(), controller.loadMore()]);
    expect(notifier.asked, [1, 2]);
    expect(container.read(provider).value!.items, [1, 2, 3, 4]);
  });

  test('si falla una página conserva lo cargado y guarda el error', () async {
    final provider = setup([
      [1, 2],
      null,
    ]);
    await container.read(provider.future);

    await container.read(provider.notifier).loadMore();
    final state = container.read(provider).value!;
    expect(state.items, [1, 2]);
    expect(state.loadingMore, isFalse);
    expect(state.loadMoreFailure, isA<NetworkFailure>());
  });

  test('si falla la primera página el estado es de error', () async {
    final provider = setup([null]);
    try {
      await container.read(provider.future);
    } catch (_) {
      // Se comprueba el estado abajo.
    }
    expect(container.read(provider).error, isA<NetworkFailure>());
  });

  test('sin cabeceras de paginación no hay más páginas', () async {
    final single = _Single();
    final provider = AsyncNotifierProvider<_Single, PagedState<int>>(() => single);
    container = ProviderContainer();
    addTearDown(container.dispose);
    final state = await container.read(provider.future);
    expect(state.hasMore, isFalse);
    await container.read(provider.notifier).loadMore();
    expect(single.calls, 1);
  });
}

class _Single extends PagedNotifier<int> {
  int calls = 0;

  @override
  Future<PagedResult<int>> fetch(int page) async {
    calls++;
    return const PagedResult(items: [1]);
  }
}
