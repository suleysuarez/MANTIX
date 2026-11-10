part of 'equipment_catalog_bloc.dart';

sealed class EquipmentCatalogEvent {
  const EquipmentCatalogEvent();
}

/// Añade al catálogo una categoría recién creada, sin volver a pedirlo todo.
class EquipmentTypeAdded extends EquipmentCatalogEvent {
  const EquipmentTypeAdded(this.type);

  final EquipmentType type;
}

/// Carga (o reintenta) las categorías y las ubicaciones.
class EquipmentCatalogStarted extends EquipmentCatalogEvent {
  const EquipmentCatalogStarted();
}
