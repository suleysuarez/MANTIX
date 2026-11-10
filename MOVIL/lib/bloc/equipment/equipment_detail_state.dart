part of 'equipment_detail_bloc.dart';

enum DetailPart { loading, success, failure }

/// Lo que la ficha del equipo carga aparte de los datos del equipo: sus tickets, sus
/// mantenimientos y sus adjuntos. Cada parte carga y falla por separado, para que un error no
/// oculte las otras.
class EquipmentDetailState extends Equatable {
  const EquipmentDetailState({
    this.tickets = const [],
    this.ticketsStatus = DetailPart.loading,
    this.ticketsFailure,
    this.records = const [],
    this.recordsStatus = DetailPart.loading,
    this.recordsFailure,
    this.recordsTotal = 0,
    this.attachments = const [],
    this.attachmentsStatus = DetailPart.loading,
    this.attachmentsFailure,
  });

  final List<TicketListItem> tickets;
  final DetailPart ticketsStatus;
  final Failure? ticketsFailure;
  final List<MaintenanceRecord> records;
  final DetailPart recordsStatus;
  final Failure? recordsFailure;

  /// Mantenimientos que tiene el equipo en total (la lista trae solo los más recientes).
  final int recordsTotal;
  final List<Attachment> attachments;
  final DetailPart attachmentsStatus;
  final Failure? attachmentsFailure;

  /// El historial de mantenimientos exige `tickets:ver_todos`; sin ese permiso no se muestra
  /// la lista (ni un error): la ficha solo enseña el último mantenimiento del equipo.
  bool get recordsForbidden => recordsStatus == DetailPart.failure && recordsFailure is ForbiddenFailure;

  EquipmentDetailState copyWith({
    List<TicketListItem>? tickets,
    DetailPart? ticketsStatus,
    Failure? ticketsFailure,
    List<MaintenanceRecord>? records,
    DetailPart? recordsStatus,
    Failure? recordsFailure,
    int? recordsTotal,
    List<Attachment>? attachments,
    DetailPart? attachmentsStatus,
    Failure? attachmentsFailure,
  }) {
    final nextTickets = ticketsStatus ?? this.ticketsStatus;
    final nextRecords = recordsStatus ?? this.recordsStatus;
    final nextAttachments = attachmentsStatus ?? this.attachmentsStatus;
    return EquipmentDetailState(
      tickets: tickets ?? this.tickets,
      ticketsStatus: nextTickets,
      ticketsFailure: nextTickets == DetailPart.failure ? (ticketsFailure ?? this.ticketsFailure) : null,
      records: records ?? this.records,
      recordsStatus: nextRecords,
      recordsFailure: nextRecords == DetailPart.failure ? (recordsFailure ?? this.recordsFailure) : null,
      recordsTotal: recordsTotal ?? this.recordsTotal,
      attachments: attachments ?? this.attachments,
      attachmentsStatus: nextAttachments,
      attachmentsFailure: nextAttachments == DetailPart.failure ? (attachmentsFailure ?? this.attachmentsFailure) : null,
    );
  }

  @override
  List<Object?> get props => [tickets, ticketsStatus, ticketsFailure, records, recordsStatus, recordsFailure, recordsTotal, attachments, attachmentsStatus, attachmentsFailure];
}
