import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/equipment/equipment_catalog_bloc.dart';
import '../../bloc/equipment/equipment_list_bloc.dart';
import '../../bloc/equipment/equipment_summary_bloc.dart';
import '../../core/format/equipment_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../widgets/equipment/equipment_list_views.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/error_state.dart';
import '../../widgets/shared/skeleton.dart';
import '../../widgets/shared/status_message.dart';
import 'create_equipment_screen.dart';

/// Marca del desplegable de estado cuando el filtro viene de una tarjeta con varios estados.
const _multipleStatuses = '__multiple__';

/// Gestión de equipos: contadores por estado, filtros, búsqueda y listado en tabla o cuadrícula
/// con paginación.
class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  static const path = '/modulos/equipos';

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  /// Filtros elegidos: estado efímero de la pantalla. Cambiarlos crea un `EquipmentListBloc` nuevo.
  String? _statuses;
  int? _typeId;
  String _search = '';
  EquipmentView _view = EquipmentView.table;
  static const int _pageSize = 10;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  late final EquipmentRepository _repository;
  late final EquipmentSummaryBloc _summaryBloc;
  late final EquipmentCatalogBloc _catalogBloc;
  late EquipmentListBloc _listBloc;

  @override
  void initState() {
    super.initState();
    _repository = context.read<EquipmentRepository>();
    _summaryBloc = EquipmentSummaryBloc(repository: _repository)..add(const EquipmentSummaryStarted());
    _catalogBloc = EquipmentCatalogBloc(repository: _repository)..add(const EquipmentCatalogStarted());
    _listBloc = _newListBloc();
  }

  EquipmentListBloc _newListBloc() => EquipmentListBloc(
        repository: _repository,
        statuses: _statuses,
        search: _search,
        typeId: _typeId,
        pageSize: _pageSize,
      )..add(const EquipmentListStarted());

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    unawaited(_summaryBloc.close());
    unawaited(_catalogBloc.close());
    unawaited(_listBloc.close());
    super.dispose();
  }

  /// Aplica un cambio de filtro y empieza el listado de nuevo desde la página 1.
  void _applyFilters(void Function() change) {
    setState(() {
      change();
      final previous = _listBloc;
      _listBloc = _newListBloc();
      unawaited(previous.close());
    });
  }

  void _applySearch(String value) {
    final term = value.trim();
    if (mounted && term != _search) _applyFilters(() => _search = term);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _applySearch(value));
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _applySearch('');
  }

  void _resetFilters() {
    _debounce?.cancel();
    _searchController.clear();
    _applyFilters(() {
      _search = '';
      _typeId = null;
      _statuses = null;
    });
  }

  Future<void> _refresh() => Future.wait([_listBloc.refresh(), _summaryBloc.refresh()]);

  /// Tarjeta del resumen que coincide con el filtro de estado actual (`null` si ninguna).
  EquipmentGroup? get _activeGroup {
    final csv = _statuses;
    if (csv == null) return EquipmentGroup.all;
    final wanted = csv.split(',').toSet();
    for (final group in EquipmentGroup.values) {
      final statuses = group.statuses;
      if (statuses != null && statuses.length == wanted.length && statuses.toSet().containsAll(wanted)) return group;
    }
    return null;
  }

  String? get _statusDropdownValue {
    final csv = _statuses;
    if (csv == null) return null;
    return knownEquipmentStatuses.contains(csv) ? csv : _multipleStatuses;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const StatusMessage(icon: Icons.devices_other_rounded, title: 'Equipos', message: 'No encontramos los datos de tu sesión.');
    }
    final filtered = _statuses != null || _typeId != null || _search.isNotEmpty;
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _summaryBloc),
        BlocProvider.value(value: _catalogBloc),
        BlocProvider.value(value: _listBloc),
      ],
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: EquipmentScreen.path),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _Header(
                canCreate: profile.can('equipos:crear'),
                group: _activeGroup,
                onGroupSelected: (group) => _applyFilters(() => _statuses = group.filter),
              ),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: _SearchField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  _applySearch(value);
                },
                onClear: _clearSearch,
              )),
                const SizedBox(width: 8),
                Material(color: EquipmentColors.info.background, borderRadius: BorderRadius.circular(13), child: IconButton(tooltip: 'Filtros', onPressed: _showFilters, icon: Icon(Icons.filter_alt_rounded, color: EquipmentColors.info.foreground))),
              ]),
              const SizedBox(height: 10),
              _ViewToggle(view: _view, onChanged: (view) => setState(() => _view = view)),
              const SizedBox(height: 14),
              _ListSection(
                view: _view,
                pageSize: _pageSize,
                filtered: filtered,
                onResetFilters: _resetFilters,
              ),
            ],
          ),
        ),
        ),
      );
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => BlocProvider<EquipmentCatalogBloc>.value(
        value: _catalogBloc,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Filtros', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 14),
          _FilterRow(types: _catalogBloc.state.types, typeId: _typeId, statusValue: _statusDropdownValue,
            onType: (id) { _applyFilters(() => _typeId = id); Navigator.pop(sheetContext); },
            onStatus: (status) { _applyFilters(() => _statuses = status); Navigator.pop(sheetContext); },
            onReset: () { _resetFilters(); Navigator.pop(sheetContext); }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group, required this.onGroupSelected, required this.canCreate});

  /// Muestra el botón «Nuevo equipo» (permiso `equipos:crear`).
  final bool canCreate;
  final EquipmentGroup? group;
  final ValueChanged<EquipmentGroup> onGroupSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: EquipmentColors.info.background, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.devices_other_rounded, color: EquipmentColors.info.foreground, size: 24),
        ),
        const Spacer(),
        if (canCreate)
          FilledButton.tonalIcon(
            onPressed: () => context.push(CreateEquipmentScreen.path),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Nuevo equipo'),
            style: FilledButton.styleFrom(
              backgroundColor: EquipmentColors.info.background,
              foregroundColor: EquipmentColors.info.foreground,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      const Text('GESTIÓN DE EQUIPOS', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
      const SizedBox(height: 6),
      const Text(
        'Administra los equipos tecnológicos, consulta sus especificaciones y realiza seguimiento a su ciclo de vida y mantenimiento.',
        style: TextStyle(color: AppColors.slate, fontSize: 12.5, height: 1.4),
      ),
      const SizedBox(height: 16),
      _SummaryCards(group: group, onGroupSelected: onGroupSelected),
    ],
  );
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.group, required this.onGroupSelected});

  final EquipmentGroup? group;
  final ValueChanged<EquipmentGroup> onGroupSelected;

  static String _rate(double? value) => value == null ? '–' : '${value.toStringAsFixed(1).replaceAll('.', ',')}% tasa';

  @override
  Widget build(BuildContext context) => BlocBuilder<EquipmentSummaryBloc, EquipmentSummaryState>(
    builder: (context, state) {
      final summary = state.summary;
      String value(EquipmentGroup g) => summary == null ? '–' : '${summary.count(g)}';
      final cards = [
        _SummaryCard(
          icon: Icons.devices_rounded,
          colors: EquipmentColors.info,
          badge: 'Total',
          value: value(EquipmentGroup.all),
          caption: 'Equipos registrados en inventario',
          action: 'Ver todo',
          actionIcon: Icons.arrow_forward_rounded,
          selected: group == EquipmentGroup.all,
          onTap: () => onGroupSelected(EquipmentGroup.all),
        ),
        _SummaryCard(
          icon: Icons.check_circle_outline_rounded,
          colors: EquipmentColors.ok,
          badge: summary == null ? 'Tasa' : _rate(summary.operationalRate),
          value: value(EquipmentGroup.operational),
          caption: 'Operativos y en disponibilidad',
          action: 'Filtrar operativos',
          actionIcon: Icons.filter_alt_outlined,
          selected: group == EquipmentGroup.operational,
          onTap: () => onGroupSelected(EquipmentGroup.operational),
        ),
        _SummaryCard(
          icon: Icons.build_outlined,
          colors: EquipmentColors.warn,
          badge: 'En curso',
          value: value(EquipmentGroup.maintenance),
          caption: 'Bajo revisión o soporte técnico',
          action: 'Ver equipos en mantenimiento',
          actionIcon: Icons.arrow_forward_rounded,
          selected: group == EquipmentGroup.maintenance,
          onTap: () => onGroupSelected(EquipmentGroup.maintenance),
        ),
        _SummaryCard(
          icon: Icons.warning_amber_rounded,
          colors: EquipmentColors.bad,
          badge: 'Crítico',
          value: value(EquipmentGroup.offline),
          caption: 'Dados de baja, retirados o extraviados',
          action: 'Revisar estos equipos',
          actionIcon: Icons.arrow_forward_rounded,
          selected: group == EquipmentGroup.offline,
          onTap: () => onGroupSelected(EquipmentGroup.offline),
        ),
      ];
      return Column(
        children: [
          GridView(
            // El alto crece con el tamaño de letra del sistema para que nada se corte.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, mainAxisExtent: 126 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6)),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cards,
          ),
          if (state.status == SummaryStatus.failure)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.slate),
                const SizedBox(width: 8),
                Expanded(child: Text('No pudimos cargar los contadores. ${state.failure?.message ?? ''}'.trim(), style: const TextStyle(color: AppColors.slate, fontSize: 11))),
                TextButton(onPressed: () => context.read<EquipmentSummaryBloc>().add(const EquipmentSummaryStarted()), child: const Text('Reintentar')),
              ]),
            ),
        ],
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.colors,
    required this.badge,
    required this.value,
    required this.caption,
    required this.action,
    required this.actionIcon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final ChipColors colors;
  final String badge;
  final String value;
  final String caption;
  final String action;
  final IconData actionIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? colors.dot : const Color(0xFFE5EEF6), width: selected ? 1.6 : 1),
            boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: colors.dot, size: 17),
                ),
                const Spacer(),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(20)),
                    child: Text(badge, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.foreground, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Color(0xFF0B1F3A), fontSize: 21, fontWeight: FontWeight.w900, height: 1.05)),
              const SizedBox(height: 2),
              Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 10, height: 1.2)),
              const Spacer(),
              const Divider(height: 8, thickness: 1, color: Color(0xFFEEF3F8)),
              Row(children: [
                Expanded(child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.foreground, fontSize: 10.5, fontWeight: FontWeight.w800))),
                const SizedBox(width: 4),
                Icon(actionIcon, size: 14, color: colors.foreground),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.onChanged, required this.onSubmitted, required this.onClear});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => TextField(
      controller: controller,
      focusNode: focusNode,
      maxLength: 100,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        counterText: '',
        hintText: 'Buscar por código, serie, marca o modelo…',
        hintStyle: const TextStyle(color: AppColors.slate, fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate),
        suffixIcon: value.text.isEmpty ? null : IconButton(tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClear),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5EEF6))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5EEF6))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: EquipmentColors.info.dot, width: 1.6)),
      ),
    ),
  );
}

