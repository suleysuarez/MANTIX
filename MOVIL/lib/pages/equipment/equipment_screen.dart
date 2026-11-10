import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/equipment/equipment_catalog_bloc.dart';
import '../../bloc/equipment/equipment_list_bloc.dart';
import '../../bloc/equipment/equipment_summary_bloc.dart';
import '../../core/format/equipment_meta.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../widgets/equipment/equipment_detail_sheet.dart';
import '../../widgets/equipment/equipment_list_views.dart';
import '../../widgets/shared/filter_widgets.dart';
import '../../widgets/shared/multi_select_sheet.dart';
import '../../widgets/shared/paginator.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/error_state.dart';
import '../../widgets/shared/skeleton.dart';
import '../../widgets/shared/status_message.dart';
import 'create_equipment_screen.dart';

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
  List<int> _typeIds = const [];
  int? _highlightId;
  Timer? _highlightTimer;
  StreamSubscription<Equipment>? _createdSub;
  DateTimeRange? _dates;
  String _search = '';
  EquipmentView _view = EquipmentView.table;
  int _pageSize = 10;

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
    _createdSub = _repository.created.listen(_onCreated);
  }

  /// Un equipo recién registrado: se limpian filtros y búsqueda, la lista vuelve a la página 1
  /// (orden por creación descendente, así que sale primero) y se resalta unos segundos.
  void _onCreated(Equipment created) {
    _debounce?.cancel();
    _searchController.clear();
    _highlightTimer?.cancel();
    _applyFilters(() {
      _search = '';
      _typeIds = const [];
      _statuses = null;
      _dates = null;
      _highlightId = created.id;
    });
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  EquipmentListBloc _newListBloc() => EquipmentListBloc(
        repository: _repository,
        statuses: _statuses,
        search: _search,
        typeIds: _typeIds,
        dateFrom: _dates?.start,
        dateTo: _dates?.end,
        pageSize: _pageSize,
      )..add(const EquipmentListStarted());

  @override
  void dispose() {
    _debounce?.cancel();
    _highlightTimer?.cancel();
    unawaited(_createdSub?.cancel());
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
      _typeIds = const [];
      _statuses = null;
      _dates = null;
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

  Set<String> get _statusSet => _statuses == null ? <String>{} : _statuses!.split(',').toSet();

  /// Filtros activos: categorías y estados elegidos, y uno más si hay fechas.
  int get _activeFilterCount => _typeIds.length + _statusSet.length + (_dates == null ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const StatusMessage(icon: Icons.devices_other_rounded, title: 'Equipos', message: 'No encontramos los datos de tu sesión.');
    }
    final filtered = _statuses != null || _typeIds.isNotEmpty || _dates != null || _search.isNotEmpty;
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
                FilterButton(count: _activeFilterCount, onPressed: _showFilters),
              ]),
              if (_activeFilterCount > 0) ...[
                const SizedBox(height: 8),
                _ActiveFilters(
                  types: _catalogBloc.state.types,
                  typeIds: _typeIds,
                  statuses: _statuses,
                  dates: _dates,
                  onClearType: (id) => _applyFilters(() => _typeIds = [for (final t in _typeIds) if (t != id) t]),
                  onClearStatus: () => _applyFilters(() => _statuses = null),
                  onClearDates: () => _applyFilters(() => _dates = null),
                ),
              ],
              const SizedBox(height: 10),
              _ViewToggle(view: _view, onChanged: (view) => setState(() => _view = view)),
              const SizedBox(height: 14),
              // Una clave por Bloc: al cambiar filtros o crear un equipo hay un Bloc nuevo y el listado
              // debe volver a suscribirse a él (si no, seguiría mostrando el anterior).
              _ListSection(
                key: ObjectKey(_listBloc),
                view: _view,
                pageSize: _pageSize,
                onPageSize: (size) => _applyFilters(() => _pageSize = size),
                filtered: filtered,
                highlightId: _highlightId,
                onResetFilters: _resetFilters,
              ),
            ],
          ),
        ),
        ),
      );
  }

  Future<void> _showFilters() async {
    var typeIds = {..._typeIds};
    var statuses = _statusSet;
    var dates = _dates;
    final types = _catalogBloc.state.types;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => FilterSheet(
          onReset: () => setSheet(() {
            typeIds = {};
            statuses = {};
            dates = null;
          }),
          onApply: () => Navigator.pop(sheetContext, true),
          children: [
            FilterTile(
              label: 'Categoría',
              icon: Icons.category_outlined,
              summary: typeIds.isEmpty ? null : [for (final t in types) if (typeIds.contains(t.id)) t.name].join(', '),
              onTap: () async {
                final picked = await showMultiSelectSheet<int>(
                  context,
                  title: 'Categoría',
                  options: [for (final t in types) FilterOption(t.id, t.name)],
                  selected: typeIds,
                );
                if (picked != null) setSheet(() => typeIds = picked);
              },
            ),
            FilterTile(
              label: 'Estado',
              icon: Icons.flag_outlined,
              summary: statuses.isEmpty ? null : [for (final s in knownEquipmentStatuses) if (statuses.contains(s)) equipmentStatusMeta(s).label].join(', '),
              onTap: () async {
                final picked = await showMultiSelectSheet<String>(
                  context,
                  title: 'Estado',
                  options: [for (final s in knownEquipmentStatuses) FilterOption(s, equipmentStatusMeta(s).label)],
                  selected: statuses,
                );
                if (picked != null) setSheet(() => statuses = picked);
              },
            ),
            DateRangeFilterField(label: 'Fecha de registro', value: dates, onChanged: (range) => setSheet(() => dates = range)),
          ],
        ),
      ),
    );
    if (applied != true || !mounted) return;
    _applyFilters(() {
      _typeIds = typeIds.toList()..sort();
      _statuses = statuses.isEmpty ? null : [for (final s in knownEquipmentStatuses) if (statuses.contains(s)) s].join(',');
      _dates = dates;
    });
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
          decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.devices_other_rounded, color: AppColors.steel, size: 24),
        ),
        const Spacer(),
        if (canCreate)
          Flexible(
            child: FilledButton.tonalIcon(
            onPressed: () => CreateEquipmentScreen.show(context),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Nuevo equipo', maxLines: 1, overflow: TextOverflow.ellipsis),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.mustard,
              foregroundColor: AppColors.navy,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      const Text('GESTIÓN DE EQUIPOS', style: TextStyle(color: AppColors.navy, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
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
          colors: EquipmentColors.info,
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
          colors: EquipmentColors.info,
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
          colors: EquipmentColors.info,
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
            border: Border.all(color: selected ? AppColors.mustard : AppColors.skyLight.withValues(alpha: .7), width: selected ? 2 : 1),
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
              Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 21, fontWeight: FontWeight.w900, height: 1.05)),
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

/// Filtros aplicados, cada uno con su equis para quitarlo sin abrir la hoja.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.types, required this.typeIds, required this.statuses, required this.dates, required this.onClearType, required this.onClearStatus, required this.onClearDates});

  final List<EquipmentType> types;
  final List<int> typeIds;
  final String? statuses;
  final DateTimeRange? dates;
  final ValueChanged<int> onClearType;
  final VoidCallback onClearStatus;
  final VoidCallback onClearDates;

  @override
  Widget build(BuildContext context) {
    final statusLabel = statuses == null ? null : [for (final s in statuses!.split(',')) knownEquipmentStatuses.contains(s) ? equipmentStatusMeta(s).label : s].join(', ');
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        for (final id in typeIds) ActiveFilterChip(label: types.where((t) => t.id == id).map((t) => t.name).firstOrNull ?? 'Categoría', onRemove: () => onClearType(id)),
        if (statusLabel != null) ActiveFilterChip(label: statusLabel, onRemove: onClearStatus),
        if (dates != null) ActiveFilterChip(label: '${formatDate(dates!.start)} – ${formatDate(dates!.end)}', onRemove: onClearDates),
      ]),
    );
  }
}

