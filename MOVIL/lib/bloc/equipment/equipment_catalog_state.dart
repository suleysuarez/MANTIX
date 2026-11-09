part of 'equipment_catalog_bloc.dart';

enum CatalogStatus { loading, success, failure }

class EquipmentCatalogState extends Equatable {
  const EquipmentCatalogState({this.status = CatalogStatus.loading, this.types = const [], this.locations = const [], this.failure});

  final CatalogStatus status;
  final List<EquipmentType> types;
  final List<EquipmentLocation> locations;

  /// Motivo del fallo de cualquiera de las dos listas; la que sí cargó se conserva.
  final Failure? failure;

  @override
  List<Object?> get props => [status, types, locations, failure];
}
