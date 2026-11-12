import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/page_info.dart';
import '../../models/reports/report_models.dart';
import '../../repositories/reports/reports_repository.dart';

part 'report_history_event.dart';
part 'report_history_state.dart';

/// Las exportaciones recientes, por páginas. Cada reporte generado en la app la recarga sola.
/// Falla por separado del resto de la pantalla.
class ReportHistoryBloc extends Bloc<ReportHistoryEvent, ReportHistoryState> {
  ReportHistoryBloc({required this._repository, this.pageSize = defaultPageSize}) : super(const ReportHistoryState()) {
    on<ReportHistoryStarted>((_, emit) => _load(1, emit));
    on<ReportHistoryPageSelected>((event, emit) => _load(event.page, emit));
    on<ReportHistoryRefreshed>((event, emit) async {
      try {
        await _load(event.goToFirst ? 1 : state.page, emit);
      } finally {
        event.done?.complete();
      }
    });
    _changes = _repository.changes.listen((_) => add(const ReportHistoryRefreshed(goToFirst: true)));
  }

  static const defaultPageSize = 8;

  final ReportsRepository _repository;
  final int pageSize;
  late final StreamSubscription<void> _changes;

  Future<void> _load(int page, Emitter<ReportHistoryState> emit) async {
    // Con datos ya cargados se siguen mostrando mientras llega la página pedida.
    emit(state.items.isEmpty && state.status != HistoryStatus.success ? ReportHistoryState(page: page) : state.copyWith(page: page, loadingPage: true));
    try {
      final result = await _repository.history(page: page, size: pageSize);
      emit(ReportHistoryState(status: HistoryStatus.success, items: result.items, info: result.info, page: page));
    } catch (error) {
      emit(state.items.isEmpty ? ReportHistoryState(status: HistoryStatus.failure, page: page, failure: toFailure(error)) : state.copyWith(loadingPage: false, failure: toFailure(error)));
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
