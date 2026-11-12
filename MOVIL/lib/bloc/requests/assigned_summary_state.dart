part of 'assigned_summary_bloc.dart';

enum AssignedSummaryStatus { loading, ready, failure }

class AssignedSummaryState extends Equatable {
  const AssignedSummaryState({this.status = AssignedSummaryStatus.loading, this.open, this.inProgress, this.urgent, this.failure});

  final AssignedSummaryStatus status;

  /// Tickets abiertos asignados; `null` mientras no llegan.
  final int? open;

  /// Los que están en proceso.
  final int? inProgress;

  /// Los abiertos con prioridad crítica o alta.
  final int? urgent;
  final Failure? failure;

  bool get initialLoading => status == AssignedSummaryStatus.loading && open == null;

  @override
  List<Object?> get props => [status, open, inProgress, urgent, failure];
}
