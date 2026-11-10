import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/page_info.dart';

/// Catálogos que usa el tablero de tickets: categorías, prioridades y técnicos. Cualquier
/// error de red o de servidor sale como un `Failure` ya traducido.
class CatalogsRepository {
  CatalogsRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  List<T> _list<T>(Object? data, T Function(Map<String, Object?>) parse) {
    if (data is! List) return const [];
    return [for (final item in data) parse((item as Map).cast<String, Object?>())];
  }

  /// Cuánto se reutiliza la lista de categorías antes de volver a pedirla.
  static const categoriesTtl = Duration(minutes: 5);

  List<RequestCategory>? _categories;
  DateTime? _categoriesAt;

  /// Categorías activas. El servidor no las pagina ni las busca: son pocas, así que se piden
  /// una vez (cada búsqueda de la hoja crea un Bloc nuevo y no debe volver a pedirlas) y la
  /// app las filtra y reparte por páginas. [refresh] fuerza una petición nueva.
  Future<List<RequestCategory>> categories({bool refresh = false}) => _guard(() async {
        final cached = _categories;
        final at = _categoriesAt;
        if (!refresh && cached != null && at != null && DateTime.now().difference(at) < categoriesTtl) return cached;
        final response = await _dio.get<Object?>('/maintenance/categories');
        final fresh = _list(response.data, RequestCategory.fromJson);
        _categories = fresh;
        _categoriesAt = DateTime.now();
        return fresh;
      });

  /// Prioridades activas, de la más urgente a la menos.
  Future<List<PriorityOption>> priorities() => _guard(() async {
        final response = await _dio.get<Object?>('/priorities');
        return _list(response.data, PriorityOption.fromJson);
      });

  /// Técnicos por páginas (requiere `tecnicos:ver`). [search] busca por nombre, correo o
  /// especialidad. El servidor no filtra por cuenta activa: quien llama descarta los inactivos.
  Future<PagedResult<TechnicianOption>> technicians({String? search, int page = 1, int size = PageInfo.defaultPageSize}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/technicians', queryParameters: {
          'page': page,
          'size': size,
          'sort': 'name',
          if (term != null && term.isNotEmpty) 'search': term,
        });
        return PagedResult(
          items: _list(response.data, TechnicianOption.fromJson),
          info: PageInfo.fromHeaders(response.headers),
        );
      });
}
