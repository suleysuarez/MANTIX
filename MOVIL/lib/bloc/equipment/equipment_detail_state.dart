part of 'equipment_detail_bloc.dart';

enum DetailPart { loading, success, failure }

/// Lo que la ficha del equipo carga aparte de los datos del equipo: sus tickets y sus adjuntos.
/// Cada parte carga y falla por separado, para que un error no oculte la otra.
class EquipmentDetailState extends Equatable {
  const EquipmentDetailState({
    this.tickets = const [],
    this.ticketsStatus = DetailPart.loading,
    this.ticketsFailure,
    this.attachments = const [],
    this.attachmentsStatus = DetailPart.loading,
    this.attachmentsFailure,
  });

  final List<TicketListItem> tickets;
  final DetailPart ticketsStatus;
  final Failure? ticketsFailure;
  final List<Attachment> attachments;
  final DetailPart attachmentsStatus;
  final Failure? attachmentsFailure;

  EquipmentDetailState copyWith({
    List<TicketListItem>? tickets,
    DetailPart? ticketsStatus,
    Failure? ticketsFailure,
    List<Attachment>? attachments,
    DetailPart? attachmentsStatus,
    Failure? attachmentsFailure,
  }) =>
      EquipmentDetailState(
        tickets: tickets ?? this.tickets,
        ticketsStatus: ticketsStatus ?? this.ticketsStatus,
        ticketsFailure: (ticketsStatus ?? this.ticketsStatus) == DetailPart.failure ? (ticketsFailure ?? this.ticketsFailure) : null,
        attachments: attachments ?? this.attachments,
        attachmentsStatus: attachmentsStatus ?? this.attachmentsStatus,
        attachmentsFailure: (attachmentsStatus ?? this.attachmentsStatus) == DetailPart.failure ? (attachmentsFailure ?? this.attachmentsFailure) : null,
      );

  @override
  List<Object?> get props => [tickets, ticketsStatus, ticketsFailure, attachments, attachmentsStatus, attachmentsFailure];
}
