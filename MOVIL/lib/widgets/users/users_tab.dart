import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/users/assignable_roles_cubit.dart';
import '../../bloc/users/users_list_bloc.dart';
import '../../bloc/users/users_summary_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/users/user_models.dart';
import '../../repositories/users/users_repository.dart';
import '../shared/empty_state.dart';
import '../shared/filter_widgets.dart';
import '../shared/multi_select_sheet.dart' show FilterButton;
import '../shared/paginator.dart';
import '../shared/skeleton.dart';
import 'user_cards.dart';
import 'users_filter_sheet.dart';
import 'users_summary_card.dart';

/// Pestaña «Usuarios»: cifras, búsqueda, filtros (rol, estado y fecha de creación), lista por
/// páginas y estados de carga, vacío y error. Tirar hacia abajo recarga la lista y las cifras.
/// Cambiar un filtro o el tamaño de página crea un `UsersListBloc` nuevo (con otra `key`), igual
/// que en Equipos; moverse entre páginas es un evento.
class UsersTab extends StatefulWidget {
  const UsersTab({super.key, this.onOpen, this.now});

  /// Qué pasa al tocar una persona (el detalle); sin él las tarjetas no se pueden tocar.
  final ValueChanged<ManagedUser>? onOpen;

  /// Hora con la que se calcula el último acceso (se inyecta para probarla).
  final DateTime? now;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> with AutomaticKeepAliveClientMixin {
  static const _debounce = Duration(milliseconds: 350);

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _timer;
  String _search = '';
  UsersFilters _filters = const UsersFilters();
  final int _pageSize = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// La búsqueda espera a que se deje de escribir antes de pedir.
  void _onSearchChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      final term = text.trim();
      if (mounted && term != _search) setState(() => _search = term);
    });
  }

  void _clearSearch() {
    _timer?.cancel();
    _searchController.clear();
    if (_search.isNotEmpty) setState(() => _search = '');
  }

  Future<void> _showFilters() async {
    final result = await showUsersFilterSheet(context, initial: _filters, roles: context.read<AssignableRolesCubit>().state.roles);
    if (result == null || !mounted || result == _filters) return;
    setState(() => _filters = result);
  }

  void _clearAll() {
    _timer?.cancel();
    _searchController.clear();
    setState(() {
      _search = '';
      _filters = const UsersFilters();
    });
  }

  bool get _filtered => _search.isNotEmpty || _filters.activeCount > 0;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final repository = context.read<UsersRepository>();
    return BlocProvider(
      key: ValueKey('$_search|${_filters.role}|${_filters.isActive}|${_filters.dates}|$_pageSize'),
      create: (_) => UsersListBloc(
        repository: repository,
        search: _search,
        role: _filters.role,
        isActive: _filters.isActive,
        createdFrom: _filters.dates?.start,
        createdTo: _filters.dates?.end,
        pageSize: _pageSize,
      )..add(const UsersListStarted()),
      child: Builder(
        builder: (context) => RefreshIndicator(
          color: AppColors.steel,
          onRefresh: () {
            final summary = Completer<void>();
            context.read<UsersSummaryBloc>().add(UsersSummaryRequested(done: summary));
            return Future.wait([context.read<UsersListBloc>().refresh(), summary.future]);
          },
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
            children: [
              BlocBuilder<UsersSummaryBloc, UsersSummaryState>(
                builder: (context, state) => UsersSummaryCard(summary: state.summary, unavailable: state.unavailable, onRetry: () => context.read<UsersSummaryBloc>().add(const UsersSummaryRequested())),
              ),
              const SizedBox(height: AppSpacing.md),
              _SearchRow(controller: _searchController, activeFilters: _filters.activeCount, onChanged: _onSearchChanged, onClear: _clearSearch, onFilters: _showFilters),
              _ActiveFilterChips(filters: _filters, onChanged: (next) => setState(() => _filters = next), roleName: (code) => _roleName(context, code)),
              const SizedBox(height: AppSpacing.md),
              _Results(
                filtered: _filtered,
                pageSize: _pageSize,
                onClearFilters: _clearAll,
                onOpen: widget.onOpen,
                now: widget.now,
                onPage: (page) {
                  context.read<UsersListBloc>().add(UsersPageSelected(page));
                  if (_scrollController.hasClients) _scrollController.jumpTo(0);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleName(BuildContext context, String code) => [for (final role in context.read<AssignableRolesCubit>().state.roles) if (role.code == code) role.name].firstOrNull ?? code;
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller, required this.activeFilters, required this.onChanged, required this.onClear, required this.onFilters});

  final TextEditingController controller;
  final int activeFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o correo…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: value.text.isEmpty ? null : IconButton(tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close_rounded), onPressed: onClear),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilterButton(count: activeFilters, onPressed: onFilters),
      ]);
}

