part of 'users_summary_bloc.dart';

enum UsersSummaryStatus { loading, ready, failure }

class UsersSummaryState extends Equatable {
  const UsersSummaryState({this.status = UsersSummaryStatus.loading, this.summary, this.failure});

  final UsersSummaryStatus status;

  /// Último resumen recibido; sigue visible mientras se recarga o si la recarga falla.
  final UsersSummary? summary;
  final Failure? failure;

  /// Se muestra «no disponible» con reintento solo si no hay nada que enseñar.
  bool get unavailable => status == UsersSummaryStatus.failure && summary == null;

  UsersSummaryState copyWith({UsersSummaryStatus? status, UsersSummary? summary, Failure? failure, bool clearFailure = false}) => UsersSummaryState(
        status: status ?? this.status,
        summary: summary ?? this.summary,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, summary, failure];
}
