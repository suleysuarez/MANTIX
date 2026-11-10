import 'package:equatable/equatable.dart';

/// Filtros de la bandeja de triaje. Los vacíos no filtran.
class QueueFilters extends Equatable {
  const QueueFilters({this.search = '', this.categories = const [], this.priorities = const [], this.technicianIds = const [], this.dateFrom, this.dateTo});

  /// Número, título o descripción.
  final String search;
  final List<String> categories;
  final List<String> priorities;
  final List<int> technicianIds;

  /// Recibidas entre estos días (inclusive).
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Filtros de la hoja de filtros que están puestos (la búsqueda tiene su propio campo).
  int get activeCount => (categories.isEmpty ? 0 : 1) + (priorities.isEmpty ? 0 : 1) + (technicianIds.isEmpty ? 0 : 1) + (dateFrom != null || dateTo != null ? 1 : 0);

  bool get isEmpty => activeCount == 0 && search.trim().isEmpty;

  QueueFilters copyWith({String? search, List<String>? categories, List<String>? priorities, List<int>? technicianIds, DateTime? dateFrom, DateTime? dateTo, bool clearDates = false}) => QueueFilters(
        search: search ?? this.search,
        categories: categories ?? this.categories,
        priorities: priorities ?? this.priorities,
        technicianIds: technicianIds ?? this.technicianIds,
        dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
        dateTo: clearDates ? null : (dateTo ?? this.dateTo),
      );

  /// Quita los filtros de la hoja y conserva la búsqueda.
  QueueFilters cleared() => QueueFilters(search: search);

  @override
  List<Object?> get props => [search, categories, priorities, technicianIds, dateFrom, dateTo];
}
