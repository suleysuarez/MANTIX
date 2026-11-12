part of 'report_history_bloc.dart';

sealed class ReportHistoryEvent {
  const ReportHistoryEvent();
}

/// Primera carga (página 1).
class ReportHistoryStarted extends ReportHistoryEvent {
  const ReportHistoryStarted();
}

/// Cambia de página (base 1).
class ReportHistoryPageSelected extends ReportHistoryEvent {
  const ReportHistoryPageSelected(this.page);

  final int page;
}

/// Vuelve a pedir la página actual; con datos cargados se siguen mostrando. [goToFirst] va a la
/// página 1 (lo que se acaba de exportar sale primero).
class ReportHistoryRefreshed extends ReportHistoryEvent {
  const ReportHistoryRefreshed({this.done, this.goToFirst = false});

  /// Se completa al terminar; el «tirar para refrescar» espera a que acabe.
  final Completer<void>? done;
  final bool goToFirst;
}