/// Alterna entre tabla y cuadrícula.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final EquipmentView view;
  final ValueChanged<EquipmentView> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .35), borderRadius: BorderRadius.circular(14)),
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
              Icon(icon, size: 18, color: selected ? AppColors.navy : AppColors.slate),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? AppColors.navy : AppColors.slate, fontSize: 13, fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      );
}

/// El listado propiamente dicho, con sus estados (cargando, error, vacío, datos) y la paginación.
class _ListSection extends StatelessWidget {
  const _ListSection({super.key, required this.view, required this.pageSize, required this.onPageSize, required this.filtered, required this.onResetFilters, this.highlightId});

  final EquipmentView view;
  final int pageSize;
  final ValueChanged<int> onPageSize;
  final bool filtered;
  final VoidCallback onResetFilters;
  final int? highlightId;

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
            if (view == EquipmentView.table) EquipmentTable(items: state.items, onOpen: open, highlightId: highlightId) else EquipmentGrid(items: state.items, onOpen: open, highlightId: highlightId),
            const SizedBox(height: 16),
            Paginator(
              page: state.page,
              totalPages: state.totalPages,
              total: state.total,
              shown: state.items.length,
              pageSize: pageSize,
              loading: state.loadingPage,
              onPage: (page) => bloc.add(EquipmentPageSelected(page)),
              onPageSize: onPageSize,
            ),
            const SizedBox(height: 24),
          ]);
        },
      );
}
