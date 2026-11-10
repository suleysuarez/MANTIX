import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../repositories/catalogs/catalogs_repository.dart';

enum PrioritiesStatus { loading, success, failure }

class PrioritiesState extends Equatable {
  const PrioritiesState({this.status = PrioritiesStatus.loading, this.priorities = const [], this.failure});

  final PrioritiesStatus status;
  final List<PriorityOption> priorities;
  final Failure? failure;

  @override
  List<Object?> get props => [status, priorities, failure];
}

/// Prioridades activas para elegir al clasificar un ticket. Son pocas y no cambian durante
/// la sesión: una carga, sin eventos (por eso es un Cubit).
class PrioritiesCubit extends Cubit<PrioritiesState> {
  PrioritiesCubit(this._repository) : super(const PrioritiesState());

  final CatalogsRepository _repository;

  Future<void> load() async {
    emit(const PrioritiesState());
    try {
      final priorities = await _repository.priorities();
      emit(PrioritiesState(status: PrioritiesStatus.success, priorities: [...priorities]..sort((a, b) => b.level.compareTo(a.level))));
    } catch (error) {
      emit(PrioritiesState(status: PrioritiesStatus.failure, failure: toFailure(error)));
    }
  }
}
