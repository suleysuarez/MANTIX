part of 'equipment_summary_bloc.dart';

enum SummaryStatus { loading, success, failure }

class EquipmentSummaryState extends Equatable {
  const EquipmentSummaryState({this.status = SummaryStatus.loading, this.summary, this.failure});

  final SummaryStatus status;

  /// Último resumen cargado; se conserva si un refresco falla.
  final EquipmentSummary? summary;
  final Failure? failure;

  @override
  List<Object?> get props => [status, summary, failure];
}