/// Un chip por filtro puesto, que se quita con su equis.
class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filters, required this.onChanged, required this.roleName});

  final UsersFilters filters;
  final ValueChanged<UsersFilters> onChanged;
  final String Function(String code) roleName;

  @override
  Widget build(BuildContext context) {
    if (filters.activeCount == 0) return const SizedBox.shrink();
    final dates = filters.dates;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        if (filters.role != null) ActiveFilterChip(label: roleName(filters.role!), onRemove: () => onChanged(UsersFilters(isActive: filters.isActive, dates: filters.dates))),
        if (filters.isActive != null) ActiveFilterChip(label: filters.isActive! ? 'Activas' : 'Inactivas', onRemove: () => onChanged(UsersFilters(role: filters.role, dates: filters.dates))),
        if (dates != null) ActiveFilterChip(label: '${formatDate(dates.start)} – ${formatDate(dates.end)}', onRemove: () => onChanged(UsersFilters(role: filters.role, isActive: filters.isActive))),
      ]),
    );
  }
}

/// La lista con sus estados (cargando, error, vacío, datos) y el paginador.
class _Results extends StatelessWidget {
  const _Results({required this.filtered, required this.pageSize, required this.onClearFilters, required this.onPage, this.onOpen, this.now});

  final bool filtered;
  final int pageSize;
  final VoidCallback onClearFilters;
  final ValueChanged<int> onPage;
  final ValueChanged<ManagedUser>? onOpen;
  final DateTime? now;

  @override
  Widget build(BuildContext context) => BlocBuilder<UsersListBloc, UsersListState>(
        builder: (context, state) {
          final bloc = context.read<UsersListBloc>();
          if (state.status == UsersListStatus.loading) return const _ListSkeleton();
          if (state.status == UsersListStatus.failure) {
            return EmptyState(icon: Icons.cloud_off_outlined, title: 'No pudimos cargar los usuarios', message: state.failure?.message, actionLabel: 'Reintentar', onAction: () => bloc.add(const UsersListStarted()));
          }
          if (state.items.isEmpty) {
            return EmptyState(
              icon: filtered ? Icons.search_off_rounded : Icons.group_outlined,
              title: filtered ? 'Ningún usuario coincide con los filtros' : 'Aún no hay usuarios',
              message: filtered ? 'Prueba con otra búsqueda o quita los filtros.' : null,
              actionLabel: filtered ? 'Quitar filtros' : null,
              onAction: filtered ? onClearFilters : null,
            );
          }
          final time = now ?? DateTime.now();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (state.loadingPage) const Padding(padding: EdgeInsets.only(bottom: 6), child: LinearProgressIndicator(minHeight: 2)),
            for (final user in state.items) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: UserCard(user: user, now: time, onTap: onOpen == null ? null : () => onOpen!(user))),
            const SizedBox(height: AppSpacing.md),
            Paginator(page: state.page, totalPages: state.totalPages, total: state.total, pageSize: pageSize, loading: state.loadingPage, onPage: onPage),
          ]);
        },
      );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Cargando usuarios',
        child: Column(children: [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: Skeleton(height: 104, radius: AppRadius.md))]),
      );
}
