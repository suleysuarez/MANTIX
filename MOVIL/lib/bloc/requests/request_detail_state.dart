part of 'request_detail_bloc.dart';

enum LoadStatus { loading, success, failure }

class RequestDetailState extends Equatable {
  const RequestDetailState({
    this.status = LoadStatus.loading,
    this.ticket,
    this.failure,
    this.attachmentsStatus = LoadStatus.loading,
    this.attachments = const [],
    this.workflow = const [],
    this.changing = false,
    this.changeSerial = 0,
    this.changedTo,
    this.changeFailure,
  });

  final LoadStatus status;
  final TicketDetail? ticket;
  final Failure? failure;
  final LoadStatus attachmentsStatus;
  final List<Attachment> attachments;

  /// Flujo de estados; vacío si no se pidió o no cargó (entonces no hay acciones).
  final List<WorkflowStatus> workflow;

  /// Hay un cambio de estado en curso.
  final bool changing;

  /// Sube en cada cambio terminado (bien o mal): la pantalla avisa una vez por número.
  final int changeSerial;

  /// A qué estado pasó el último cambio terminado bien; `null` si falló.
  final String? changedTo;

  /// Por qué falló el último cambio; `null` si salió bien.
  final Failure? changeFailure;

  RequestDetailState copyWith({
    LoadStatus? status,
    TicketDetail? ticket,
    bool clearTicket = false,
    Failure? failure,
    bool clearFailure = false,
    LoadStatus? attachmentsStatus,
    List<Attachment>? attachments,
    List<WorkflowStatus>? workflow,
    bool? changing,
    int? changeSerial,
    String? changedTo,
    Failure? changeFailure,
    bool clearChange = false,
  }) =>
      RequestDetailState(
        status: status ?? this.status,
        ticket: clearTicket ? null : (ticket ?? this.ticket),
        failure: clearFailure ? null : (failure ?? this.failure),
        attachmentsStatus: attachmentsStatus ?? this.attachmentsStatus,
        attachments: attachments ?? this.attachments,
        workflow: workflow ?? this.workflow,
        changing: changing ?? this.changing,
        changeSerial: changeSerial ?? this.changeSerial,
        changedTo: clearChange ? null : (changedTo ?? this.changedTo),
        changeFailure: clearChange ? null : (changeFailure ?? this.changeFailure),
      );

  @override
  List<Object?> get props => [status, ticket, failure, attachmentsStatus, attachments, workflow, changing, changeSerial, changedTo, changeFailure];
}
