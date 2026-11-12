part of 'schedule_detail_bloc.dart';

enum PlanBlockStatus { loading, ready, failure }

class ScheduleDetailState extends Equatable {
  const ScheduleDetailState({this.planStatus = PlanBlockStatus.loading, this.plan, this.planFailure, this.historyStatus = PlanBlockStatus.loading, this.history, this.historyFailure});

  final PlanBlockStatus planStatus;
  final MaintenanceSchedule? plan;
  final Failure? planFailure;

  final PlanBlockStatus historyStatus;
  final ScheduleHistory? history;
  final Failure? historyFailure;

  ScheduleDetailState copyWith({PlanBlockStatus? planStatus, MaintenanceSchedule? plan, Failure? planFailure, PlanBlockStatus? historyStatus, ScheduleHistory? history, Failure? historyFailure}) => ScheduleDetailState(
        planStatus: planStatus ?? this.planStatus,
        plan: plan ?? this.plan,
        planFailure: planFailure ?? this.planFailure,
        historyStatus: historyStatus ?? this.historyStatus,
        history: history ?? this.history,
        historyFailure: historyFailure ?? this.historyFailure,
      );

  @override
  List<Object?> get props => [planStatus, plan, planFailure, historyStatus, history, historyFailure];
}