/// Categoría y estado como desplegables, y el botón que limpia todos los filtros.
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.types, required this.typeId, required this.statusValue, required this.onType, required this.onStatus, required this.onReset});

  final List<EquipmentType> types;
  final int? typeId;
  final String? statusValue;
  final ValueChanged<int?> onType;
  final ValueChanged<String?> onStatus;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: _FilterBox<int?>(
            label: 'Categoría',
            value: types.any((type) => type.id == typeId) ? typeId : null,
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todas las categorías', overflow: TextOverflow.ellipsis)),
              for (final type in types) DropdownMenuItem<int?>(value: type.id, child: Text(type.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onType,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FilterBox<String?>(
            label: 'Estado',
            value: statusValue,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos los estados', overflow: TextOverflow.ellipsis)),
              for (final status in knownEquipmentStatuses) DropdownMenuItem<String?>(value: status, child: Text(equipmentStatusMeta(status).label, overflow: TextOverflow.ellipsis)),
              if (statusValue == _multipleStatuses) const DropdownMenuItem<String?>(value: _multipleStatuses, child: Text('Varios estados', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) {
              if (value != _multipleStatuses) onStatus(value);
            },
          ),
        ),
        const SizedBox(width: 4),
        IconButton(tooltip: 'Limpiar filtros', onPressed: onReset, icon: const Icon(Icons.refresh_rounded), color: AppColors.slate),
      ]);
}

