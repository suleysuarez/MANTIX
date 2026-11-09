import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';

part 'equipment_catalog_event.dart';
part 'equipment_catalog_state.dart';

/// Categorías y ubicaciones: alimentan el filtro del listado y el formulario de alta.
class EquipmentCatalogBloc extends Bloc<EquipmentCatalogEvent, EquipmentCatalogState> {
  EquipmentCatalogBloc({required this._repository}) : super(const EquipmentCatalogState()) {
    on<EquipmentCatalogStarted>(_onStarted);
  }

  final EquipmentRepository _repository;

  Future<void> _onStarted(EquipmentCatalogStarted event, Emitter<EquipmentCatalogState> emit) async {
    emit(EquipmentCatalogState(types: state.types, locations: state.locations));
    // Las dos listas se piden a la vez; si una falla se conserva la otra.
    final results = await Future.wait<Object?>([_attempt(_repository.types), _attempt(_repository.locations)]);
    final types = results[0];
    final locations = results[1];
    final error = types is List<EquipmentType> ? (locations is List<EquipmentLocation> ? null : locations) : types;
    emit(EquipmentCatalogState(
      status: error == null ? CatalogStatus.success : CatalogStatus.failure,
      types: types is List<EquipmentType> ? types : const [],
      locations: locations is List<EquipmentLocation> ? locations : const [],
      failure: error == null ? null : toFailure(error),
    ));
  }

  /// El resultado de [call] o, si falla, el error (también si lo lanza al llamarla).
  static Future<Object?> _attempt(Future<Object?> Function() call) async {
    try {
      return await call();
    } catch (error) {
      return error;
    }
  }
}
