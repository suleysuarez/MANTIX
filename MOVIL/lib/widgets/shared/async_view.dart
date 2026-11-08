import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'skeleton.dart';

/// Resuelve los cuatro estados de una pantalla (docs/flutter-plan.md): cargando
/// (esqueleto), error (con reintento), vacío y con datos. Cada pantalla de datos
/// pasa por aquí para no repetir ni olvidar ninguno.
///
/// Recibe lo que ya resolvió un Bloc: [data] si hay datos, [failure] si falló y,
/// si no hay ninguno de los dos, se muestra el esqueleto. Al refrescar con datos
/// ya cargados se siguen mostrando los datos, no el esqueleto.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.data,
    this.loaded,
    this.failure,
    this.isEmpty,
    this.empty,
    this.loading,
    this.onRetry,
  });

  /// Construye la pantalla con los datos cargados.
  final Widget Function(T data) data;

  /// Datos ya cargados; `null` mientras no los haya.
  final T? loaded;
  final Failure? failure;

  /// Decide si los datos cuentan como vacíos (por ejemplo, una lista sin elementos).
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final current = loaded;
    if (current != null) {
      if (isEmpty?.call(current) ?? false) {
        return empty ?? const EmptyState(title: 'No hay nada por aquí todavía');
      }
      return data(current);
    }
    final error = failure;
    if (error != null) return ErrorState(failure: error, onRetry: onRetry);
    return loading ?? const SkeletonList();
  }
}
