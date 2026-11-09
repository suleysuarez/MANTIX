part of 'equipment_catalog_bloc.dart';

sealed class EquipmentCatalogEvent {
  const EquipmentCatalogEvent();
}

/// Carga (o reintenta) las categorías y las ubicaciones.
class EquipmentCatalogStarted extends EquipmentCatalogEvent {
  const EquipmentCatalogStarted();
}