class _FilterBox<T> extends StatelessWidget {
  const _FilterBox({required this.label, required this.value, required this.items, required this.onChanged});

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5EEF6))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: value,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.slate),
              style: const TextStyle(color: Color(0xFF334155), fontSize: 13, fontWeight: FontWeight.w600),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      );
}

/// Alterna entre tabla y cuadrícula.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final EquipmentView view;
  final ValueChanged<EquipmentView> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFEAF2FA), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(child: _ViewOption(label: 'Tabla', icon: Icons.table_rows_rounded, selected: view == EquipmentView.table, onTap: () => onChanged(EquipmentView.table))),
          Expanded(child: _ViewOption(label: 'Cuadrícula', icon: Icons.grid_view_rounded, selected: view == EquipmentView.grid, onTap: () => onChanged(EquipmentView.grid))),
        ]),
      );
}

class _ViewOption extends StatelessWidget {
  const _ViewOption({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 40,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected ? const [BoxShadow(color: Color(0x140B1F3A), blurRadius: 6, offset: Offset(0, 2))] : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: selected ? EquipmentColors.info.foreground : AppColors.slate),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? const Color(0xFF0B1F3A) : AppColors.slate, fontSize: 13, fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      );
}

/// El listado propiamente dicho, con sus estados (cargando, error, vacío, datos) y la paginación.
class _ListSection extends StatelessWidget {
  const _ListSection({required this.view, required this.pageSize, required this.filtered, required this.onResetFilters});

