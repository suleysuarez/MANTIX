part of 'queue_summary_bloc.dart';

enum SummaryStatus { loading, ready, failure }

class QueueSummaryState extends Equatable {
  const QueueSummaryState({this.status = SummaryStatus.loading, this.summary, this.failure});

  final SummaryStatus status;

  /// Último resumen recibido; sigue visible mientras se recarga o si la recarga falla.
  final QueueSummary? summary;
  final Failure? failure;

  /// Se muestra «no disponible» con reintento solo si no hay nada que enseñar.
  bool get unavailable => status == SummaryStatus.failure && summary == null;

  QueueSummaryState copyWith({SummaryStatus? status, QueueSummary? summary, Failure? failure, bool clearFailure = false}) => QueueSummaryState(
        status: status ?? this.status,
        summary: summary ?? this.summary,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, summary, failure];
}
