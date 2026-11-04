/// Modelos de la API de solicitudes (tickets) y equipos. Escritos a mano, con
/// lectura tolerante: un campo opcional ausente no rompe la pantalla.
library;

DateTime _date(Object? value) => DateTime.parse(value! as String).toLocal();

DateTime? _dateOrNull(Object? value) => value is String ? DateTime.parse(value).toLocal() : null;

/// Fila de `GET /maintenance/requests`.
class TicketListItem {
  const TicketListItem({
    required this.id,
    required this.ticketNumber,
    required this.title,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.category,
  });

  factory TicketListItem.fromJson(Map<String, Object?> json) => TicketListItem(
        id: json['id']! as int,
        ticketNumber: json['ticket_number']! as String,
        title: json['title']! as String,
        priority: json['priority']! as String,
        status: json['status']! as String,
        category: json['category'] as String?,
        createdAt: _date(json['created_at']),
      );

  final int id;
  final String ticketNumber;
  final String title;
  final String priority;
  final String status;
  final String? category;
  final DateTime createdAt;
}

class EquipmentRef {
  const EquipmentRef({required this.id, required this.assetTag, required this.brand, required this.model});

  factory EquipmentRef.fromJson(Map<String, Object?> json) => EquipmentRef(
        id: json['id']! as int,
        assetTag: json['asset_tag']! as String,
        brand: json['brand']! as String,
        model: json['model']! as String,
      );

  final int id;
  final String assetTag;
  final String brand;
  final String model;

  String get label => '$assetTag · $brand $model';
}

class StatusHistoryEntry {
  const StatusHistoryEntry({required this.toStatus, required this.changedAt, this.fromStatus, this.notes});

  factory StatusHistoryEntry.fromJson(Map<String, Object?> json) => StatusHistoryEntry(
        fromStatus: json['from_status'] as String?,
        toStatus: json['to_status']! as String,
        changedAt: _date(json['changed_at']),
        notes: json['notes'] as String?,
      );

  final String? fromStatus;
  final String toStatus;
  final DateTime changedAt;
  final String? notes;
}

/// `GET /maintenance/requests/{id}`.
class TicketDetail {
  const TicketDetail({
    required this.id,
    required this.ticketNumber,
    required this.equipment,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.history,
    this.category,
    this.resolutionSummary,
    this.technicianName,
  });

  factory TicketDetail.fromJson(Map<String, Object?> json) {
    final assignment = json['current_assignment'];
    final technician = assignment is Map ? assignment['technician'] : null;
    final history = json['status_history'];
    return TicketDetail(
      id: json['id']! as int,
      ticketNumber: json['ticket_number']! as String,
      equipment: EquipmentRef.fromJson((json['equipment']! as Map).cast<String, Object?>()),
      title: json['title']! as String,
      description: json['description']! as String,
      priority: json['priority']! as String,
      category: json['category'] as String?,
      status: json['status']! as String,
      resolutionSummary: json['resolution_summary'] as String?,
      createdAt: _date(json['created_at']),
      updatedAt: _dateOrNull(json['updated_at']) ?? _date(json['created_at']),
      technicianName: technician is Map ? technician['full_name'] as String? : null,
      history: history is List
          ? [for (final entry in history) StatusHistoryEntry.fromJson((entry as Map).cast<String, Object?>())]
          : const [],
    );
  }

  final int id;
  final String ticketNumber;
  final EquipmentRef equipment;
  final String title;
  final String description;
  final String priority;
  final String? category;
  final String status;
  final String? resolutionSummary;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? technicianName;
  final List<StatusHistoryEntry> history;
}

class Attachment {
  const Attachment({required this.id, required this.fileName, required this.mimeType, required this.fileSize});

  factory Attachment.fromJson(Map<String, Object?> json) => Attachment(
        id: json['id']! as int,
        fileName: json['file_name']! as String,
        mimeType: json['mime_type'] as String? ?? '',
        fileSize: json['file_size'] as int? ?? 0,
      );

  final int id;
  final String fileName;
  final String mimeType;
  final int fileSize;
}

/// Equipo del selector. Del catálogo solo se leen estos campos: la app no muestra
/// custodio ni ubicación (decisión de la Fase 4, ver docs/flutter-plan.md).
class EquipmentOption {
  const EquipmentOption({
    required this.id,
    required this.assetTag,
    required this.brand,
    required this.model,
    required this.typeName,
    required this.status,
  });

  factory EquipmentOption.fromJson(Map<String, Object?> json) {
    final type = json['equipment_type'];
    return EquipmentOption(
      id: json['id']! as int,
      assetTag: json['asset_tag']! as String,
      brand: json['brand']! as String,
      model: json['model']! as String,
      typeName: type is Map ? (type['name'] as String? ?? '') : '',
      status: json['status'] as String? ?? '',
    );
  }

  final int id;
  final String assetTag;
  final String brand;
  final String model;
  final String typeName;
  final String status;

  String get label => '$assetTag · $brand $model';
}

/// Datos del formulario de nueva solicitud.
class NewRequest {
  const NewRequest({required this.equipmentId, required this.title, required this.description, required this.priority});

  final int equipmentId;
  final String title;
  final String description;
  final String priority;

  Map<String, Object?> toJson() => {
        'equipment_id': equipmentId,
        'title': title,
        'description': description,
        'priority': priority,
      };
}