  final EquipmentView view;
  final int pageSize;
  final bool filtered;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) => BlocBuilder<EquipmentListBloc, EquipmentListState>(
        builder: (context, state) {
          final bloc = context.read<EquipmentListBloc>();
          if (state.status == EquipmentListStatus.loading) return const SizedBox(height: 320, child: SkeletonList());
          if (state.status == EquipmentListStatus.failure) {
            return SizedBox(height: 340, child: ErrorState(failure: state.failure!, onRetry: () => bloc.add(const EquipmentListRefreshed())));
          }
          if (state.items.isEmpty) {
            return SizedBox(
              height: 340,
              child: EmptyState(
                icon: Icons.devices_other_rounded,
                title: filtered ? 'Ningún equipo coincide con los filtros' : 'Aún no hay equipos registrados',
                message: filtered ? 'Prueba con otra búsqueda o muestra todo el catálogo.' : null,
                actionLabel: filtered ? 'Ver todo el catálogo' : null,
                onAction: filtered ? onResetFilters : null,
              ),
            );
          }
          void open(Equipment item) => showEquipmentDetails(context, item);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (state.loadingPage) const Padding(padding: EdgeInsets.only(bottom: 6), child: LinearProgressIndicator(minHeight: 2)),
            if (view == EquipmentView.table) EquipmentTable(items: state.items, onOpen: open) else EquipmentGrid(items: state.items, onOpen: open),
            const SizedBox(height: 16),
            EquipmentPagination(
              page: state.page,
              totalPages: state.totalPages,
              total: state.total,
              shown: state.items.length,
              pageSize: pageSize,
              onPage: (page) => bloc.add(EquipmentPageSelected(page)),
            ),
            const SizedBox(height: 24),
          ]);
        },
      );
}
