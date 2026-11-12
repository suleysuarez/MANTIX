part of 'users_list_bloc.dart';

enum UsersListStatus { loading, success, failure }

class UsersListState extends Equatable {
  const UsersListState({this.status = UsersListStatus.loading, this.items = const [], this.info, this.page = 1, this.loadingPage = false, this.failure});

  final UsersListStatus status;

  /// Usuarios de la página actual.
  final List<ManagedUser> items;

  /// Paginación de la última respuesta; `null` si el servidor no la envió (una sola página).
  final PageInfo? info;

  /// Página pedida (base 1).
  final int page;

  /// Se está pidiendo otra página mientras se siguen mostrando los datos anteriores.
  final bool loadingPage;
  final Failure? failure;

  int get total => info?.total ?? items.length;
  int get totalPages => info?.totalPages ?? 1;

  UsersListState copyWith({int? page, bool? loadingPage}) => UsersListState(status: status, items: items, info: info, page: page ?? this.page, loadingPage: loadingPage ?? this.loadingPage, failure: failure);

  @override
  List<Object?> get props => [status, items, info, page, loadingPage, failure];
}
