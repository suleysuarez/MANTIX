import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../models/catalogs/catalog_models.dart';
import '../../repositories/catalogs/catalogs_repository.dart';

class CategoryNamesState extends Equatable {
  const CategoryNamesState({this.categories = const [], this.loaded = false});

  final List<RequestCategory> categories;

  /// `true` cuando terminó la carga, con o sin éxito.
  final bool loaded;

  /// Nombre por código, para rotular tarjetas y barras.
  Map<String, String> get names => {for (final category in categories) category.code: category.name};

  @override
  List<Object?> get props => [categories, loaded];
}

/// Nombres de las categorías para mostrar en la bandeja. Si el catálogo no carga, la bandeja
/// sigue funcionando y rotula con el código (`categoryLabel`): no es un error que bloquee nada.
class CategoryNamesCubit extends Cubit<CategoryNamesState> {
  CategoryNamesCubit(this._repository) : super(const CategoryNamesState());

  final CatalogsRepository _repository;

  Future<void> load() async {
    try {
      emit(CategoryNamesState(categories: await _repository.categories(), loaded: true));
    } catch (_) {
      emit(const CategoryNamesState(loaded: true));
    }
  }
}
