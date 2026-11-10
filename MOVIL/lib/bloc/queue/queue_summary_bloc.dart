import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/queue/queue_models.dart';
import '../../repositories/queue/queue_repository.dart';

part 'queue_summary_event.dart';
part 'queue_summary_state.dart';

/// Tarjetas de arriba y «Pulso de la cola». Falla por separado del tablero: si el resumen no
/// carga, el tablero sigue funcionando y la tarjeta muestra «no disponible» con reintento.
class QueueSummaryBloc extends Bloc<QueueSummaryEvent, QueueSummaryState> {
  QueueSummaryBloc({required this._repository}) : super(const QueueSummaryState()) {
    on<QueueSummaryRequested>(_onRequested);
  }

  final QueueRepository _repository;

  Future<void> _onRequested(QueueSummaryRequested event, Emitter<QueueSummaryState> emit) async {
    // Al recargar se conserva el último resumen visible; solo cambia lo que llega.
    emit(state.copyWith(status: SummaryStatus.loading, clearFailure: true));
    try {
      final summary = await _repository.summary();
      emit(state.copyWith(status: SummaryStatus.ready, summary: summary));
    } catch (error) {
      emit(state.copyWith(status: SummaryStatus.failure, failure: toFailure(error)));
    }
  }
}
