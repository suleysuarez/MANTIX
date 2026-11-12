import '../../models/page_info.dart';
import '../../models/profile/profile_models.dart';
import '../../repositories/profile/profile_repository.dart';
import '../paged/paged_bloc.dart';

/// Mi actividad (inicios de sesión, cambios en mis datos y en mi cuenta), la más reciente primero,
/// de 20 en 20. Se vuelve a pedir con `PagedRefreshed` cuando cambian mis datos o mi foto.
class ProfileHistoryBloc extends PagedBloc<HistoryEntry> {
  ProfileHistoryBloc({required this._repository, super.pageSize});

  final ProfileRepository _repository;

  @override
  Future<PagedResult<HistoryEntry>> fetch(int page) => _repository.history(page: page, size: pageSize);
}
