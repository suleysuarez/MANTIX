import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/failure_mapper.dart';
import '../../models/page_info.dart';
import '../../models/users/user_models.dart';

/// Acceso a la API de usuarios y roles. Cualquier error de red o de servidor sale como un
/// `Failure` ya traducido. Cada cambio avisa por [changes] para que las listas abiertas se
/// recarguen sin acoplarse a quien lo hizo.
class UsersRepository {
  UsersRepository(this._dio);

  final Dio _dio;
  final _changes = StreamController<void>.broadcast();

  /// Emite después de cambiar roles, estado o datos de una persona.
  Stream<void> get changes => _changes.stream;

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

  /// Usuarios por páginas (requiere `usuarios:ver`). [role] es el código de un rol y
  /// [isActive] filtra cuentas activas o inactivas; `null` no filtra.
  Future<PagedResult<ManagedUser>> listUsers({int page = 1, int size = PageInfo.defaultPageSize, String? search, String? role, bool? isActive, DateTime? createdFrom, DateTime? createdTo, String? sort}) => _guard(() async {
        final term = search?.trim();
        final response = await _dio.get<Object?>('/admin/users', queryParameters: {
          'page': page,
          'size': size,
          if (term != null && term.isNotEmpty) 'search': term,
          'role': ?role,
          'is_active': ?isActive,
          if (createdFrom != null) 'created_from': createdFrom.toUtc().toIso8601String(),
          if (createdTo != null) 'created_to': createdTo.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1)).toUtc().toIso8601String(),
          'sort': ?sort,
        });
        return PagedResult(items: _list(response.data, ManagedUser.fromJson), info: PageInfo.fromHeaders(response.headers));
      });

  /// Cifras de la pantalla (requiere `usuarios:ver`).
  Future<UsersSummary> summary() => _guard(() async {
        final response = await _dio.get<Map<String, Object?>>('/admin/users/summary');
        return UsersSummary.fromJson(response.data!);
      });

  /// Personas activas que ya entraron y aún no tienen rol (requiere `usuarios:ver`). El
  /// servidor no pagina esta lista.
  Future<List<PendingUser>> pending() => _guard(() async {
        final response = await _dio.get<Object?>('/admin/users/pending');
        return _list(response.data, PendingUser.fromJson);
      });

  /// Roles activos que se pueden asignar (requiere `usuarios:ver`).
  Future<List<UserRoleRef>> assignableRoles() => _guard(() async {
        final response = await _dio.get<Object?>('/admin/roles');
        return _list(response.data, UserRoleRef.fromJson);
      });

  /// Roles con su descripción y cuántas personas los tienen. Con [detailed] usa
  /// `GET /admin/roles/manage` (requiere `usuarios:asignar`); sin él, la lista de roles y los
  /// conteos del resumen, que solo piden `usuarios:ver`.
  Future<List<RoleInfo>> rolesOverview({required bool detailed}) => _guard(() async {
        if (detailed) {
          final response = await _dio.get<Object?>('/admin/roles/manage');
          return _list(response.data, RoleInfo.fromJson);
        }
        final roles = await assignableRoles();
        final counts = {for (final item in (await summary()).byRole) item.code: item.count};
        return [for (final role in roles) RoleInfo(id: role.id, code: role.code, name: role.name, userCount: counts[role.code] ?? 0)];
      });

  /// Reemplaza los roles de una persona (de 1 a 10; requiere `usuarios:asignar`). Sirve igual
  /// para quien está pendiente.
  Future<ManagedUser> setRoles(int userId, List<int> roleIds) => _guard(() async {
        final response = await _dio.put<Map<String, Object?>>('/admin/users/$userId/roles', data: {'role_ids': roleIds});
        _changes.add(null);
        return ManagedUser.fromJson(response.data!);
      });

  /// Activa o desactiva una cuenta (requiere `usuarios:cambiar_estado`).
  Future<ManagedUser> setActive(int userId, {required bool active}) => _guard(() async {
        final response = await _dio.post<Map<String, Object?>>('/admin/users/$userId/${active ? 'activate' : 'deactivate'}');
        _changes.add(null);
        return ManagedUser.fromJson(response.data!);
      });

  /// Cambia el teléfono (requiere `usuarios:editar`). Solo viaja si se pasa: ausente no cambia;
  /// `(value: null)` lo borra y `(value: 'x')` lo cambia.
  Future<ManagedUser> updateContact(int userId, {({String? value})? phone}) => _guard(() async {
        final response = await _dio.patch<Map<String, Object?>>('/admin/users/$userId', data: {
          if (phone != null) 'phone': phone.value,
        });
        _changes.add(null);
        return ManagedUser.fromJson(response.data!);
      });
}
