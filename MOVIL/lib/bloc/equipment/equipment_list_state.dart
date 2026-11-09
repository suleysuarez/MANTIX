part of 'equipment_list_bloc.dart';

enum EquipmentListStatus { loading, success, failure }

class EquipmentListState extends Equatable {
  const EquipmentListState({
    this.status = EquipmentListStatus.loading,
    this.items = const [],
    this.info,
    this.page = 1,
    this.loadingPage = false,
    this.failure,
  });

  final EquipmentListStatus status;

  /// Equipos de la página actual.
  final List<Equipment> items;

  /// Paginación de la última respuesta; `null` si el servidor no la envió (una sola página).
  final PageInfo? info;

  /// Página pedida (base 1).
  final int page;

  /// Se está pidiendo otra página mientras se siguen mostrando los datos anteriores.
  final bool loadingPage;
  final Failure? failure;

  int get total => info?.total ?? items.length;
  int get totalPages => info?.totalPages ?? 1;

  EquipmentListState copyWith({int? page, bool? loadingPage}) => EquipmentListState(
        status: status,
        items: items,
        info: info,
        page: page ?? this.page,
        loadingPage: loadingPage ?? this.loadingPage,
        failure: failure,
      );

  @override
  List<Object?> get props => [status, items, info, page, loadingPage, failure];
}
