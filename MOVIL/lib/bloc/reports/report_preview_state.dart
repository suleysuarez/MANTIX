part of 'report_preview_bloc.dart';

/// [idle] aún no se ha pedido; [invalid] los filtros tienen un error y no se pidió nada.
enum PreviewStatus { idle, loading, ready, failure, invalid }

class ReportPreviewState extends Equatable {
  const ReportPreviewState({this.status = PreviewStatus.idle, this.values = const ReportFilterValues(), this.preview, this.rangeError, this.failure});

  final PreviewStatus status;

  /// Los filtros de la última petición.
  final ReportFilterValues values;

  /// La última vista recibida; sigue visible mientras se recarga o si la recarga falla.
  final ReportPreview? preview;
  final String? rangeError;
  final Failure? failure;

  bool get loading => status == PreviewStatus.loading;

  /// Se puede exportar: la vista llegó, tiene filas y no pasa del límite.
  bool get canExport => status == PreviewStatus.ready && preview != null && preview!.totalRows > 0 && !preview!.truncated;

  ReportPreviewState copyWith({PreviewStatus? status, ReportFilterValues? values, ReportPreview? preview, String? rangeError, bool clearRangeError = false, Failure? failure, bool clearFailure = false}) => ReportPreviewState(
        status: status ?? this.status,
        values: values ?? this.values,
        preview: preview ?? this.preview,
        rangeError: clearRangeError ? null : (rangeError ?? this.rangeError),
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  @override
  List<Object?> get props => [status, values, preview, rangeError, failure];
}
