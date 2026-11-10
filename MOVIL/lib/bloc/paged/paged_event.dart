part of 'paged_bloc.dart';

sealed class PagedEvent {
  const PagedEvent();
}

/// Carga la primera página (con esqueleto si aún no hay datos).
class PagedStarted extends PagedEvent {
  const PagedStarted();
}

/// Vuelve a pedir la primera página. Con datos ya cargados se siguen mostrando
/// mientras llega la respuesta; sin datos (error) vuelve el esqueleto.
class PagedRefreshed extends PagedEvent {
  const PagedRefreshed({this.done});

  /// Se completa al terminar; el «tirar para refrescar» espera a que acabe.
  final Completer<void>? done;
}

/// Añade la página siguiente (scroll infinito).
class PagedLoadMoreRequested extends PagedEvent {
  const PagedLoadMoreRequested();
}

/// Va a una página concreta (paginación numerada): sustituye los elementos por los de esa página.
class PagedPageSelected extends PagedEvent {
  const PagedPageSelected(this.page);

  /// Base 1.
  final int page;
}
