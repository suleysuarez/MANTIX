import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/page_info.dart';
import '../../models/technicians/technician_models.dart';

/// Acceso a la API de técnicos: el catálogo que usan la pantalla de técnicos y el selector de
/// asignación de tickets, su carga, sus indicadores y los cambios del perfil. Cualquier error de
/// red o de servidor sale como un `Failure` ya traducido. Cada cambio avisa por [changes] para
/// que la lista abierta se recargue sin acoplarse a quien lo hizo.
class TechniciansRepository {
  TechniciansRepository(this._dio);

  /// Tamaño de página con el que se trae el catálogo completo (el máximo del servidor).
  static const allPageSize = 500;

  final Dio _dio;
  final _changes = StreamController<void>.broadcast();

  /// Emite después de registrar o editar un técnico.
  Stream<void> get changes => _changes.stream;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  /// Técnicos por páginas (requiere `tecnicos:ver`). [search] busca por nombre, correo o
  /// especialidad. [isActive] `true` deja solo los de cuenta activa: los que se pueden asignar.
  Future<PagedResult<Technician>> list({String? search, int page = 1, int size = PageInfo.defaultPageSize, bool? isActive}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/technicians', queryParameters: {
          'page': page,
          'size': size,
          'sort': 'name',
          if (term != null && term.isNotEmpty) 'search': term,
          'is_active': ?isActive,
        });
        final data = response.data;
        return PagedResult(
          items: [if (data is List) for (final item in data) Technician.fromJson((item as Map).cast<String, Object?>())],
          info: PageInfo.fromHeaders(response.headers),
        );
      });

  /// Todos los técnicos. El servidor no ordena ni filtra por carga, así que la pantalla trae el
  /// catálogo entero (son pocos) y lo filtra, ordena y pagina ella, como la web.
  Future<List<Technician>> all() async {
    final technicians = <Technician>[];
    for (int? page = 1; page != null;) {
      final result = await list(page: page, size: allPageSize);
      technicians.addAll(result.items);
      page = result.info?.nextPage;
    }
    return technicians;
  }

  /// Tickets abiertos y resueltos de cada técnico en los últimos [days] días (requiere
  /// `dashboard:ver`).
  Future<Workload> workload({int days = 30}) => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/dashboard/workload', queryParameters: {'days': days});
        return Workload.fromJson(response.data!);
      });

  /// Indicadores de cada técnico en [period] (`7d`, `30d`, `12m`; requiere `dashboard:ver`).
  Future<PerformanceReport> performance({String period = '30d'}) => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/dashboard/technicians', queryParameters: {'period': period});
        return PerformanceReport.fromJson(response.data!);
      });

  /// Activa o desactiva la **cuenta de usuario** del técnico (requiere `usuarios:cambiar_estado`):
  /// el perfil de técnico no tiene un estado propio, su `is_active` es el de la cuenta. Con la
  /// cuenta desactivada la persona no puede iniciar sesión y no se le pueden asignar tickets.
  Future<void> setAccountActive(int userId, {required bool active}) => _guard(() async {
        await _dio.post<Object?>('/admin/users/$userId/${active ? 'activate' : 'deactivate'}');
        _changes.add(null);
      });

  static String? _rate(double? value) => value?.toStringAsFixed(2);

  /// Abre un perfil de técnico al usuario [userId] (requiere `tecnicos:crear`). Un usuario que
  /// ya tiene perfil llega como `technician_profile_exists`; uno inactivo, como `user_not_found`.
  Future<Technician> create({required int userId, String? specialization, double? hourlyRate}) => _guard(() async {
        final response = await _dio.post<Map<String, Object?>>('/technicians', data: {
          'user_id': userId,
          'specialization': specialization,
          'hourly_rate': _rate(hourlyRate),
        });
        _changes.add(null);
        return Technician.fromJson(response.data!);
      });

  /// Cambia el perfil (requiere `tecnicos:editar`). Solo viaja el campo que se pasa: ausente no
  /// cambia; `(value: null)` lo borra y `(value: x)` lo cambia.
  Future<Technician> update(int id, {({String? value})? specialization, ({double? value})? hourlyRate, bool? isAvailable}) => _guard(() async {
        final response = await _dio.patch<Map<String, Object?>>('/technicians/$id', data: {
          if (specialization != null) 'specialization': specialization.value,
          if (hourlyRate != null) 'hourly_rate': _rate(hourlyRate.value),
          'is_available': ?isAvailable,
        });
        _changes.add(null);
        return Technician.fromJson(response.data!);
      });
}
