part of 'reports_catalog_bloc.dart';

enum CatalogStatus { loading, ready, failure }

class ReportsCatalogState extends Equatable {
  const ReportsCatalogState({this.status = CatalogStatus.loading, this.reports = const [], this.maxRows = 10000, this.selectedKey, this.failure});

  final CatalogStatus status;

  /// Los reportes que ofrece la app, en su orden. Siguen visibles mientras se recarga o si la
  /// recarga falla.
  final List<ReportDefinition> reports;

  /// Más filas que esto no se exporta.
  final int maxRows;
  final String? selectedKey;
  final Failure? failure;

  ReportDefinition? get selected {
    for (final report in reports) {
      if (report.key == selectedKey) return report;
    }
    return null;
  }

  bool get initialLoading => status == CatalogStatus.loading && reports.isEmpty;

  /// Se muestra el error con reintento solo si no hay galería que enseñar.
  bool get unavailable => status == CatalogStatus.failure && reports.isEmpty;

  ReportsCatalogState copyWith({CatalogStatus? status, List<ReportDefinition>? reports, int? maxRows, String? selectedKey, bool clearSelected = false, Failure? failure, bool clearFailure = false}) => ReportsCatalogState(
        status: status ?? this.status,
        reports: reports ?? this.reports,
        maxRows: maxRows ?? this.maxRows,
        selectedKey: clearSelected ? null : (selectedKey ?? this.selectedKey),
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, reports, maxRows, selectedKey, failure];
}
