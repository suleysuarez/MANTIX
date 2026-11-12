part of 'schedules_list_bloc.dart';

sealed class SchedulesListEvent {
  const SchedulesListEvent();
}

/// Primera carga (página 1).
class SchedulesListStarted extends SchedulesListEvent {
  const SchedulesListStarted();
}

/// Cambia de página (base 1).
class SchedulesPageSelected extends SchedulesListEvent {
  const SchedulesPageSelected(this.page);

  final int page;
}

/// Vuelve a pedir la página actual; con datos cargados se siguen mostrando.
class SchedulesListRefreshed extends SchedulesListEvent {
  const SchedulesListRefreshed({this.done});

  /// Se completa al terminar; el «tirar para refrescar» espera a que acabe.
  final Completer<void>? done;
}
