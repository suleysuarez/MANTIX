import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/report_format.dart';
import '../../models/reports/report_models.dart';
import '../../repositories/reports/reports_repository.dart';

part 'report_preview_event.dart';
part 'report_preview_state.dart';

/// La vista previa de un reporte con sus filtros: las primeras filas, el total y, si se pide, el
/// comparativo con el periodo anterior. Un Bloc por reporte (cambiar de reporte crea otro). Con un
/// rango de fechas inválido no se pide nada; si se piden dos vistas seguidas, solo cuenta la
/// última (una respuesta que llega tarde se descarta).
class ReportPreviewBloc extends Bloc<ReportPreviewEvent, ReportPreviewState> {
  ReportPreviewBloc({required this._repository, required this.definition}) : super(const ReportPreviewState()) {
    on<ReportPreviewRequested>(_onRequested);
  }

  final ReportsRepository _repository;
  final ReportDefinition definition;
  int _token = 0;

  Future<void> _onRequested(ReportPreviewRequested event, Emitter<ReportPreviewState> emit) async {
    final token = ++_token;
    final values = event.values;
    final rangeError = reportRangeError(values.dateFrom, values.dateTo);
    if (rangeError != null) {
      emit(state.copyWith(status: PreviewStatus.invalid, values: values, rangeError: rangeError));
      return;
    }
    // Con una vista ya cargada se sigue mostrando mientras llega la nueva.
    emit(state.copyWith(status: PreviewStatus.loading, values: values, clearRangeError: true, clearFailure: true));
    try {
      final preview = await _repository.preview(definition.key, toApiFilters(definition, values), compare: values.compare && canCompare(definition, values));
      if (token != _token) return;
      emit(state.copyWith(status: PreviewStatus.ready, preview: preview));
    } catch (error) {
      if (token != _token) return;
      emit(state.copyWith(status: PreviewStatus.failure, failure: toFailure(error)));
    }
  }
}
