import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/failure_mapper.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'skeleton.dart';

/// Resuelve los cuatro estados de una pantalla (docs/flutter-plan.md): cargando
/// (esqueleto), error (con reintento), vacío y con datos. Cada pantalla de datos
/// pasa por aquí para no repetir ni olvidar ninguno.
///
/// Al refrescar con datos ya cargados se siguen mostrando los datos, no el esqueleto.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.isEmpty,
    this.empty,
    this.loading,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  /// Decide si los datos cuentan como vacíos (por ejemplo, una lista sin elementos).
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const SkeletonList(),
      error: (error, _) => ErrorState(failure: toFailure(error), onRetry: onRetry),
      data: (loaded) {
        if (isEmpty?.call(loaded) ?? false) {
          return empty ?? const EmptyState(title: 'No hay nada por aquí todavía');
        }
        return data(loaded);
      },
    );
  }
}
