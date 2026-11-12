import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../core/format/report_format.dart';
import '../../models/reports/report_models.dart';
import '../../repositories/reports/reports_repository.dart';

part 'reports_catalog_event.dart';
part 'reports_catalog_state.dart';

/// La galería de reportes: carga el catálogo, se queda con los que ofrece la app
/// ([relevantReports]) y recuerda cuál está elegido. Al cargar elige el primero; si el elegido
/// desaparece del catálogo, vuelve al primero.
class ReportsCatalogBloc extends Bloc<ReportsCatalogEvent, ReportsCatalogState> {
  ReportsCatalogBloc({required this._repository}) : super(const ReportsCatalogState()) {
    on<ReportsCatalogRequested>(_onRequested);
    on<ReportSelected>((event, emit) {
      // Solo se puede elegir un reporte de la galería.
      if (state.reports.any((report) => report.key == event.key)) emit(state.copyWith(selectedKey: event.key));
    });
  }

  final ReportsRepository _repository;

  Future<void> _onRequested(ReportsCatalogRequested event, Emitter<ReportsCatalogState> emit) async {
    // Al recargar se conserva lo que ya se ve; solo cambia lo que llega.
    emit(state.copyWith(status: CatalogStatus.loading, clearFailure: true));
    try {
      final catalog = await _repository.catalog();
      final reports = relevantOf(catalog.reports);
      final keep = reports.any((report) => report.key == state.selectedKey);
      emit(state.copyWith(status: CatalogStatus.ready, reports: reports, maxRows: catalog.maxRows, selectedKey: keep ? state.selectedKey : reports.firstOrNull?.key, clearSelected: !keep && reports.isEmpty));
    } catch (error) {
      emit(state.copyWith(status: CatalogStatus.failure, failure: toFailure(error)));
    } finally {
      event.done?.complete();
    }
  }
}
