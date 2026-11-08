part of 'request_detail_bloc.dart';

enum LoadStatus { loading, success, failure }

class RequestDetailState extends Equatable {
  const RequestDetailState({
    this.status = LoadStatus.loading,
    this.ticket,
    this.failure,
    this.attachmentsStatus = LoadStatus.loading,
    this.attachments = const [],
  });

  final LoadStatus status;
  final TicketDetail? ticket;
  final Failure? failure;
  final LoadStatus attachmentsStatus;
  final List<Attachment> attachments;

  RequestDetailState copyWith({
    LoadStatus? status,
    TicketDetail? ticket,
    bool clearTicket = false,
    Failure? failure,
    bool clearFailure = false,
    LoadStatus? attachmentsStatus,
    List<Attachment>? attachments,
  }) =>
      RequestDetailState(
        status: status ?? this.status,
        ticket: clearTicket ? null : (ticket ?? this.ticket),
        failure: clearFailure ? null : (failure ?? this.failure),
        attachmentsStatus: attachmentsStatus ?? this.attachmentsStatus,
        attachments: attachments ?? this.attachments,
      );

  @override
  List<Object?> get props => [status, ticket, failure, attachmentsStatus, attachments];
}
